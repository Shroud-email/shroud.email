import { effect, frame, init, surface } from "vgpu";

const shader = `struct Params {
  resolution: vec2f,
  time: f32,
  wakes: array<vec4f, 24>,
}
@group(0) @binding(0) var<uniform> params: Params;

fn hash(p: vec2f) -> f32 {
  var p3 = fract(vec3f(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2f) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(cell), hash(cell + vec2f(1, 0)), u.x),
    mix(hash(cell + vec2f(0, 1)), hash(cell + vec2f(1, 1)), u.x), u.y);
}

fn fbm(point: vec2f) -> f32 {
  var p = point;
  var value = 0.0;
  var amplitude = 0.55;
  let rotation = mat2x2f(0.8, 0.6, -0.6, 0.8);
  for (var i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = rotation * p * 2.03 + vec2f(17.1, 9.2);
    amplitude *= 0.32;
  }
  return value;
}

// The curl of a compact stream function moves fog without compressing it.
fn flow(point: vec2f, aspect: vec2f) -> vec2f {
  var velocity = vec2f(0.0);
  for (var i = 0; i < 24; i++) {
    let wake = params.wakes[i];
    let delta = point - (wake.xy - 0.5) * aspect;
    let radius = mix(0.045, 0.11, smoothstep(0.0, 0.012, length(wake.zw)));
    let falloff = max(0.0, 1.0 - dot(delta, delta) / (radius * radius));
    let stream = wake.z * delta.y - wake.w * delta.x;
    velocity += wake.zw * falloff * falloff * falloff
      - vec2f(delta.y, -delta.x) * stream * (6.0 / (radius * radius)) * falloff * falloff;
  }
  return velocity;
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = vec2f(params.resolution.x / params.resolution.y, 1.0);
  let t = params.time * 0.035;
  let p = (uv - 0.5) * aspect;
  let step = 1.0 / 8.0;
  var source = p;
  // Midpoint backtracing bends wisps around the pointer without folding the texture.
  for (var i = 0; i < 8; i++) {
    let midpoint = source - flow(source, aspect) * step * 0.5;
    source -= flow(midpoint, aspect) * step;
  }
  let displacement = p - source;
  var color = vec3f(0.055, 0.083, 0.14);
  // Composite soft banks at different depths; foreground mist moves most.
  for (var layer = 0; layer < 4; layer++) {
    let depth = f32(layer);
    let drift = vec2f(t * (0.4 + depth * 0.13), -t * 0.18);
    let point = (p - displacement * (0.35 + depth * 0.25)) * (2.4 + depth * 0.8)
      + vec2f(depth * 13.7, depth * 7.9) + drift;
    let warp = vec2f(noise(point * 0.6 + t * 0.2), noise(point * 0.6 + 8.4));
    let density = fbm(point + warp * 0.45);
    let opacity = smoothstep(0.24, 0.70, density) * 0.34;
    color = mix(color, vec3f(0.26, 0.32, 0.40) + depth * 0.01, opacity);
  }
  let vignette = 1.0 - 0.18 * dot(uv - 0.5, uv - 0.5);
  let grain = (hash(uv * params.resolution) - 0.5) / 255.0;
  return vec4f(color * vignette + grain, 1.0);
}
`;

class PointerWakes {
  constructor() {
    this.wakes = Array.from({ length: 24 }, () => [0, 0, 0, 0]);
    this.index = 0;
    this.remainder = 0;
    this.pointer = null;
    this.sample = null;
  }

  sync(pointer) {
    this.pointer = pointer && [...pointer];
    this.sample = pointer && [...pointer];
    this.remainder = 0;
  }

  step(dt, pointer, aspect) {
    const decay = Math.exp(-dt * 1.3);
    for (const wake of this.wakes) {
      const drift = ((1 - decay) / 1.3) * 0.9;
      wake[0] += (wake[2] * drift) / aspect;
      wake[1] += wake[3] * drift;
      wake[2] *= decay;
      wake[3] *= decay;
    }
    if (pointer && this.sample) {
      const dx = (pointer[0] - this.sample[0]) * aspect;
      const dy = pointer[1] - this.sample[1];
      const distance = Math.hypot(dx, dy);
      if (distance > 1e-4) {
        const count = Math.min(12, Math.ceil(distance / 0.025));
        const strength = (Math.min(distance, 0.18) * 2.5) / count;
        const scale = Math.min(strength, 0.012) / distance;
        for (let i = 1; i <= count; i++) {
          this.wakes[this.index] = [
            this.sample[0] + ((pointer[0] - this.sample[0]) * i) / count,
            this.sample[1] + ((pointer[1] - this.sample[1]) * i) / count,
            dx * scale,
            dy * scale,
          ];
          this.index = (this.index + 1) % this.wakes.length;
        }
      }
    }
    this.sample = pointer && [...pointer];
  }

  advance(dt, pointer, aspect) {
    if (!!this.pointer !== !!pointer) this.sync(pointer);
    const step = 1 / 60;
    let elapsed = step - this.remainder;
    for (; elapsed <= dt + 1e-9; elapsed += step) {
      const fraction = Math.min(1, elapsed / dt);
      const sample = pointer && [
        this.pointer[0] + (pointer[0] - this.pointer[0]) * fraction,
        this.pointer[1] + (pointer[1] - this.pointer[1]) * fraction,
      ];
      this.step(step, sample, aspect);
    }
    this.remainder = Math.max(0, dt - (elapsed - step));
    this.pointer = pointer && [...pointer];
  }
}

export async function initFog() {
  const scene = document.querySelector("#fog");
  if (!scene) return;
  const canvas = scene.querySelector("canvas");
  const status = scene.querySelector("#fog-status");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const wakes = new PointerWakes();
  let gpu;
  let target;
  let fog;
  let animation;
  let unavailable = false;
  let pointer = null;
  let time = 0;
  let previous = performance.now();
  let dirty = true;

  function fail() {
    if (unavailable) return;
    unavailable = true;
    scene.dataset.state = "unavailable";
    status.textContent = "WebGPU unavailable";
    cancelAnimationFrame(animation);
    gpu?.dispose();
  }

  function render() {
    if (unavailable) return;
    try {
      fog.set({
        params: { time, wakes: wakes.wakes, resolution: target.size },
      });
      frame(gpu, (frame) => frame.pass(target, fog));
    } catch {
      fail();
    }
  }

  function tick(now) {
    const elapsed = (now - previous) / 1000;
    previous = now;
    if (document.hidden || elapsed > 0.25) {
      pointer = null;
      wakes.sync(null);
    } else if (reducedMotion.matches) {
      wakes.sync(pointer);
    } else {
      const dt = Math.min(elapsed, 0.1);
      time += dt;
      wakes.advance(dt, pointer, scene.clientWidth / scene.clientHeight);
      dirty = true;
    }
    if (dirty && !document.hidden) {
      render();
      dirty = false;
    }
    if (!unavailable) animation = requestAnimationFrame(tick);
  }

  scene.addEventListener("pointermove", (event) => {
    if (unavailable) return;
    const bounds = scene.getBoundingClientRect();
    pointer = [
      (event.clientX - bounds.left) / bounds.width,
      (event.clientY - bounds.top) / bounds.height,
    ];
  });
  scene.addEventListener("pointerleave", () => {
    pointer = null;
  });
  window.addEventListener("resize", () => {
    pointer = null;
    wakes.sync(null);
    dirty = true;
  });
  window.addEventListener(
    "pagehide",
    () => {
      cancelAnimationFrame(animation);
      gpu?.dispose();
    },
    { once: true },
  );

  try {
    gpu = await init();
    gpu.onError(fail);
    gpu.gpu.lost.then(fail);
    target = surface(gpu, canvas, { dpr: 1 });
    fog = effect(gpu, shader, {
      set: { params: { resolution: target.size, wakes: wakes.wakes, time: 0 } },
    });
    target.onResize(() => fog.set({ params: { resolution: target.size } }));
    render();
    await gpu.settled();
    if (!unavailable) {
      scene.dataset.state = "ready";
      previous = performance.now();
      animation = requestAnimationFrame(tick);
    }
  } catch {
    fail();
  }
}

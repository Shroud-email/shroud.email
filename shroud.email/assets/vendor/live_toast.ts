// Vendored from live_toast 0.11.0 (MIT), assets/js/live_toast/live_toast.ts.
// Local fixes: lifecycle-owned events/timers and resize-aware stack geometry.
// Native transform/opacity keyframes use Motion's lightweight mini entry point.
// Keep these fixes when upgrading LiveToast. See live_toast.LICENSE.md.
import { animate } from 'motion/mini'
import type { ViewHook } from 'phoenix_live_view'

function isHidden(el: HTMLElement | null) {
  if (el === null) {
    return true
  }

  return el.offsetParent === null
}

function isFlash(el: HTMLElement) {
  return el.dataset.component === 'flash'
}

function parseDuration(value: string | undefined, fallback: number) {
  if (value === undefined) {
    return fallback
  }

  if (value === 'Infinity') {
    return Number.POSITIVE_INFINITY
  }

  const parsed = Number.parseInt(value)

  return Number.isNaN(parsed) ? fallback : parsed
}

// number of flashes that aren't hidden
function flashCount() {
  let num = 0

  if (!isHidden(document.getElementById('server-error'))) {
    num += 1
  }

  if (!isHidden(document.getElementById('client-error'))) {
    num += 1
  }

  if (!isHidden(document.getElementById('flash-info'))) {
    num += 1
  }

  if (!isHidden(document.getElementById('flash-error'))) {
    num += 1
  }

  return num
}

// time in ms to wait before removal, but after animation
const removalTime = 5
// animation time in ms
const animationTime = 550
// whether flashes should be counted in maxItems
const maxItemsIgnoresFlashes = true
// gap in px between toasts
const gap = 15
const dismissEvent = 'live-toast-dismiss'
const clientToastEvent = 'live-toast:add'
const remainingSelector = '[data-live-toast-remaining]'

let lastTS: HTMLElement[] = []

type DismissTimer = {
  cancel: () => void
}

type ToastElement = HTMLElement & {
  order: number
  targetDestination: string
  targetOpacity: number
}

export type ClientToastOptions = {
  duration?: number | 'infinity'
  metadata?: Record<string, unknown>
  title?: string
}

type ClientToastRequest = {
  kind: string
  message: string
  options: ClientToastOptions
}

const dismissTimers = new WeakMap<object, DismissTimer>()
const groups = new WeakMap<HTMLElement, ViewHook>()

function asToastElement(el: HTMLElement): ToastElement {
  return el as ToastElement
}

export function addToast(
  kind: string,
  message: string,
  options: ClientToastOptions = {}
) {
  document
    .getElementById('toast-group')
    ?.dispatchEvent(
      new CustomEvent<ClientToastRequest>(clientToastEvent, {
        detail: { kind, message, options }
      })
    )
}

function doAnimations(
  this: ViewHook,
  animationDelayTime: number,
  maxItems: number,
  elToRemove?: HTMLElement
) {
  const ts: ToastElement[] = []
  let toasts = Array.from(
    document.querySelectorAll<ToastElement>(
      '#toast-group [phx-hook="LiveToast"]'
    )
  )
    .map(t => {
      if (isHidden(t)) {
        return null
      }

      return t
    })
    .filter(Boolean)
    .filter(t => t!.dataset.liveToastDismissing !== 'true')
    // reverse
    .reverse()

  if (elToRemove) {
    toasts = toasts.filter(t => t !== elToRemove)
  }

  // Traverse through all toasts, in order they appear in the dom, for which they are NOT hidden, and assign el.order to
  // their index
  for (let i = 0; i < toasts.length; i++) {
    const toast = toasts[i]!
    if (isHidden(toast)) {
      continue
    }
    toast.order = i

    ts[i] = toast
  }

  // now loop through ts and animate each toast to its position
  for (let i = 0; i < ts.length; i++) {
    const max = maxItemsIgnoresFlashes ? maxItems + flashCount() : maxItems

    const toast = ts[i]

    let direction = ''

    if (
      toast.dataset.corner === 'bottom_left' ||
      toast.dataset.corner === 'bottom_center' ||
      toast.dataset.corner === 'bottom_right'
    ) {
      direction = '-'
    }

    // Calculate the translateY value with gap
    // now that they can be different heights, we need to actually caluclate the real heights and add them up.
    let val = 0

    for (let j = 0; j < toast.order; j++) {
      val += ts[j].offsetHeight + gap
    }

    // Calculate opacity based on position
    const opacity = toast.order > max ? 0 : 1 - (toast.order - max + 1)

    // also if this item moved past the max limit, disable click events on it
    if (toast.order >= max) {
      toast.classList.remove('pointer-events-auto')
    } else {
      toast.classList.add('pointer-events-auto')
    }

    const keyframes = { transform: [`translateY(${direction}${val}px)`], opacity: [opacity] }

    // if element is entering for the first time, start below the fold
    if (toast.order === 0 && lastTS.includes(toast) === false) {
      const val = toast.offsetHeight + gap
      const oppositeDirection = direction === '-' ? '' : '-'
      keyframes.transform.unshift(`translateY(${oppositeDirection}${val}px)`)

      keyframes.opacity.unshift(0)
    }

    const duration = animationTime / 1000

    // as of right now this is not exposed to end users, but
    // it's 'plumbed out' if we want to make it so in the future
    const delayTime = Number.parseInt(this.el.dataset.delay || '0') / 1000

    const destination = `${direction}${val}px`
    if (toast.targetDestination !== destination || toast.targetOpacity !== opacity) {
      this.animateToast(toast, keyframes, {
        duration,
        ease: [0.22, 1.0, 0.36, 1.0],
        delay: delayTime
      })
      toast.targetDestination = destination
      toast.targetOpacity = opacity
    }
    toast.order += 1

    // decrease z-index
    toast.style.zIndex = (50 - toast.order).toString()

    // Overflow timers belong to the group, not whichever toast caused a layout.
    // Repeated resize/layout passes must not enqueue duplicate removal requests.
    const group = groups.get(document.getElementById('toast-group')!)
    if (group) {
      if (toast.order > max && !group.overflowTimers.has(toast)) {
        group.overflowTimers.set(toast, window.setTimeout(() => {
          group.overflowTimers.delete(toast)
          if (toast.isConnected && toast.order > max) {
            group.pushEventTo(group.el, 'clear', { id: toast.id })
          }
        }, animationDelayTime + removalTime))
      } else if (toast.order <= max) {
        window.clearTimeout(group.overflowTimers.get(toast))
        group.overflowTimers.delete(toast)
      }
    }

    lastTS = ts
  }
}

function toastGroupTarget(el: HTMLElement) {
  const streamContainer = el.closest<HTMLElement>('[phx-update="stream"]')
  const toastGroup = streamContainer?.parentElement

  return toastGroup || '#toast-group'
}

async function animateOut(this: ViewHook) {
  const toast = asToastElement(this.el)
  const val = (toast.order - 2) * 100 + (toast.order - 2) * gap

  let direction = ''

  if (
    this.el.dataset.corner === 'bottom_left' ||
    this.el.dataset.corner === 'bottom_center' ||
    this.el.dataset.corner === 'bottom_right'
  ) {
    direction = '-'
  }

  const animation = this.animateToast(
    this.el,
    { transform: `translateY(${direction}${val}%)`, opacity: 0 },
    {
      opacity: {
        duration: 0.2,
        ease: 'ease-out'
      },
      duration: 0.3,
      ease: 'ease-out'
    }
  )

  await animation.finished
}

async function dismissToast(
  this: ViewHook,
  animationDelayTime: number,
  maxItems: number
) {
  if (this.el.dataset.liveToastDismissing === 'true') {
    return
  }

  this.el.dataset.liveToastDismissing = 'true'
  dismissTimers.get(this)?.cancel()
  dismissTimers.delete(this)

  doAnimations.bind(this, animationDelayTime, maxItems, this.el)()
  await animateOut.bind(this)()

  if (this.el.isConnected) {
    this.pushEventTo(toastGroupTarget(this.el), 'clear', { id: this.el.id })
  }
}

function isInteracting(el: HTMLElement) {
  return el.matches(':hover') || el.matches(':focus-within')
}

function renderRemaining(el: HTMLElement, remaining: number, paused: boolean) {
  const output = el.querySelector<HTMLElement>(remainingSelector)

  if (!output) {
    return
  }

  output.textContent = Math.ceil(remaining / 1000).toString()
  output.dataset.paused = paused.toString()
}

function startDismissTimer(
  this: ViewHook,
  duration: number,
  animationDelayTime: number,
  maxItems: number
) {
  let remaining = duration
  let startedAt: number | undefined
  let timer: number | undefined
  let displayTimer: number | undefined

  const currentRemaining = () => {
    if (startedAt === undefined) {
      return remaining
    }

    return Math.max(0, remaining - (performance.now() - startedAt))
  }

  const clearTimers = () => {
    if (timer !== undefined) {
      window.clearTimeout(timer)
      timer = undefined
    }

    if (displayTimer !== undefined) {
      window.clearInterval(displayTimer)
      displayTimer = undefined
    }
  }

  const pause = () => {
    if (startedAt === undefined) {
      return
    }

    remaining = currentRemaining()
    startedAt = undefined
    clearTimers()
    renderRemaining(this.el, remaining, true)
  }

  const resume = () => {
    if (timer || isInteracting(this.el)) {
      return
    }

    startedAt = performance.now()
    renderRemaining(this.el, remaining, false)

    if (this.el.querySelector(remainingSelector)) {
      displayTimer = window.setInterval(() => {
        renderRemaining(this.el, currentRemaining(), false)
      }, 100)
    }

    timer = window.setTimeout(async () => {
      clearTimers()
      remaining = 0
      startedAt = undefined
      renderRemaining(this.el, remaining, false)

      await dismissToast.bind(this)(animationDelayTime, maxItems)
    }, remaining + removalTime)
  }

  const cancel = () => {
    clearTimers()
    this.el.removeEventListener('mouseenter', pause)
    this.el.removeEventListener('focusin', pause)
    this.el.removeEventListener('mouseleave', resume)
    this.el.removeEventListener('focusout', resume)
  }

  this.el.addEventListener('mouseenter', pause)
  this.el.addEventListener('focusin', pause)
  this.el.addEventListener('mouseleave', resume)
  this.el.addEventListener('focusout', resume)

  dismissTimers.set(this, { cancel })
  resume()
}

// Create the Phoenix Hoook for live_toast.
// You can set custom animation durations.
export function createLiveToastHook(duration = 6000, maxItems = 3, animateToast = animate) {
  return {
    animateToast,
    destroyed(this: ViewHook) {
      this.active = false
      if (this.el.dataset.liveToastGroup === 'true') {
        this.resizeObserver.disconnect()
        this.breakpoint.removeEventListener('change', this.layout)
        this.el.removeEventListener(clientToastEvent, this.clientToastListener)
        this.removeHandleEvent(this.clearFlashRef)
        for (const timer of this.overflowTimers.values()) window.clearTimeout(timer)
        groups.delete(this.el)
        lastTS = []
        return
      }

      this.resizeObserver?.disconnect()
      if (this.dismissRef) this.removeHandleEvent(this.dismissRef)
      window.clearTimeout(this.flashTimer)
      dismissTimers.get(this)?.cancel()
      dismissTimers.delete(this)
      const group = groups.get(document.getElementById('toast-group')!)
      if (group) {
        window.clearTimeout(group.overflowTimers.get(this.el))
        group.overflowTimers.delete(this.el)
      }
      group?.layout()
    },
    updated(this: ViewHook) {
      if (this.el.dataset.liveToastGroup === 'true') {
        this.layout()
        return
      }

      groups.get(document.getElementById('toast-group')!)?.layout()
    },
    mounted(this: ViewHook) {
      this.active = true
      if (this.el.dataset.liveToastGroup === 'true') {
        groups.set(this.el, this)
        this.overflowTimers = new Map()
        this.breakpoint = window.matchMedia('(min-width: 640px)')
        this.layout = () => {
          if (!this.active) return
          const corner = this.breakpoint.matches ? 'top_right' : 'bottom_center'
          for (const toast of this.el.querySelectorAll<HTMLElement>('[data-kind]')) {
            toast.dataset.corner = corner
          }
          doAnimations.call(this, duration, maxItems)
        }
        this.resizeObserver = new ResizeObserver(this.layout)
        this.resizeObserver.observe(this.el)
        this.breakpoint.addEventListener('change', this.layout)
        this.clearFlashRef = this.handleEvent('clear-flash', ({ key }: { key: string }) => {
          this.pushEvent('lv:clear-flash', { key })
        })
        this.clientToastListener = (event: Event) => {
          const request = (event as CustomEvent<ClientToastRequest>).detail

          if (!request) {
            return
          }

          this.pushEventTo(this.el, 'add_toast', {
            kind: request.kind,
            message: request.message,
            options: request.options
          })
        }

        this.el.addEventListener(clientToastEvent, this.clientToastListener)

        return
      }

      this.el.addEventListener('show-error', async _event => {
        const delayTime = Number.parseInt(this.el.dataset.delay || '0')
        await new Promise(resolve => setTimeout(resolve, delayTime))

        // todo: in the future use this to execute the data-disconnected command
        // https://elixirforum.com/t/can-we-use-liveview-js-commands-inside-a-hook/67324/8

        // const command = this.el.getAttribute('data-disconnected')
        // this.liveSocket.execJS(this.el, command)

        // (don't want to do this quite yet because 1.0 is pretty new)
        // also repeat this on hide.

        this.el.removeAttribute('hidden')
        this.el.style.display = 'flex'
      })

      this.el.addEventListener('hide-error', async _event => {
        this.el.style.display = 'none'
      })

      // for the special flashes, check if they are visible, and if not, return early out of here.
      if (['server-error', 'client-error'].includes(this.el.id)) {
        if (isHidden(document.getElementById(this.el.id))) {
          return
        }
      }

      this.el.addEventListener('flash-leave', async () => {
        this.el.dataset.liveToastDismissing = 'true'
        doAnimations.bind(this, duration, maxItems, this.el)()
        await animateOut.bind(this)()
      })

      this.el.addEventListener(dismissEvent, async event => {
        event.stopPropagation()

        await dismissToast.bind(this)(duration, maxItems)
      })

      this.dismissRef = this.handleEvent(dismissEvent, async (detail: { id?: string; uuid?: string }) => {
        const id = detail.id || `toast-${detail.uuid}`

        if (id === this.el.id) {
          await dismissToast.bind(this)(duration, maxItems)
        }
      })

      // begin actually showing the toast through this call to the animation function
      const group = groups.get(document.getElementById('toast-group')!)
      this.resizeObserver = new ResizeObserver(() => group?.layout())
      this.resizeObserver.observe(this.el)
      group?.layout()

      const durationOverride = parseDuration(this.el.dataset.duration, duration)

      let flashDuration = undefined
      if (this.el.dataset.flashDuration !== undefined) {
        flashDuration = Number.parseInt(this.el.dataset.flashDuration)
      }

      // skip the removal code if this is a flash, if autoHideFlash is nullish
      if (isFlash(this.el) && !flashDuration) {
        return
      }

      // this could be condensed
      if (flashDuration) {
        // do stuff
        this.flashTimer = window.setTimeout(async () => {
          // animate this element sliding down, opacity to 0, with delay time
          await animateOut.bind(this)()

          const kind = this.el.dataset.kind

          if (kind && this.el.isConnected) {
            this.pushEvent('lv:clear-flash', { key: kind })
          }
        }, flashDuration + removalTime)
      } else {
        if (Number.isFinite(durationOverride) && durationOverride > 0) {
          startDismissTimer.bind(this)(durationOverride, duration, maxItems)
        }
      }
    }
  }
}

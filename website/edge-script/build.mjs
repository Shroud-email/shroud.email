// Bundles the edge script into a single file (dist/index.ts) that the bunny.net
// deploy action uploads. Mirrors the official BunnyWay/es-empty-script setup:
// esbuild + @luca/esbuild-deno-loader resolves the `https://esm.sh/...` import
// at build time and inlines it.
import * as esbuild from "npm:esbuild";
import { denoPlugins } from "jsr:@luca/esbuild-deno-loader";

await esbuild.build({
  plugins: [...denoPlugins()],
  entryPoints: ["./src/main.ts"],
  outfile: "./dist/index.ts",
  bundle: true,
  format: "esm",
});

esbuild.stop();

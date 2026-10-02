// Match the website edge script's single-file Bunny deployment format.
import * as esbuild from "esbuild";
import { denoPlugins } from "@luca/esbuild-deno-loader";

await esbuild.build({
  plugins: [...denoPlugins({ configPath: `${Deno.cwd()}/deno.json` })],
  entryPoints: ["./src/main.ts"],
  outfile: "./dist/index.ts",
  bundle: true,
  format: "esm",
});

esbuild.stop();

import * as BunnySDK from "https://esm.sh/@bunny.net/edgescript-sdk@0.12.0";
import { resolveDirectoryIndex, rewritePricing } from "./pricing.ts";

console.log(
  "shroud-pricing",
  JSON.stringify({
    revision: "directory-index-v3",
    stage: "script-start",
    sdk: "0.12.0",
    nativeBunny: "Bunny" in globalThis,
  }),
);

// Only used for local development; production uses the Pull Zone's origin.
BunnySDK.net.http
  .servePullZone({ url: "https://shroud.email/" })
  .onOriginRequest(resolveDirectoryIndex)
  .onOriginResponse(rewritePricing);

console.log(
  "shroud-pricing",
  JSON.stringify({
    revision: "directory-index-v3",
    stage: "middleware-registered",
  }),
);

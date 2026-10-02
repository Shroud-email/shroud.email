import * as BunnySDK from "https://esm.sh/@bunny.net/edgescript-sdk@0.12.0";
import {
  disableHtmlRanges,
  PRICING_REVISION,
  rewritePricing,
} from "./pricing.ts";

console.log(
  "shroud-pricing",
  JSON.stringify({
    revision: PRICING_REVISION,
    stage: "script-start",
    sdk: "0.12.0",
    nativeBunny: "Bunny" in globalThis,
  }),
);

// Only used for local development; production uses the Pull Zone's origin.
BunnySDK.net.http
  .servePullZone({ url: "https://shroud.email/" })
  .onOriginRequest(disableHtmlRanges)
  .onOriginResponse(rewritePricing);

console.log(
  "shroud-pricing",
  JSON.stringify({
    revision: PRICING_REVISION,
    stage: "middleware-registered",
  }),
);

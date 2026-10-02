import * as BunnySDK from "https://esm.sh/@bunny.net/edgescript-sdk@0.13.0";
import {
  disableHtmlRanges,
  repairDirectoryNotFound,
  rewritePricing,
} from "./pricing.ts";

// Only used for local development; production uses the Pull Zone's origin.
BunnySDK.net.http
  .servePullZone({ url: "https://shroud.email/" })
  .onOriginRequest(disableHtmlRanges)
  .onOriginResponse(rewritePricing)
  .onClientResponse(repairDirectoryNotFound);

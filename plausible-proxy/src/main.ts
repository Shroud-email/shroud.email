import * as BunnySDK from "@bunny.net/edgescript-sdk";
import { handleRequest } from "./proxy.ts";

BunnySDK.net.http.serve(handleRequest);

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "./vendor/some-package.js"
//
// Alternatively, you can `npm install some-package` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import "../vendor/components";
import "@cap.js/widget";
import { Modal, Notification } from "./hooks";

import { initTheme, setTheme } from "./theme";
import Alpine from "alpinejs";
import Tooltip from "@ryangjchandler/alpine-tooltip";
import { initializePaddle } from "@paddle/paddle-js";

Alpine.plugin(Tooltip);
window.Alpine = Alpine;
Alpine.start();

// Initialize theme (dark mode support)
initTheme();
window.setTheme = setTheme;

// Initialize Paddle.js for checkout. Token + environment are injected via
// meta tags by the root layout (server-side config, not hardcoded).
const paddleToken = document
  .querySelector("meta[name='paddle-client-token']")
  ?.getAttribute("content");
const paddleEnv = document
  .querySelector("meta[name='paddle-environment']")
  ?.getAttribute("content");

if (paddleToken) {
  initializePaddle({
    token: paddleToken,
    environment: paddleEnv === "sandbox" ? "sandbox" : undefined,
  }).then((paddle) => {
    window.Paddle = paddle;
  });
}

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { Modal, Notification },
  params: { _csrf_token: csrfToken },
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to);
      }
    },
  },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
let topBarScheduled = undefined;
window.addEventListener("phx:page-loading-start", () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 120);
  }
});
window.addEventListener("phx:page-loading-stop", () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

// Initialize Chatwoot live chat widget. Only runs when the widget is
// enabled (CHATWOOT_BASE_URL configured); self-hosted deployments omit
// the SDK script and data attribute entirely.
var chatwootBaseUrl = document.body.dataset.chatwootBaseUrl;

if (chatwootBaseUrl) {
  window.addEventListener("load", () => {
    if (window.chatwootSDK) {
      window.chatwootSDK.run({
        websiteToken: "7j9ZdJCJR5ZGaYkCMN2EvAhp",
        baseUrl: chatwootBaseUrl,
      });
    }
  });

  // Identify the authenticated user to Chatwoot once the widget is ready.
  // On logout the page reloads with no current_user, but Chatwoot keeps
  // the previous user's session in its own storage — so we reset it.
  // To avoid resetting on every anonymous page load (and hammering the
  // Chatwoot server), we only reset when we identified a user earlier in
  // this browser session, tracked via localStorage (aligned with
  // Chatwoot's own session persistence, which survives tab close).
  var chatwootSynced = false;
  function syncChatwootUser() {
    if (chatwootSynced || !window.$chatwoot) return;
    chatwootSynced = true;
    var email = document.body.dataset.currentUserEmail;
    var identifierHash = document.body.dataset.chatwootIdentifierHash;
    if (email) {
      localStorage.setItem("chatwoot_identified", "1");
      var attrs = { email: email, name: email };
      if (identifierHash) attrs.identifier_hash = identifierHash;
      window.$chatwoot.setUser(email, attrs);
    } else if (localStorage.getItem("chatwoot_identified") === "1") {
      localStorage.removeItem("chatwoot_identified");
      window.$chatwoot.reset();
    }
  }

  window.addEventListener("chatwoot:ready", syncChatwootUser);
  // If the SDK finished loading before this script ran, sync immediately.
  if (window.$chatwoot) syncChatwootUser();
}

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

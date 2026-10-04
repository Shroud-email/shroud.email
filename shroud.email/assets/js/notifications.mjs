import { createLiveToastHook } from "../vendor/live_toast.ts";

function prepareNotification(element) {
  if (!element.dataset.kind) return;
  element.setAttribute(
    "role",
    element.dataset.kind === "error" ? "alert" : "status",
  );
  element.setAttribute("aria-atomic", "true");
  element.dataset.corner = window.matchMedia("(min-width: 640px)").matches
    ? "top_right"
    : "bottom_center";
  element
    .querySelector("button")
    ?.setAttribute("aria-label", "Dismiss notification");
}

const hook = createLiveToastHook(8000, 3);
let notificationSink;
const pendingNotifications = [];

export const NotificationSource = {
  mounted() {
    this.seen = new Set();
    this.deliverNotifications();
  },
  updated() {
    this.deliverNotifications();
  },
  deliverNotifications() {
    const current = new Set();
    for (const element of this.el.querySelectorAll("[data-kind]")) {
      current.add(element.dataset.id);
      if (this.seen.has(element.dataset.id)) continue;
      const request = {
        kind: element.dataset.kind,
        message: element.textContent.trim(),
        options: { duration: Number(element.dataset.duration) },
      };
      if (notificationSink) notificationSink(request);
      else pendingNotifications.push(request);
      this.pushEvent("lv:clear-flash", { key: element.dataset.kind });
    }
    this.seen = current;
  },
};

export const LiveToast = {
  ...hook,
  mounted() {
    prepareNotification(this.el);
    hook.mounted.call(this);
    if (this.el.dataset.liveToastGroup === "true") {
      notificationSink = (request) =>
        this.el.dispatchEvent(
          new CustomEvent("live-toast:add", { detail: request }),
        );
      for (const request of pendingNotifications.splice(0))
        notificationSink(request);
    }
  },
  destroyed() {
    if (this.el.dataset.liveToastGroup === "true") notificationSink = undefined;
    hook.destroyed.call(this);
  },
  updated() {
    prepareNotification(this.el);
    hook.updated.call(this);
  },
};

// Controller pages have no enclosing LiveView to mount the toast hook or handle
// lv:clear-flash. Their redirect flashes stay visible until explicitly dismissed.
export function initializeFlashNotifications() {
  document
    .querySelectorAll("#toast-group [data-component=flash]")
    .forEach((element) => {
      prepareNotification(element);
      if (element.closest("[data-phx-main]")) return;
      element.style.opacity = "1";
      element.style.gridRow = "auto";
      element.style.marginBottom = "12px";
    });
  document.addEventListener("click", (event) => {
    const button = event.target.closest(
      "#toast-group [data-component=flash] button",
    );
    if (!button || button.closest("[data-phx-main]")) return;
    button.closest("[data-component=flash]").remove();
  });
}

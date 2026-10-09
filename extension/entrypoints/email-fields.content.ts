import { defineContentScript } from "wxt/utils/define-content-script";
import { browser } from "wxt/browser";
import { startFields } from "../content/controller";
import css from "../assets/theme.css?inline";

export default defineContentScript({
  registration: "runtime",
  main(ctx) {
    const globals = globalThis as typeof globalThis & {
      __shroudFields?: ReturnType<typeof startFields>;
    };
    if (globals.__shroudFields) {
      globals.__shroudFields.refresh();
      return;
    }
    globals.__shroudFields = startFields(
      document,
      css.replaceAll(
        "/fonts/Inter.var.woff2",
        browser.runtime.getURL("/fonts/Inter.var.woff2"),
      ),
      browser.runtime.getURL("/fonts/Inter.var.woff2"),
    );
    const stop = () => {
      globals.__shroudFields?.stop();
      delete globals.__shroudFields;
      browser.runtime.onMessage.removeListener(message);
    };
    const message = (value: unknown) => {
      if (
        value &&
        typeof value === "object" &&
        "type" in value &&
        value.type === "injection-state"
      )
        stop();
    };
    browser.runtime.onMessage.addListener(message);
    ctx.onInvalidated(stop);
  },
});

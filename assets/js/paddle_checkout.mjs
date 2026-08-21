function metaContent(document, name) {
  return document.querySelector(`meta[name='${name}']`)?.content;
}

function markUnavailable(button, message) {
  if (!button) return;

  button.disabled = true;
  button.textContent = "Payments unavailable";
  button.title = message;
}

export function setupPaddleCheckout({
  document,
  window,
  initializePaddle,
  logger = console,
}) {
  const button = document.querySelector("#upgrade-button");
  const token = metaContent(document, "paddle-client-token");

  if (!button || button.dataset.paddleCheckout !== "true" || !token) {
    return Promise.resolve(null);
  }

  let checkoutPending = false;

  const paddlePromise = initializePaddle({
    token,
    environment:
      metaContent(document, "paddle-environment") === "sandbox"
        ? "sandbox"
        : undefined,
    eventCallback: (data) => {
      if (data.name === "checkout.completed") {
        window.setTimeout(() => {
          window.location.href = "/settings/billing";
        }, 5000);
      }
    },
  })
    .then((paddle) => {
      if (!paddle) throw new Error("Paddle.js returned no client");

      window.Paddle = paddle;
      if (!checkoutPending) button.disabled = false;
      return paddle;
    })
    .catch((error) => {
      logger.error("Paddle.js initialization failed", error);
      markUnavailable(button, "Checkout couldn't load. Please try again later.");
      return null;
    });

  document.addEventListener("click", async (event) => {
    const clickedButton = event.target.closest?.(
      "#upgrade-button[data-paddle-checkout='true']",
    );

    if (!clickedButton || checkoutPending) return;

    checkoutPending = true;
    clickedButton.disabled = true;

    let paddle;

    try {
      paddle = await paddlePromise;
      if (!paddle) return;

      const csrfToken = metaContent(document, "csrf-token");
      const response = await window.fetch(
        clickedButton.dataset.paddleCheckoutUrl,
        {
          method: "POST",
          headers: { "x-csrf-token": csrfToken },
        },
      );

      if (!response.ok) throw new Error(`checkout request failed: ${response.status}`);

      const { transaction_id: transactionId } = await response.json();
      if (!transactionId) throw new Error("checkout response omitted transaction_id");

      paddle.Checkout.open({
        transactionId,
        settings: { displayMode: "overlay", theme: "light", locale: "en" },
      });

      clickedButton.textContent = "Upgrade";
      clickedButton.title = "";
    } catch (error) {
      logger.error("Paddle checkout failed", error);
      clickedButton.textContent = "Try again";
      clickedButton.title = "Checkout couldn't be opened. Please try again.";
    } finally {
      checkoutPending = false;
      if (paddle) clickedButton.disabled = false;
    }
  });

  return paddlePromise;
}

function decodeBase64(value) {
  const binary = atob(value.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

function encodeBase64(value) {
  const bytes = new Uint8Array(value);
  return btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function setupPasskeys({ document, window, fetch }) {
  const login = document.getElementById("login-form");
  const addForm = document.getElementById("add-passkey-form");
  if (!login && !addForm) return;

  const csrf = document.querySelector('meta[name="csrf-token"]').getAttribute("content");
  const supported = !!(window.PublicKeyCredential && window.navigator.credentials);

  async function post(url, body, redirect = "follow", signal) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      redirect,
      signal,
      headers: { "content-type": "application/json", "x-csrf-token": csrf },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error("Passkey request failed");
    return response;
  }

  if (login) {
    const button = document.getElementById("passkey-login-button");
    const status = document.getElementById("passkey-login-status");
    if (!supported) return;
    button.hidden = false;
    document.getElementById("passkey-login").hidden = false;
    let pending;
    let generation = 0;

    async function start(conditional, currentGeneration) {
      try {
        const response = await post("/users/passkeys/options", {});
        const { publicKey, token } = await response.json();
        if (currentGeneration !== generation) return;
        const controller = new AbortController();
        pending = controller;

        const request = {
          publicKey: { ...publicKey, challenge: decodeBase64(publicKey.challenge) },
          signal: controller.signal,
        };
        if (conditional) request.mediation = "conditional";

        const credentialPromise = window.navigator.credentials.get(request);
        if (conditional) {
          credentialPromise.then(credential => complete(credential, token, currentGeneration)).catch(error => {
            if (currentGeneration === generation && error.name !== "NotAllowedError" && error.name !== "AbortError") {
              status.textContent = "Could not sign in with passkey. You can still use your password.";
            }
          });
        } else {
          await complete(await credentialPromise, token, currentGeneration);
        }
      } catch (error) {
        if (currentGeneration === generation && error.name !== "NotAllowedError" && error.name !== "AbortError") {
          status.textContent = "Could not sign in with passkey. You can still use your password.";
        }
      }
    }

    async function complete(credential, token, currentGeneration) {
      if (currentGeneration !== generation) return;
      const result = await post("/users/passkeys", {
        token,
        rawId: encodeBase64(credential.rawId),
        userHandle: encodeBase64(credential.response.userHandle),
        authenticatorData: encodeBase64(credential.response.authenticatorData),
        clientDataJSON: encodeBase64(credential.response.clientDataJSON),
        signature: encodeBase64(credential.response.signature),
      });
      if (currentGeneration === generation) window.location.assign(result.url);
    }

    button.addEventListener("click", async () => {
      const currentGeneration = ++generation;
      pending?.abort();
      await start(false, currentGeneration);
    });

    const conditionalGeneration = generation;
    if (typeof window.PublicKeyCredential.isConditionalMediationAvailable === "function" &&
        await window.PublicKeyCredential.isConditionalMediationAvailable() &&
        generation === conditionalGeneration) {
      await start(true, conditionalGeneration);
    }
  }

  if (addForm) {
    const status = document.getElementById("passkey-status");
    const submit = document.getElementById("add-passkey-submit");

    addForm.addEventListener("submit", async event => {
      event.preventDefault();
      if (submit.disabled) return;
      if (!supported || !window.navigator.credentials.create) {
        status.dataset.state = "error";
        status.textContent = "This browser does not support passkeys. You can still use your password.";
        return;
      }
      submit.disabled = true;
      status.dataset.state = "pending";
      status.textContent = "Preparing your passkey…";
      let timer;
      let timedOut = false;

      try {
        const password = document.getElementById("add-passkey-password").value;
        const response = await post(addForm.action, { current_password: password });
        const { publicKey, token } = await response.json();
        const options = {
          ...publicKey,
          challenge: decodeBase64(publicKey.challenge),
          user: { ...publicKey.user, id: decodeBase64(publicKey.user.id) },
          excludeCredentials: publicKey.excludeCredentials.map(credential => ({
            ...credential, id: decodeBase64(credential.id),
          })),
        };

        const controller = new AbortController();
        const onTimeout = () => {
          timedOut = true;
          status.dataset.state = "error";
          status.textContent = "Passkey request timed out. Please try again.";
          controller.abort();
        };
        status.textContent = "Waiting for your passkey…";
        timer = window.setTimeout(onTimeout, 60_000);
        const credential = await window.navigator.credentials.create({ publicKey: options, signal: controller.signal });
        if (timedOut) return;
        window.clearTimeout(timer);
        status.textContent = "Saving your passkey…";
        timer = window.setTimeout(onTimeout, 60_000);
        await post("/settings/passkeys", {
          token,
          rawId: encodeBase64(credential.rawId),
          attestationObject: encodeBase64(credential.response.attestationObject),
          clientDataJSON: encodeBase64(credential.response.clientDataJSON),
        }, "follow", controller.signal);
        if (timedOut) return;
        window.location.assign("/settings/security");
      } catch (error) {
        if (!timedOut) {
          status.dataset.state = "error";
          status.textContent = error.name === "NotAllowedError"
            ? "Passkey creation was canceled. Please try again."
            : "Could not add passkey. Please check your password and try again.";
        }
      } finally {
        if (timer !== undefined) window.clearTimeout(timer);
        submit.disabled = false;
      }
    });
  }
}

function decodeBase64(value) {
  const binary = atob(value.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

function encodeBase64(value) {
  const bytes = new Uint8Array(value || 0);
  return btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function registrationOptions(publicKey) {
  return {
    ...publicKey,
    challenge: decodeBase64(publicKey.challenge),
    user: { ...publicKey.user, id: decodeBase64(publicKey.user.id) },
    excludeCredentials: (publicKey.excludeCredentials || []).map(credential => ({
      ...credential,
      id: decodeBase64(credential.id),
    })),
  };
}

function assertionOptions(publicKey) {
  return {
    ...publicKey,
    challenge: decodeBase64(publicKey.challenge),
    allowCredentials: (publicKey.allowCredentials || []).map(credential => ({
      ...credential,
      id: decodeBase64(credential.id),
    })),
  };
}

function supported(window, operation) {
  return !!(window.PublicKeyCredential &&
    typeof window.navigator.credentials?.[operation] === "function");
}

function reason(error, timedOut = false) {
  if (timedOut) return "timeout";
  if (error?.name === "NotAllowedError" || error?.name === "AbortError") return "canceled";
  if (error?.name === "NotSupportedError" || error?.name === "SecurityError") return "unsupported";
  return "failed";
}

export function createPasskeyHooks(window) {
  const PasskeyRegistration = {
    mounted() {
      this.passkeyGeneration = 0;
      this.passkeyController = null;
      this.passkeyTimer = null;
      this.pushEvent("passkey_supported", { supported: supported(window, "create") });
      this.handleEvent("passkey-register", payload => this.registerPasskey(payload));
      this.handleEvent("passkey-cancel", () => this.cancelPasskeyRegistration());
    },

    async registerPasskey({ token, publicKey }) {
      const generation = ++this.passkeyGeneration;
      this.passkeyController?.abort();
      if (this.passkeyTimer !== null) window.clearTimeout(this.passkeyTimer);
      const controller = new AbortController();
      this.passkeyController = controller;
      this.passkeyTimer = window.setTimeout(() => {
        if (generation !== this.passkeyGeneration) return;
        ++this.passkeyGeneration;
        this.passkeyController = null;
        this.passkeyTimer = null;
        this.pushEvent("passkey_error", { token, reason: "timeout" });
        controller.abort();
      }, 60_000);

      try {
        if (!supported(window, "create")) {
          throw new DOMException("Passkeys unsupported", "NotSupportedError");
        }
        this.pushEvent("passkey_status", { token, phase: "waiting" });
        const credential = await window.navigator.credentials.create({
          publicKey: registrationOptions(publicKey),
          signal: controller.signal,
        });
        if (generation !== this.passkeyGeneration) return;
        this.pushEvent("passkey_status", { token, phase: "saving" });
        await new Promise((resolve, reject) => {
          controller.signal.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError")), { once: true });
          this.pushEvent("passkey_registered", {
            token,
            rawId: encodeBase64(credential.rawId),
            attestationObject: encodeBase64(credential.response.attestationObject),
            clientDataJSON: encodeBase64(credential.response.clientDataJSON),
          }, reply => reply?.error ? reject(new Error(reply.error)) : resolve(reply));
        });
      } catch (error) {
        if (generation === this.passkeyGeneration) {
          this.pushEvent("passkey_error", { token, reason: reason(error) });
        }
      } finally {
        if (generation === this.passkeyGeneration) {
          window.clearTimeout(this.passkeyTimer);
          this.passkeyTimer = null;
          this.passkeyController = null;
        }
      }
    },

    disconnected() { this.cancelPasskeyRegistration(); },
    reconnected() {
      this.pushEvent("passkey_supported", { supported: supported(window, "create") });
    },
    destroyed() { this.cancelPasskeyRegistration(); },
    cancelPasskeyRegistration() {
      ++this.passkeyGeneration;
      this.passkeyController?.abort();
      if (this.passkeyTimer !== null) window.clearTimeout(this.passkeyTimer);
      this.passkeyController = null;
      this.passkeyTimer = null;
    },
  };

  const PasskeyLogin = {
    mounted() {
      this.passkeyGeneration = 0;
      this.passkeyController = null;
      this.passkeyTimer = null;
      this.passkeyClick = event => {
        if (event.target.closest("#passkey-login-button")) this.startPasskeyLogin(false);
      };
      this.el.addEventListener("click", this.passkeyClick);
      const available = supported(window, "get");
      this.pushEvent("passkey_supported", { supported: available });
      if (available) this.startConditionalPasskeyLogin();
    },

    async startConditionalPasskeyLogin() {
      const generation = this.passkeyGeneration;
      try {
        const check = window.PublicKeyCredential.isConditionalMediationAvailable;
        if (typeof check === "function" && await check.call(window.PublicKeyCredential) &&
            generation === this.passkeyGeneration) {
          this.requestPasskeyOptions(true, generation);
        }
      } catch {
        // Capability detection must never interfere with password login.
      }
    },

    startPasskeyLogin(conditional) {
      const generation = ++this.passkeyGeneration;
      this.passkeyController?.abort();
      if (this.passkeyTimer !== null) window.clearTimeout(this.passkeyTimer);
      this.passkeyController = null;
      this.passkeyTimer = null;
      this.requestPasskeyOptions(conditional, generation);
    },

    requestPasskeyOptions(conditional, generation) {
      if (!supported(window, "get")) {
        if (!conditional) this.pushEvent("passkey_login_error", { reason: "unsupported" });
        return;
      }
      let timedOut = false;
      if (!conditional) {
        this.passkeyTimer = window.setTimeout(() => {
          timedOut = true;
          this.passkeyController?.abort();
          this.passkeyController = null;
          this.passkeyTimer = null;
          if (generation === this.passkeyGeneration) {
            ++this.passkeyGeneration;
            this.pushEvent("passkey_login_error", { reason: "timeout" });
          }
        }, 60_000);
      }
      this.pushEvent("passkey_options", {}, reply => {
        if (generation !== this.passkeyGeneration) return;
        if (reply?.error || !reply?.publicKey) {
          this.finishPasskeyLogin(generation);
          // Rate-limit replies already render specific retry guidance on the server.
          if (!conditional && !reply?.retry_after) {
            this.pushEvent("passkey_login_error", { reason: "failed" });
          }
          return;
        }
        this.getPasskey(reply, conditional, generation, () => timedOut);
      });
    },

    async getPasskey({ token, publicKey }, conditional, generation, didTimeOut) {
      const controller = new AbortController();
      this.passkeyController = controller;
      try {
        const options = { publicKey: assertionOptions(publicKey), signal: controller.signal };
        if (conditional) options.mediation = "conditional";
        const credential = await window.navigator.credentials.get(options);
        if (generation !== this.passkeyGeneration) return;
        await new Promise((resolve, reject) => {
          controller.signal.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError")), { once: true });
          this.pushEvent("passkey_assertion", {
            token,
            rawId: encodeBase64(credential.rawId),
            userHandle: encodeBase64(credential.response.userHandle),
            authenticatorData: encodeBase64(credential.response.authenticatorData),
            clientDataJSON: encodeBase64(credential.response.clientDataJSON),
            signature: encodeBase64(credential.response.signature),
          }, reply => reply?.error ? reject(new Error(reply.error)) : resolve(reply));
        });
      } catch (error) {
        if (generation === this.passkeyGeneration && !(conditional &&
            (error?.name === "NotAllowedError" || error?.name === "AbortError"))) {
          this.pushEvent("passkey_login_error", { reason: reason(error, didTimeOut()) });
        }
      } finally {
        this.finishPasskeyLogin(generation);
      }
    },

    finishPasskeyLogin(generation) {
      if (generation !== this.passkeyGeneration) return;
      if (this.passkeyTimer !== null) window.clearTimeout(this.passkeyTimer);
      this.passkeyTimer = null;
      this.passkeyController = null;
    },

    disconnected() { this.cancelPasskeyLogin(); },
    reconnected() {
      const available = supported(window, "get");
      this.pushEvent("passkey_supported", { supported: available });
      if (available) this.startConditionalPasskeyLogin();
    },
    destroyed() {
      this.el.removeEventListener("click", this.passkeyClick);
      this.cancelPasskeyLogin();
    },
    cancelPasskeyLogin() {
      ++this.passkeyGeneration;
      this.passkeyController?.abort();
      if (this.passkeyTimer !== null) window.clearTimeout(this.passkeyTimer);
      this.passkeyController = null;
      this.passkeyTimer = null;
    },
  };

  return { PasskeyRegistration, PasskeyLogin };
}

export const { PasskeyRegistration, PasskeyLogin } =
  createPasskeyHooks(globalThis.window);

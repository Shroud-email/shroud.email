import { onMounted, onUnmounted, ref, watch } from "vue";
import { browser } from "wxt/browser";
import {
  request,
  type AccountView,
  type Alias,
  type AliasPage,
  type CreateAlias,
  type Failure,
  type Message,
  type Reply,
  type Result,
} from "../shared/contracts";

export function useAccount() {
  const account = ref<AccountView | null>(null);
  const screen = ref<"aliases" | "create" | "settings">("aliases");
  const loaded = ref(false);
  const page = ref<AliasPage | null>(null);
  const query = ref("");
  const searching = ref(false);
  const error = ref<Failure | null>(null);
  const creationError = ref<Failure | null>(null);
  const creating = ref(false);
  const created = ref<Alias | null>(null);
  const notice = ref("");
  let epoch = 0;
  let accountRead = 0;
  let searchRead = 0;
  let noticeTimer: ReturnType<typeof setTimeout> | undefined;
  async function send<M extends Message>(
    message: M,
  ): Promise<Reply<Result<M>>> {
    try {
      return await request(message);
    } catch {
      return {
        ok: false,
        error: {
          kind: "network",
          message:
            message.type === "create"
              ? "The result is uncertain. Check your aliases before creating another."
              : "Could not reach the extension. Try again.",
          ...(message.type === "create" ? { creationUncertain: true } : {}),
        },
      };
    }
  }
  function reset() {
    epoch++;
    accountRead++;
    searchRead++;
    account.value = null;
    page.value = null;
    query.value = "";
    screen.value = "aliases";
    error.value = null;
    creationError.value = null;
    created.value = null;
    creating.value = false;
  }
  async function refreshAccount(): Promise<boolean> {
    const read = ++accountRead;
    const result = await send({ type: "account" });
    if (read !== accountRead) return false;
    loaded.value = true;
    if (!result.ok) {
      error.value = result.error;
      if (result.error.kind === "auth") {
        reset();
        error.value = result.error;
      }
      return false;
    }
    if (
      account.value &&
      (!result.value ||
        account.value.email !== result.value.email ||
        account.value.instance !== result.value.instance)
    )
      reset();
    account.value = result.value;
    error.value = null;
    return true;
  }
  async function loadAliases(number = 1): Promise<boolean> {
    const read = ++searchRead;
    const generation = epoch;
    searching.value = true;
    const result = await send({
      type: "aliases",
      search: query.value,
      page: number,
    });
    if (read !== searchRead || generation !== epoch) return false;
    searching.value = false;
    if (!result.ok) {
      error.value = result.error;
      return false;
    }
    page.value = result.value;
    error.value = null;
    return true;
  }
  function confirm(message: string) {
    clearTimeout(noticeTimer);
    notice.value = message;
    noticeTimer = setTimeout(() => {
      notice.value = "";
    }, 4000);
  }
  async function copy(address: string, afterCreation = false): Promise<void> {
    const generation = epoch;
    try {
      await navigator.clipboard.writeText(address);
      if (generation !== epoch) return;
      confirm(afterCreation ? "Alias created and copied" : "Alias copied");
      if (afterCreation) {
        created.value = null;
        screen.value = "aliases";
      }
    } catch {
      if (generation === epoch)
        error.value = {
          kind: "permission",
          message: afterCreation
            ? "Alias created. Copy it below."
            : "Could not copy. Try the copy button again.",
        };
    }
  }
  async function create(input: CreateAlias): Promise<void> {
    if (
      creating.value ||
      created.value ||
      creationError.value?.creationUncertain ||
      !account.value?.capabilities.can_create
    )
      return;
    const generation = epoch;
    creating.value = true;
    creationError.value = null;
    error.value = null;
    const result = await send({ type: "create", input });
    if (generation !== epoch) return;
    if (!result.ok) {
      creating.value = false;
      creationError.value = result.error;
      if (result.error.kind === "limit") {
        account.value!.capabilities.can_create = false;
        await refreshAccount();
      }
      if (result.error.kind === "auth") {
        reset();
        error.value = result.error;
      }
      return;
    }
    created.value = result.value;
    await copy(result.value.address, true);
    if (generation !== epoch) return;
    creating.value = false;
    await Promise.all([refreshAccount(), loadAliases()]);
  }
  async function checkUncertain(): Promise<void> {
    if (await loadAliases()) {
      creationError.value = null;
      screen.value = "aliases";
      notice.value = "Check this list before creating another alias.";
      await refreshAccount();
    }
  }
  async function logout(): Promise<void> {
    reset();
    notice.value = "";
    const result = await send({ type: "logout" });
    if (!result.ok) error.value = result.error;
  }
  watch(query, () => {
    if (account.value) {
      page.value = null;
      void loadAliases();
    }
  });
  function changed(message: unknown) {
    if (
      !message ||
      typeof message !== "object" ||
      !("type" in message) ||
      message.type !== "account-changed"
    )
      return;
    reset();
    void refreshAccount().then((loaded) => {
      if (loaded && account.value) return loadAliases();
    });
  }
  onMounted(async () => {
    browser.runtime.onMessage.addListener(changed);
    if ((await refreshAccount()) && account.value) await loadAliases();
  });
  onUnmounted(() => {
    epoch++;
    clearTimeout(noticeTimer);
    browser.runtime.onMessage.removeListener(changed);
  });
  return {
    account,
    screen,
    loaded,
    page,
    query,
    searching,
    error,
    creationError,
    creating,
    created,
    notice,
    send,
    refreshAccount,
    loadAliases,
    create,
    copy,
    checkUncertain,
    logout,
  };
}

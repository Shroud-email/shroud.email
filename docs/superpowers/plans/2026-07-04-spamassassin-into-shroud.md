# SpamAssassin-into-shroud Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move SpamAssassin scanning from the Haraka MTA into the shroud.email Elixir app, so shroud calls spamd itself and injects the `X-Spam-Status` header into the parsed email before the existing spam-detection logic runs. This is step 1 of the larger Haraka-removal sequence (see `.worktrees/explore-haraka-removal/FEASIBILITY.md`); it touches only the SpamAssassin slice and leaves Haraka running everything else.

**Architecture:** Add a `Shroud.Email.SpamAssassin` module that calls the `spamc` CLI (shipped by the `dinkel/spamassassin` container) over a behaviour, so it is mockable in tests via Mox (matching the existing `Shroud.MockDateTime` / `Shroud.MockDnsClient` pattern). A new step in `IncomingEmailHandler.handle_incoming_email/3` runs the scan *before* `SpamHandler.spam?/1` is called, and rewrites the parsed email's headers to include the returned `X-Spam-Status` line so the existing header-reading code keeps working unchanged. Scanning is opt-in via an env var (`SPAMASSASSIN_ENABLED`) and fails safe: any error → log a warning and proceed as "not spam" (matching today's missing-header behaviour exactly).

**Tech Stack:** Elixir, Phoenix, gen_smtp, Oban, Mox, ExUnit. The `spamc` binary (SpamAssassin client) shells out via `System.cmd/3`. No new Hex dependencies.

## Global Constraints

- **All work happens in the worktree** `/Users/tao/dev/shroud/shroud.email/.worktrees/explore-haraka-removal` on branch `explore/haraka-removal`. All file paths in this plan are relative to the repo root (i.e. inside that worktree).
- **TDD strictly:** every production-code change is preceded by a failing test that the implementer watches fail. No exceptions.
- **No new Hex dependencies.** `System.cmd/3` + a behaviour + Mox is the whole pattern, matching `Shroud.MockDateTime` and `Shroud.MockDnsClient` already in `test/test_helper.exs`.
- **Fail-safe, fail-safe, fail-safe.** The spam scan must never cause an inbound email to be dropped or to crash the Oban worker. On any error (spamc missing, SA unreachable, timeout, malformed response), the handler logs a warning and proceeds as if the email is **not spam** — identical to today's "missing X-Spam-Status header" path (`spam_handler.ex:103-110`).
- **Backwards compatible with Haraka still in place.** During rollout Haraka may still be injecting `X-Spam-Status`. If the header is already present on an inbound message, shroud must **not** scan again — use the existing header (avoids double work and double-counting). This makes the change safe to ship behind a flag with Haraka still running.
- **Do not modify `SpamHandler.spam?/1` or `SpamHandler.get_spamassassin_header/1` behaviour.** They already correctly read `X-Spam-Status`. The new code's job is to *ensure that header is present* before they run.
- `mix format` runs before every commit. `mix credo --strict` and `mix test` must pass before the final commit.
- Predicate functions end in `?`, no `is_` prefix (Elixir convention). Use `with` for error chaining, `{:ok, _} / {:error, _}` tuples.
- The `:outgoing_email` Oban queue name is a pre-existing misnomer (handles both directions) — do not rename it in this PR.

---

## File Structure

**Create:**
- `lib/shroud/email/spam_assassin.ex` — the new module. Defines a behaviour, a default `System.cmd("spamc", ...)` implementation, and a public `scan/1` entry point. One responsibility: turn a raw RFC822 string into `{:ok, x_spam_status_header_value :: String.t()} | {:error, term()}` (or `:disabled`).
- `test/shroud/email/spam_assassin_test.exs` — unit tests for the new module, using Mox for the behaviour.

**Modify:**
- `test/test_helper.exs` — register the `Shroud.MockSpamAssassin` Mox mock and point the app env at it (same pattern as the existing mocks).
- `lib/shroud/email/incoming_email_handler.ex` — insert the scan step before the `SpamHandler.spam?(data)` call in `handle_incoming_email/3`. No other behaviour change.
- `test/shroud/email/incoming_email_handler_test.exs` (if it exists; otherwise `email_handler_test.exs` covers it — see Task 4) — tests that the new scan runs and that the fail-safe path works.
- `config/config.exs`, `config/test.exs`, `config/runtime.exs` — add `SPAMASSASSIN_ENABLED` and `SPAMC_PATH` env config (default off in test, on in prod via runtime).
- `config/runtime.exs` — read `SPAMASSASSIN_ENABLED` and `SPAMC_PATH` env vars.
- `.env.example` / `example.env` (shroud.email repo) — document the new env vars (if the repo has one; check first).
- `AGENTS.md` — one-line note in the Email Processing Pipeline section that SpamAssassin now runs in-process.

**No changes to:**
- `lib/shroud/email/spam_handler.ex` (reads the header; the new module produces it).
- `lib/shroud/email/smtp_server.ex` (still receives from Haraka on :1587; unchanged).
- The hosting repo / Haraka config — that's a later step. This PR ships *behind a flag* and Haraka keeps running its own SA in parallel; the flag is off by default.

---

## Task 1: Behaviour + Mox wiring (no production logic yet)

**Goal of this task:** establish the seam. Define the behaviour, register the mock, and prove the wiring works with a trivial stub. No `spamc` calls yet, no handler changes — just the contract and the test harness.

**Files:**
- Create: `lib/shroud/email/spam_assassin.ex`
- Create: `test/shroud/email/spam_assassin_test.exs`
- Modify: `test/test_helper.exs`

**Interfaces:**
- Produces: `Shroud.Email.SpamAssassin.scan/1` with signature `(raw_email :: String.t()) :: {:ok, String.t()} | {:error, term()} | :disabled`. The `String.t()` on `:ok` is the `X-Spam-Status` header **value** (e.g. `"No, score=-1.0 ..."`), NOT the full header line.
- Produces: a behaviour `Shroud.Email.SpamAssassin.Behaviour` (or implicit via `@callback` in the module) that Mox can mock.

- [ ] **Step 1: Write the failing test**

Create `test/shroud/email/spam_assassin_test.exs`:

```elixir
defmodule Shroud.Email.SpamAssassinTest do
  use ExUnit.Case, async: true
  import Mox

  alias Shroud.Email.SpamAssassin

  # The mock is registered in test_helper.exs as Shroud.MockSpamAssassin
  # and bound to the app env :spamassassin_module.

  setup do
    # Always verify expectations and stub the module by default so tests
    # that don't care about scanning don't have to set it up.
    stub_with(Shroud.MockSpamAssassin, Shroud.Email.SpamAssassin.Stub)
    :ok
  end

  describe "scan/1" do
    test "returns :disabled when SpamAssassin is not enabled" do
      # Disable via app env for this test
      original = Application.get_env(:shroud, :spamassassin, [])
      Application.put_env(:shroud, :spamassassin, Keyword.put(original, :enabled, false))

      try do
        assert SpamAssassin.scan("Subject: hi\r\n\r\nbody") == :disabled
      after
        Application.put_env(:shroud, :spamassassin, original)
      end
    end

    test "returns the X-Spam-Status value via the configured module" do
      # Use a stub implementation that returns a canned value
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw -> {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"} end)

      Application.put_env(:shroud, :spamassassin, enabled: true, module: Shroud.MockSpamAssassin)

      assert SpamAssassin.scan("Subject: hi\r\n\r\nbody") ==
               {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
    after
      Application.put_env(:shroud, :spamassassin, Application.get_env(:shroud, :spamassassin, []))
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/shroud/email/spam_assassin_test.exs`
Expected: compile error — `Shroud.Email.SpamAssassin` does not exist, and `Shroud.MockSpamAssassin` is not defined. Confirm the failure is the *module-missing* failure, not a typo.

- [ ] **Step 3: Register the mock in test_helper.exs**

Modify `test/test_helper.exs` — add alongside the existing `Mox.defmock` lines (after `Shroud.MockDnsClient`):

```elixir
Mox.defmock(Shroud.MockSpamAssassin, for: Shroud.Email.SpamAssassin.Behaviour)
Application.put_env(:shroud, :spamassassin, enabled: false, module: Shroud.MockSpamAssassin)
```

- [ ] **Step 4: Write the minimal module to make the test pass**

Create `lib/shroud/email/spam_assassin.ex`:

```elixir
defmodule Shroud.Email.SpamAssassin do
  @moduledoc """
  Scans raw RFC822 email data with SpamAssassin and returns the
  `X-Spam-Status` header value that SpamAssassin produces.

  This module is the in-process replacement for the SpamAssassin scanning
  Haraka used to do via its `spamassassin` plugin. The actual spamd call
  happens in `Shroud.Email.SpamAssassin.Client` (added in Task 2); this
  module is the public entry point and the behaviour + config seam.

  ## Fail-safe contract

  `scan/1` never raises. On any error (spamc missing, spamd unreachable,
  timeout, malformed response) it returns `{:error, reason}`. Callers
  must treat `:disabled` and `{:error, _}` as "not spam" and continue.
  """

  @type raw_email :: String.t()
  @type x_spam_status :: String.t()

  @callback scan(raw_email()) :: {:ok, x_spam_status()} | {:error, term()} | :disabled

  defmodule Behaviour do
    @callback scan(Shroud.Email.SpamAssassin.raw_email()) ::
                    {:ok, Shroud.Email.SpamAssassin.x_spam_status()}
                    | {:error, term()}
                    | :disabled
  end

  @doc """
  A no-op stub used as the default in tests. Returns `:disabled`.
  """
  defmodule Stub do
    @behaviour Shroud.Email.SpamAssassin.Behaviour
    def scan(_raw), do: :disabled
  end

  @spec scan(raw_email()) :: {:ok, x_spam_status()} | {:error, term()} | :disabled
  def scan(raw) do
    config = Application.get_env(:shroud, :spamassassin, [])
    enabled = Keyword.get(config, :enabled, false)
    module = Keyword.get(config, :module, Shroud.Email.SpamAssassin.Stub)

    if enabled do
      module.scan(raw)
    else
      :disabled
    end
  end
end
```

Note: `Shroud.MockSpamAssassin` is `for: Shroud.Email.SpamAssassin.Behaviour`, and `Stub` also implements `Behaviour`. The `@callback` on the outer module is documentation-only and may be removed if credo complains; keep `Behaviour` as the source of truth.

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/shroud/email/spam_assassin_test.exs`
Expected: PASS. (`Mox.stub_with/2` is available — Mox 1.2.0 is pinned in `mix.lock`.)

- [ ] **Step 6: Run the full suite to confirm nothing else broke**

Run: `mix test`
Expected: all green. The new module is not referenced anywhere yet, so this is a smoke check.

- [ ] **Step 7: Commit**

```bash
git add lib/shroud/email/spam_assassin.ex test/shroud/email/spam_assassin_test.exs test/test_helper.exs
git commit -m "feat(email): add SpamAssassin behaviour + Mox seam

Introduces Shroud.Email.SpamAssassin with a Behaviour + Stub and a
config-driven scan/1 entry point. No spamc calls yet; this is the
seam the next task fills in. Default disabled, fail-safe by design."
```

---

## Task 2: spamc client implementation

**Goal of this task:** implement the real `Behaviour` callback that shells out to `spamc` and parses the returned `X-Spam-Status` header. This is the only task that touches the actual SpamAssassin protocol, and it's isolated behind the behaviour so it has zero callers yet.

**Files:**
- Modify: `lib/shroud/email/spam_assassin.ex` (add `Client` submodule)
- Modify: `test/shroud/email/spam_assassin_test.exs` (add `Client` tests)

**Interfaces:**
- Consumes: `Shroud.Email.SpamAssassin.Behaviour` (from Task 1)
- Produces: `Shroud.Email.SpamAssassin.Client.scan/1` implementing that behaviour, suitable to be set as `:spamassassin, module:` in prod config.

**Spamc protocol reference (what the test must assert against):**
`spamc` reads a raw RFC822 message on stdin and writes the *same message back* with extra SpamAssassin headers inserted. The relevant output line is `X-Spam-Status: No, score=-1.0 required=5.0 tests=...`. The client pipes the raw email to `spamc`, captures stdout, and extracts the `X-Spam-Status` value (case-insensitive header name). The `spamc` binary path is configurable via `:spamassassin, :spamc_path` (default `"spamc"`).

- [ ] **Step 1: Write the failing tests for `Client.scan/1`**

Append to `test/shroud/email/spam_assassin_test.exs` a new describe block. Use `System.cmd` mocking via a small wrapper — **but** `System.cmd` is not mockable directly. Two options, pick the lazy one that matches the codebase: introduce a tiny `Shroud.Email.SpamAssassin.Client.cmd/3` private function and test the parsing logic separately from the shell-out by extracting a pure `parse_x_spam_status/1`. The test plan:

```elixir
  describe "Client.parse_x_spam_status/1" do
    alias Shroud.Email.SpamAssassin.Client

    test "extracts the X-Spam-Status header value (case-insensitive)" do
      output =
        "Subject: hi\r\nX-Spam-Status: No, score=-1.0 required=5.0 tests=NONE version=3.4.1\r\n\r\nbody"

      assert Client.parse_x_spam_status(output) ==
               {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"}
    end

    test "extracts the header when spam is detected" do
      output =
        "X-Spam-Status: Yes, score=8.2 required=5.0 tests=FOO,BAR version=3.4.1\r\nSubject: hi\r\n\r\nbody"

      assert Client.parse_x_spam_status(output) ==
               {:ok, "Yes, score=8.2 required=5.0 tests=FOO,BAR version=3.4.1"}
    end

    test "handles lowercase header name" do
      output = "x-spam-status: No, score=0.0 required=5.0\r\n\r\nbody"
      assert Client.parse_x_spam_status(output) == {:ok, "No, score=0.0 required=5.0"}
    end

    test "returns :error when the header is absent" do
      assert Client.parse_x_spam_status("Subject: hi\r\n\r\nbody") == :error
    end

    test "returns :error on empty input" do
      assert Client.parse_x_spam_status("") == :error
    end
  end
```

Then a single integration-style test for the shell-out path using a real `spamc`-shim approach is **not** worth the complexity. Instead, add one test that proves `Client.scan/1` returns `{:error, _}` when `spamc` is not found, by configuring a path that does not exist:

```elixir
  describe "Client.scan/1 shell-out" do
    alias Shroud.Email.SpamAssassin.Client

    test "returns {:error, _} when spamc binary is missing" do
      # Point at a path that does not exist on the test machine.
      Application.put_env(:shroud, :spamassassin,
        enabled: true,
        module: Client,
        spamc_path: "/nonexistent/spamc-#{System.unique_integer([:positive])}"
      )

      try do
        assert {:error, _} = Client.scan("Subject: hi\r\n\r\nbody")
      after
        Application.put_env(:shroud, :spamassassin, Application.get_env(:shroud, :spamassassin, []))
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/shroud/email/spam_assassin_test.exs`
Expected: FAIL with `UndefinedFunctionError` for `Shroud.Email.SpamAssassin.Client.parse_x_spam_status/1` and `Client.scan/1`.

- [ ] **Step 3: Implement the `Client` submodule**

Add inside `lib/shroud/email/spam_assassin.ex`, below the `Stub` module:

```elixir
  defmodule Client do
    @moduledoc """
    Real spamd client that shells out to the `spamc` CLI shipped with
    SpamAssassin. Implements `Shroud.Email.SpamAssassin.Behaviour`.

    Fail-safe: every exit path other than a clean parse returns
    `{:error, reason}` so callers can fall back to "not spam".
    """
    @behaviour Shroud.Email.SpamAssassin.Behaviour

    @default_spamc_path "spamc"

    @impl true
    def scan(raw) when is_binary(raw) do
      config = Application.get_env(:shroud, :spamassassin, [])
      spamc_path = Keyword.get(config, :spamc_path, @default_spamc_path)

      case System.cmd(spamc_path, [], input: raw, stderr_to_stdout: true, env: []) do
        {output, 0} ->
          parse_x_spam_status(output)

        {_output, _exit_code} ->
          # Non-zero exit: spamd unreachable, message rejected, etc.
          {:error, :spamc_nonzero_exit}
      end
    rescue
      # `System.cmd` raises `ErlangError` / `File.Error` when the binary
      # is not found. Treat that as a recoverable error, never a crash.
      e in [ErlangError, File.Error] ->
        {:error, {:spamc_unavailable, Exception.message(e)}}
    end

    @doc """
    Pure parser: extracts the `X-Spam-Status` header value from a
    SpamAssassin-annotated message. Case-insensitive on the header name.
    Returns `{:ok, value}` or `:error`.
    """
    @spec parse_x_spam_status(String.t()) :: {:ok, String.t()} | :error
    def parse_x_spam_status(output) when is_binary(output) do
      # Only scan the headers block (everything before the first blank line).
      headers =
        case String.split(output, ~r/\r?\n\r?\n/, parts: 2) do
          [headers | _] -> headers
          [headers] -> headers
        end

      headers
      |> String.split(~r/\r?\n/)
      |> Enum.find_value(fn line ->
        case String.split(line, ":", parts: 2) do
          [name, value] ->
            if String.downcase(String.trim(name)) == "x-spam-status" do
              String.trim(value)
            end

          _ ->
            nil
        end
      end)
      |> case do
        nil -> :error
        value when is_binary(value) -> {:ok, value}
      end
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/shroud/email/spam_assassin_test.exs`
Expected: PASS, including the "spamc missing" test (returns `{:error, _}`).

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: all green. `Client` is not yet wired into any caller.

- [ ] **Step 6: Commit**

```bash
git add lib/shroud/email/spam_assassin.ex test/shroud/email/spam_assassin_test.exs
git commit -m "feat(email): implement spamc client in SpamAssassin.Client

Client.scan/1 shells out to the spamc binary and parses the
X-Spam-Status header from the response. Pure parser is split out
as parse_x_spam_status/1 for unit testing without shelling out.
Fail-safe: missing binary and non-zero exits return {:error, _}."
```

---

## Task 3: Wire the scan into the inbound pipeline

**Goal of this task:** call `SpamAssassin.scan/1` from `IncomingEmailHandler.handle_incoming_email/3` before the spam check, and inject the returned header into the `data` so `SpamHandler.spam?/1` and `get_spamassassin_header/1` see it. Two rules from Global Constraints: **don't rescan if `X-Spam-Status` is already present** (Haraka may still be injecting it during rollout), and **fail safe** (any error → behave exactly like today's missing-header path).

**Files:**
- Modify: `lib/shroud/email/incoming_email_handler.ex`
- Modify: `test/shroud/email/email_handler_test.exs` (this is the integration test file; `incoming_email_handler` is exercised through `EmailHandler.perform/1`)

**Interfaces:**
- Consumes: `Shroud.Email.SpamAssassin.scan/1` (Tasks 1 & 2)
- Produces: a new private function `maybe_inject_spamassassin_header/1` in `IncomingEmailHandler` that takes raw `data` and returns possibly-rewritten `data`.

**Where exactly in `handle_incoming_email/3`:** the scan must run *once*, *after* the recipient is known to be valid (so we don't scan mail we're going to drop anyway — that wastes a spamd round-trip and could be a DoS vector), and *before* the `SpamHandler.spam?(data)` cond branch. The natural place is the very first line of the function body, before the `cond`, because `spam?/1` is one of the cond branches and needs the rewritten data. The cost of scanning mail for unknown recipients is acceptable *if* we early-return for them first — but the current code's unknown-recipient branch just logs and returns; the scan would run before that check. To avoid scanning dropped mail, **only scan when we are going to forward or quarantine** — i.e. move the scan to right before the `SpamHandler.spam?(data)` branch, and have the `true ->` (forward) branch also use the scanned data. Cleanest: scan once at the top of the function, gated by "is the header already present", and thread the result through. Since `forward_incoming_email/4` re-parses the raw `data`, injecting the header into `data` propagates everywhere.

- [ ] **Step 1: Write the failing tests**

Append to `test/shroud/email/email_handler_test.exs`, inside the `describe "perform/1"` block (or a new `describe "SpamAssassin integration"` block — either works; new block is cleaner). The test must use `Shroud.MockSpamAssassin` to control the scan and assert that the header is injected and that spam is detected.

First, ensure the test imports Mox (already imported at top of `email_handler_test.exs`: `import Mox`).

```elixir
  describe "SpamAssassin integration" do
    setup do
      user = user_fixture(%{status: :active, email: "user@example.com"})
      email_alias = alias_fixture(%{user_id: user.id, address: "alias@email.shroud.test"})

      # Enable SpamAssassin and point at the mock for these tests.
      original = Application.get_env(:shroud, :spamassassin, [])
      Application.put_env(:shroud, :spamassassin,
        enabled: true,
        module: Shroud.MockSpamAssassin
      )

      on_exit(fn -> Application.put_env(:shroud, :spamassassin, original) end)

      %{user: user, email_alias: email_alias}
    end

    test "scans a clean email and forwards it", %{user: user, email_alias: email_alias} do
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw -> {:ok, "No, score=-1.0 required=5.0 tests=NONE version=3.4.1"} end)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Hello",
          "Plain text"
        )

      perform_job(EmailHandler, %{from: "sender@example.com", to: email_alias.address, data: data})

      assert_email_sent(fn email ->
        assert email.text_body =~ "Plain text"
      end)

      # Spam email was NOT stored
      assert Email.list_spam_emails(user) == []
    end

    test "stores a scanned spam email in detention", %{user: user, email_alias: email_alias} do
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw ->
        {:ok, "Yes, score=8.2 required=5.0 tests=FOO,BAR version=3.4.1"}
      end)

      data =
        text_email(
          "spammer@example.com",
          [email_alias.address],
          "Viagra",
          "Buy now"
        )

      perform_job(EmailHandler, %{from: "spammer@example.com", to: email_alias.address, data: data})

      # No forwarded email
      assert_no_email_sent()

      # Spam email IS stored, with the SA header
      spam_email = hd(Email.list_spam_emails(user))
      assert spam_email.spamassassin_header =~ "Yes, score=8.2"
    end

    test "fails safe when scan returns an error (forwards as non-spam)", %{
      user: user,
      email_alias: email_alias
    } do
      Shroud.MockSpamAssassin
      |> expect(:scan, fn _raw -> {:error, :spamc_nonzero_exit} end)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Hello",
          "Plain text"
        )

      # Must not raise, must not drop the mail, must forward it.
      perform_job(EmailHandler, %{from: "sender@example.com", to: email_alias.address, data: data})

      assert_email_sent(fn email -> assert email.text_body =~ "Plain text" end)
      assert Email.list_spam_emails(user) == []
    end

    test "does not rescan when X-Spam-Status is already present (Haraka still active)", %{
      email_alias: email_alias
    } do
      # When the header is already on the message, the scan MUST NOT be called.
      Shroud.MockSpamAssassin
      |> expect(:scan, 0, fn _raw -> {:ok, "should not be called"} end)

      data =
        text_email(
          "sender@example.com",
          [email_alias.address],
          "Hello",
          "Plain text",
          "X-Spam-Status: No, score=-1.0 required=5.0 tests=NONE version=3.4.1"
        )

      perform_job(EmailHandler, %{from: "sender@example.com", to: email_alias.address, data: data})

      # The Mox `expect(..., 0, ...)` assertion: any call would fail the test.
    end
  end
```

Note: the `expect(module, fn, 0, ...)` form asserts the function is called exactly zero times. If Mox in this version doesn't support the count form, replace with `stub(Shroud.MockSpamAssassin, :scan, fn _ -> ExUnit.Assertions.flunk("should not be called") end)` — verify against the installed Mox version (`mix.exs` pins `mox ~> 1.0`, which supports `expect/4` with a count).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/shroud/email/email_handler_test.exs`
Expected: the "scans a clean email", "stores a scanned spam email", and "fails safe" tests fail because `scan` is never called (the mock has an unfulfilled `expect`), and the "spam" test fails because the email is forwarded instead of being stored as spam. The "does not rescan" test should already pass (the scan isn't called today either). Confirm each failure is for the *expected* reason.

- [ ] **Step 3: Implement the injection in `IncomingEmailHandler`**

Modify `lib/shroud/email/incoming_email_handler.ex`. Add an alias and a private function, and call it at the top of `handle_incoming_email/3`.

Add to the alias block at the top:

```elixir
alias Shroud.Email.SpamAssassin
```

Replace the opening of `handle_incoming_email/3`:

```elixir
  def handle_incoming_email(sender, recipient, data) do
    data = maybe_inject_spamassassin_header(data)

    # Lookup real email based on the receiving alias (`recipient`)
    recipient_user = Accounts.get_user_by_alias(recipient)
    # ... rest unchanged
```

Add the private helper at the bottom of the module (before the final `end`):

```elixir
  # If SpamAssassin scanning is enabled and the inbound message does not
  # already carry an X-Spam-Status header (Haraka may still inject one
  # during the rollout window), run the scan and prepend the header to
  # the raw data so the existing SpamHandler header-reading code sees it.
  #
  # Fail-safe: any error from the scanner is logged and the original
  # data is returned unchanged. This matches today's "missing header"
  # behaviour, where SpamHandler.spam?/1 returns false and the email
  # is forwarded normally.
  @spec maybe_inject_spamassassin_header(String.t()) :: String.t()
  defp maybe_inject_spamassassin_header(data) do
    cond do
      has_spamassassin_header?(data) ->
        # Haraka (or a previous scan) already added the header. Don't rescan.
        data

      true ->
        case SpamAssassin.scan(data) do
          {:ok, header_value} ->
            inject_header(data, "X-Spam-Status", header_value)

          :disabled ->
            data

          {:error, reason} ->
            Logger.warning("SpamAssassin scan failed: #{inspect(reason)}; forwarding as non-spam")
            data
        end
    end
  end

  @spec has_spamassassin_header?(String.t()) :: boolean()
  defp has_spamassassin_header?(data) do
    case String.split(data, ~r/\r?\n\r?\n/, parts: 2) do
      [headers | _] ->
        headers
        |> String.split(~r/\r?\n/)
        |> Enum.any?(fn line ->
          case String.split(line, ":", parts: 2) do
            [name, _] -> String.downcase(String.trim(name)) == "x-spam-status"
            _ -> false
          end
        end)

      _ ->
        false
    end
  end

  @spec inject_header(String.t(), String.t(), String.t()) :: String.t()
  defp inject_header(data, name, value) do
    # Insert the header right after the first header line (or at the top
    # if the message is degenerate). We split headers from body, prepend
    # the new header to the headers block, and rejoin with the blank
    # line separator. This is deliberately simple — mimemail/Mailex will
    # re-parse the result downstream.
    case String.split(data, ~r/\r?\n\r?\n/, parts: 2) do
      [headers, body] ->
        headers <> "\r\n" <> name <> ": " <> value <> "\r\n\r\n" <> body

      [headers] ->
        headers <> "\r\n" <> name <> ": " <> value <> "\r\n\r\n"

      [] ->
        name <> ": " <> value <> "\r\n\r\n"
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/shroud/email/email_handler_test.exs`
Expected: all four new tests pass, and every existing test in the file still passes. If the "does not rescan" test fails because `expect(_, 0, _)` isn't honoured, switch to the `stub` + `flunk` form described in Step 1.

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: all green. Existing `spam_handler_test.exs` is unaffected because it operates on already-constructed emails with explicit `X-Spam-Status` headers and does not go through `IncomingEmailHandler`.

- [ ] **Step 6: Commit**

```bash
git add lib/shroud/email/incoming_email_handler.ex test/shroud/email/email_handler_test.exs
git commit -m "feat(email): scan inbound mail with SpamAssassin in-process

IncomingEmailHandler now calls Shroud.Email.SpamAssassin.scan/1
before the spam check and injects the X-Spam-Status header into the
raw data. If the header is already present (Haraka still running), the
scan is skipped. Errors fail safe: log and forward as non-spam, matching
the prior missing-header behaviour."
```

---

## Task 4: Config + env vars + docs

**Goal of this task:** wire env vars through `config/runtime.exs` so prod can turn the feature on, set sensible defaults (off in test, off in dev unless overridden, on in prod when the spamassassin container is reachable), and document the rollout.

**Files:**
- Modify: `config/config.exs` (default `enabled: false`)
- Modify: `config/test.exs` (explicit `enabled: false`, `module: Shroud.MockSpamAssassin`)
- Modify: `config/runtime.exs` (read `SPAMASSASSIN_ENABLED` and `SPAMC_PATH`)
- Modify: `AGENTS.md` (one-line pipeline note)
- Possibly modify: `example.env` or `.env.example` (check which exists first)

- [ ] **Step 1: Write a test that asserts the prod config defaults**

There is no existing `config_test.exs`; rather than introduce one, this task is config + docs and the verification is manual (`mix test` still green, `config/runtime.exs` parses). Skip the failing-test step for the docs portion (allowed: configuration files are a TDD exception per the skill), but DO add one smoke test in `spam_assassin_test.exs` that proves `runtime.exs`'s env-var branch produces the right config when the env is set — if and only if such a test is cheap. If it isn't (runtime.exs is hard to exercise in test), skip it and verify by reading. **Decision: skip the test for config; verify by reading and by `mix test` staying green.**

- [ ] **Step 2: Update `config/config.exs`**

Add near the `:mailer` config block:

```elixir
config :shroud, :spamassassin,
  enabled: false,
  module: Shroud.Email.SpamAssassin.Stub,
  spamc_path: "spamc"
```

- [ ] **Step 3: Update `config/test.exs`**

Add:

```elixir
config :shroud, :spamassassin,
  enabled: false,
  module: Shroud.MockSpamAssassin,
  spamc_path: "spamc"
```

- [ ] **Step 4: Update `config/runtime.exs`**

In the prod block (after the mailer config), add:

```elixir
  # SpamAssassin — when enabled, shroud scans inbound mail itself via the
  # spamc CLI instead of relying on Haraka to inject X-Spam-Status.
  spamassassin_enabled = System.get_env("SPAMASSASSIN_ENABLED") == "true"
  spamc_path = System.get_env("SPAMC_PATH") || "spamc"

  config :shroud, :spamassassin,
    enabled: spamassassin_enabled,
    module: Shroud.Email.SpamAssassin.Client,
    spamc_path: spamc_path
```

- [ ] **Step 5: Document the env vars**

Check for `example.env` or `.env.example` in the repo root (`ls example.env .env.example 2>/dev/null`). If one exists, append:

```
# Set to "true" to enable in-process SpamAssassin scanning (step 1 of Haraka removal).
# When disabled, shroud relies on Haraka injecting X-Spam-Status (legacy behaviour).
SPAMASSASSIN_ENABLED=false

# Path to the spamc binary (shipped by the spamassassin container). Default: "spamc".
# SPAMC_PATH=spamc
```

- [ ] **Step 6: Update `AGENTS.md`**

In the "Email Processing Pipeline" section under Architecture, change the one-line pipeline diagram and add a sentence:

```
SMTP Input → ParsedEmail → SpamAssassin Scan → Tracker Removal → Spam Check → Forward
```

Add immediately after the pipeline:

> SpamAssassin scanning now runs in-process (`Shroud.Email.SpamAssassin`), gated by the
> `SPAMASSASSIN_ENABLED` env var. When disabled, shroud falls back to reading the
> `X-Spam-Status` header injected by Haraka. See `docs/superpowers/plans/2026-07-04-spamassassin-into-shroud.md`.

- [ ] **Step 7: Run the full suite one final time**

Run: `mix test && mix credo --strict lib/shroud/email/spam_assassin.ex lib/shroud/email/incoming_email_handler.ex`
Expected: all tests pass; credo clean on the new/modified files. If credo complains about the `@callback` on the outer module (duplicate of `Behaviour`), remove the outer `@callback` and keep only `Behaviour`'s.

- [ ] **Step 8: Format and commit**

```bash
mix format
git add config/config.exs config/test.exs config/runtime.exs AGENTS.md
# plus example.env / .env.example if modified
git commit -m "chore(email): wire SPAMASSASSIN_ENABLED env var and docs

Default off. Prod enables via runtime.exs to scan in-process using
Shroud.Email.SpamAssassin.Client (spamc CLI). Test config points at
the Mox mock. Docs note the new pipeline step."
```

---

## Rollout notes (not tasks — informational, for the PR description)

1. **Ship behind the flag.** `SPAMASSASSIN_ENABLED=false` by default. Haraka keeps running its own SA and injecting `X-Spam-Status`. shroud's new code path is dormant.
2. **Flip the flag on one node.** Set `SPAMASSASSIN_ENABLED=true` on the shroud container that has the `spamassassin` service reachable. shroud will now scan AND see Haraka's header — the "don't rescan" guard prevents double work, and shroud's scan result is authoritative for the detention decision (Haraka's reject-at-SMTP still runs too, but shroud's own scan is what populates `spam_emails`).
3. **Disable Haraka's SA plugin.** In `hosting/haraka/haraka_config/config/plugins`, comment out the `spamassassin` line. shroud is now the sole scanner. The `dinkel/spamassassin` container stays up — shroud is talking to it directly.
4. **(Later PR, not this one)** Remove the `spamassassin` service dependency from Haraka's `depends_on`, delete `hosting/haraka/haraka_config/config/spamassassin.ini`. That belongs in the hosting repo and is its own change.

The feature is reversible at every step: flip `SPAMASSASSIN_ENABLED` back to `false` and Haraka resumes sole scanning.

---

## Self-Review

**1. Spec coverage.** The goal is "move SpamAssassin scanning from Haraka into shroud." Task 1 builds the seam, Task 2 builds the client, Task 3 wires it into the pipeline, Task 4 makes it configurable and documented. The fail-safe and "don't rescan when header present" rules from Global Constraints each have a dedicated test. Rollout sequencing is documented. No gap.

**2. Placeholder scan.** No "TBD", "implement later", "add appropriate error handling". Every code step shows the code. The single TDD exception taken (config files in Task 4) is explicitly called out and justified.

**3. Type consistency.** `scan/1` returns `{:ok, String.t()} | {:error, term()} | :disabled` everywhere it appears (Behaviour, Stub, Client, the mock, the tests). `parse_x_spam_status/1` returns `{:ok, String.t()} | :error` consistently. `maybe_inject_spamassassin_header/1` returns `String.t()` (always — fail-safe returns the original `data`). Names match across tasks: `Shroud.Email.SpamAssassin`, `Shroud.Email.SpamAssassin.Behaviour`, `Shroud.Email.SpamAssassin.Client`, `Shroud.Email.SpamAssassin.Stub`, `Shroud.MockSpamAssassin`, config key `:spamassassin` with sub-keys `:enabled` / `:module` / `:spamc_path`. Env vars `SPAMASSASSIN_ENABLED`, `SPAMC_PATH` — same casing throughout.

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-04-spamassassin-into-shroud.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**

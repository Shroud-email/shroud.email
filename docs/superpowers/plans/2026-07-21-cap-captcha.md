# Cap CAPTCHA Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cap (self-hosted, open-source CAPTCHA) to Shroud.email, env-gated so self-hosters who set no `CAP_*` vars see no behavior change.

**Architecture:** A `Shroud.Captcha` boundary module wraps the Cap Standalone `/siteverify` HTTP call via Req. A `VerifyCaptcha` plug gates the three protected POST routes, short-circuiting to a no-op when Cap is disabled (the "optional" guarantee). A `<.cap_widget />` function component renders the Cap widget in the three auth forms. Cap + Valkey services run in Docker Compose (both repos); the app only activates when all three env vars are set.

**Tech Stack:** Elixir/Phoenix 1.8, Req 0.6 (HTTP client, tested via `Req.Test`), Plug, HEEx function components, Docker Compose, Valkey.

**Spec:** `docs/superpowers/specs/2026-07-21-cap-captcha-design.md`

## Global Constraints

- **Cap is optional.** All behavior changes must be gated on `Shroud.Captcha.enabled?/0`. When any of `CAP_INSTANCE_URL`, `CAP_SITE_KEY`, `CAP_SECRET_KEY` is unset, the app behaves exactly as today: no widget script, no verification HTTP call, no broken forms.
- **Fail closed.** Network errors / decode failures during verification reject the request; never fall through to success.
- **Secret key never reaches the browser.** `CAP_SECRET_KEY` is server-side only. `CAP_SITE_KEY` is public.
- **Widget version pinned.** `@cap.js/widget@0.1.56` exactly (Cap's "pin version" common-failure rule).
- **Trailing slash on widget endpoint.** `widget_endpoint/0` must end in `/` (Cap's #1 common failure mode).
- **No inline `<script>` in templates** (AGENTS.md rule). The widget script is loaded via a `<script src=...>` tag like the existing Chatwoot/Better Stack/Plausible scripts in `root.html.heex`.
- **Conventional Commits.** `feat:`, `chore:`, `docs:` prefixes.
- **Run `mix format` before each commit.** (credo runs on commit via husky.)
- **Valkey service named `valkey`** (not `cap_valkey`) in both compose files, for future reuse.

---

## File Structure

**Create:**
- `lib/shroud/captcha.ex` — boundary module: `enabled?/0`, `verify/1`, `widget_endpoint/0`
- `lib/shroud_web/plugs/verify_captcha.ex` — plug: no-op when disabled, else verify token
- `lib/shroud_web/components/cap.ex` — `<.cap_widget />` function component
- `test/shroud/captcha_test.exs` — unit tests for the boundary module
- (hosting repo) no new files; edits to `docker-compose.yaml`, `example.env`, `README.md`

**Modify:**
- `mix.exs` — add `{:req, "~> 0.6"}`
- `config/runtime.exs` — read the three `CAP_*` env vars into app env
- `config/test.exs` — inject `plug: {Req.Test, Shroud.Captcha}` into cap req options
- `lib/shroud_web.ex` — import `ShroudWeb.Components.Cap` into `html_helpers`
- `lib/shroud_web/router.ex` — add `plug VerifyCaptcha when action in [:create]` to the 3 routes
- `lib/shroud_web/controllers/user_registration_html/new.html.heex` — add `<.cap_widget />`
- `lib/shroud_web/controllers/user_session_html/new.html.heex` — add `<.cap_widget />`
- `lib/shroud_web/controllers/user_reset_password_html/new.html.heex` — add `<.cap_widget />`
- `test/shroud_web/controllers/user_registration_controller_test.exs` — add Cap tests
- `test/shroud_web/controllers/user_session_controller_test.exs` — add Cap tests
- `test/shroud_web/controllers/user_reset_password_controller_test.exs` — add Cap tests
- `example.env` — append three `CAP_*` vars with comments
- `docker-compose.yaml` (shroud.email repo) — add `cap` + `valkey` services
- `~/dev/shroud/hosting/docker-compose.yaml` — add `cap` + `valkey` services + `CAP_*` on `web`
- `~/dev/shroud/hosting/example.env` — append `CAP_*` placeholders + `CAP_ADMIN_KEY`
- `~/dev/shroud/hosting/README.md` — document Cap setup

---

### Task 1: Add Req dependency

**Files:**
- Modify: `mix.exs:91` (deps section)

**Interfaces:**
- Produces: `Req` available as a dependency for Task 2's HTTP calls.

- [ ] **Step 1: Add Req to deps**

In `mix.exs`, in the `defp deps do` list, add after the `{:httpoison, "~> 2.3"},` line (line 91):

```elixir
      {:req, "~> 0.6"},
```

- [ ] **Step 2: Fetch and compile**

Run: `mix deps.get`
Expected: dependency `req` fetched (already in lock transitively, now direct).

Run: `mix compile`
Expected: compiles without warnings.

- [ ] **Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore: add req as direct dependency"
```

---

### Task 2: Shroud.Captcha boundary module (TDD)

**Files:**
- Create: `lib/shroud/captcha.ex`
- Create: `test/shroud/captcha_test.exs`

**Interfaces:**
- Consumes: app env `:cap_instance_url`, `:cap_site_key`, `:cap_secret_key` (set in Task 6's runtime.exs; for tests, set via `Application.put_env/2`). Also `:cap_req_options` (set in `config/test.exs` in Task 7 to route through `Req.Test`).
- Produces:
  - `Shroud.Captcha.enabled?/0 :: boolean`
  - `Shroud.Captcha.verify(token :: String.t() | nil) :: :ok | {:error, :missing_token | :verification_failed | :network_error}`
  - `Shroud.Captcha.widget_endpoint/0 :: String.t() | nil`

- [ ] **Step 1: Write the failing tests**

Create `test/shroud/captcha_test.exs`:

```elixir
defmodule Shroud.CaptchaTest do
  use ExUnit.Case, async: true

  import Req.Test

  alias Shroud.Captcha

  # Helper: set all three env vars so enabled?/0 is true.
  defp enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
    Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
    Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
  end

  defp disable_cap do
    Application.put_env(:shroud, :cap_instance_url, nil)
    Application.put_env(:shroud, :cap_site_key, nil)
    Application.put_env(:shroud, :cap_secret_key, nil)
  end

  # config/test.exs sets cap_req_options: [plug: {Req.Test, Shroud.Captcha}].
  # Req.Test routes the POST through our stub. The plug receives a Plug.Conn
  # for the siteverify request; we read nothing from it and just return JSON.
  defp siteverify_response(body) do
    fn conn ->
      Req.Test.json(conn, body)
    end
  end

  describe "enabled?/0" do
    test "true when all three env vars are set" do
      enable_cap()
      assert Captcha.enabled?()
    after
      disable_cap()
    end

    test "false when any env var is nil" do
      disable_cap()
      refute Captcha.enabled?()

      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      refute Captcha.enabled?()
    after
      disable_cap()
    end
  end

  describe "widget_endpoint/0" do
    test "returns instance + site key with trailing slash when enabled" do
      enable_cap()
      assert Captcha.widget_endpoint() == "https://cap.example.com/a1b2c3d4e5/"
    after
      disable_cap()
    end

    test "returns nil when disabled" do
      disable_cap()
      assert Captcha.widget_endpoint() == nil
    end
  end

  describe "verify/1" do
    test "returns :ok when Cap responds success: true" do
      enable_cap()
      stub(Shroud.Captcha, siteverify_response(%{"success" => true}))

      assert Captcha.verify("valid-token") == :ok
    after
      disable_cap()
    end

    test "returns {:error, :verification_failed} when success: false" do
      enable_cap()
      stub(Shroud.Captcha, siteverify_response(%{"success" => false, "error" => "Token not found"}))

      assert Captcha.verify("bad-token") == {:error, :verification_failed}
    after
      disable_cap()
    end

    test "returns {:error, :missing_token} when token is nil" do
      enable_cap()
      assert Captcha.verify(nil) == {:error, :missing_token}
    after
      disable_cap()
    end

    test "returns {:error, :missing_token} when token is empty" do
      enable_cap()
      assert Captcha.verify("") == {:error, :missing_token}
    after
      disable_cap()
    end

    test "returns {:error, :network_error} on transport error (fail-closed)" do
      enable_cap()
      stub(Shroud.Captcha, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert Captcha.verify("some-token") == {:error, :network_error}
    after
      disable_cap()
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/shroud/captcha_test.exs`
Expected: FAIL — `module Shroud.Captcha is not available` / `undefined function`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/shroud/captcha.ex`:

```elixir
defmodule Shroud.Captcha do
  @moduledoc """
  Boundary module for the optional Cap CAPTCHA integration.

  Cap is enabled only when all three of CAP_INSTANCE_URL, CAP_SITE_KEY,
  and CAP_SECRET_KEY are configured. When disabled, every function here
  is a safe no-op: `enabled?/0` is false, `widget_endpoint/0` is nil, and
  the `VerifyCaptcha` plug short-circuits.
  """

  @doc """
  True iff all three Cap env vars are configured. This is the single gate
  the rest of the app checks to decide whether Cap is active.
  """
  @spec enabled? :: boolean
  def enabled? do
    instance_url() != nil and site_key() != nil and secret_key() != nil
  end

  @doc """
  The widget's `data-cap-api-endpoint` value: the Cap instance URL plus the
  site key, with a guaranteed trailing slash. Returns nil when Cap is
  disabled (so the widget is not rendered at all).
  """
  @spec widget_endpoint :: String.t() | nil
  def widget_endpoint do
    if enabled?() do
      "#{String.trim_trailing(instance_url(), "/")}/#{site_key()}/"
    else
      nil
    end
  end

  @doc """
  Verify a Cap token against the Standalone `/siteverify` endpoint.

  Returns `:ok` on success, or one of:
    * `{:error, :missing_token}` — token was nil or empty
    * `{:error, :verification_failed}` — Cap rejected the token
    * `{:error, :network_error}` — the HTTP call failed or response was
      unparseable. Fail-closed: callers should reject the request.
  """
  @spec verify(String.t() | nil) :: :ok | {:error, atom}
  def verify(nil), do: {:error, :missing_token}
  def verify(""), do: {:error, :missing_token}

  def verify(token) when is_binary(token) do
    body = %{"secret" => secret_key(), "response" => token}

    case req_post(siteverify_url(), body) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{body: %{"success" => _}}} ->
        {:error, :verification_failed}

      {:ok, %Req.Response{}} ->
        {:error, :verification_failed}

      {:error, _reason} ->
        {:error, :network_error}
    end
  end

  defp req_post(url, body) do
    options =
      [
        url: url,
        method: :post,
        json: body
      ]
      |> Keyword.merge(Application.get_env(:shroud, :cap_req_options, []))

    Req.request(options)
  end

  defp siteverify_url do
    "#{String.trim_trailing(instance_url(), "/")}/#{site_key()}/siteverify"
  end

  defp instance_url, do: Application.get_env(:shroud, :cap_instance_url)
  defp site_key, do: Application.get_env(:shroud, :cap_site_key)
  defp secret_key, do: Application.get_env(:shroud, :cap_secret_key)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/shroud/captcha_test.exs`
Expected: PASS — all 9 tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/shroud/captcha.ex test/shroud/captcha_test.exs
git commit -m "feat: add Shroud.Captcha boundary module for Cap verification"
```

---

### Task 3: VerifyCaptcha plug (TDD)

**Files:**
- Create: `lib/shroud_web/plugs/verify_captcha.ex`
- Create: `test/shroud_web/plugs/verify_captcha_test.exs`

**Interfaces:**
- Consumes: `Shroud.Captcha.enabled?/0`, `Shroud.Captcha.verify/1` (from Task 2).
- Produces: `ShroudWeb.Plugs.VerifyCaptcha` — a Plug used as `plug VerifyCaptcha when action in [:create]`.

- [ ] **Step 1: Write the failing tests**

Create `test/shroud_web/plugs/verify_captcha_test.exs`:

```elixir
defmodule ShroudWeb.Plugs.VerifyCaptchaTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest
  import Req.Test

  alias Shroud.Captcha
  alias ShroudWeb.Plugs.VerifyCaptcha

  @endpoint ShroudWeb.Endpoint

  defp enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
    Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
    Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
  end

  defp disable_cap do
    Application.put_env(:shroud, :cap_instance_url, nil)
    Application.put_env(:shroud, :cap_site_key, nil)
    Application.put_env(:shroud, :cap_secret_key, nil)
  end

  # Build a Plug.Conn shaped like a Phoenix form POST: parsed params with a
  # "cap-token" key. We don't go through the router; we invoke the plug
  # directly so the test is focused on the plug's behavior.
  defp conn_with_token(token) do
    build_conn(:post, "/users/register", %{"cap-token" => token})
  end

  describe "when Cap is disabled" do
    test "passes the conn through unchanged (no-op)" do
      disable_cap()
      conn = conn_with_token("ignored-token")
      returned = VerifyCaptcha.call(conn, [])

      assert returned == conn
    after
      disable_cap()
    end
  end

  describe "when Cap is enabled" do
    test "passes through when verify returns :ok" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.json(conn, %{"success" => true}) end)

      conn = conn_with_token("valid-token")
      returned = VerifyCaptcha.call(conn, [])

      refute returned.halted()
    after
      disable_cap()
    end

    test "rejects (flash + redirect + halt) when token is missing" do
      enable_cap()
      conn = build_conn(:post, "/users/register", %{})

      returned = VerifyCaptcha.call(conn, [])

      assert returned.halted()
      assert get_flash(returned, :error) =~ "verification"
      assert redirected_to(returned) == "/users/register"
    after
      disable_cap()
    end

    test "rejects when verify returns {:error, :verification_failed}" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.json(conn, %{"success" => false}) end)

      returned = VerifyCaptcha.call(conn_with_token("bad-token"), [])

      assert returned.halted()
      assert get_flash(returned, :error) =~ "verification"
    after
      disable_cap()
    end

    test "rejects (fail-closed) when verify returns {:error, :network_error}" do
      enable_cap()
      stub(Shroud.Captcha, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      returned = VerifyCaptcha.call(conn_with_token("some-token"), [])

      assert returned.halted()
      assert get_flash(returned, :error) =~ "verification"
    after
      disable_cap()
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/shroud_web/plugs/verify_captcha_test.exs`
Expected: FAIL — `module ShroudWeb.Plugs.VerifyCaptcha is not available`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/shroud_web/plugs/verify_captcha.ex`:

```elixir
defmodule ShroudWeb.Plugs.VerifyCaptcha do
  @moduledoc """
  Verifies the Cap CAPTCHA token on protected form submissions.

  This plug is a **no-op when Cap is disabled** (any of the three CAP_*
  env vars unset), which is what makes Cap optional for self-hosters.

  When enabled, it reads `cap-token` from the request params and verifies
  it via `Shroud.Captcha.verify/1` before the controller action runs.
  On failure it flashes an error and redirects back to the form.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller

  alias Shroud.Captcha

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Captcha.enabled?() do
      verify_token(conn, conn.params["cap-token"])
    else
      conn
    end
  end

  defp verify_token(conn, token) do
    case Captcha.verify(token) do
      :ok ->
        conn

      {:error, _reason} ->
        conn
        |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
        |> redirect(to: form_route(conn))
        |> halt()
    end
  end

  # Redirect back to the form that was being submitted. We key off the
  # request path so each protected route returns to its own form.
  defp form_route(%Plug.Conn{request_path: "/users/log_in"}), do: "/users/log_in"
  defp form_route(%Plug.Conn{request_path: "/users/reset_password"}), do: "/users/reset_password"
  defp form_route(_conn), do: "/users/register"
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/shroud_web/plugs/verify_captcha_test.exs`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/shroud_web/plugs/verify_captcha.ex test/shroud_web/plugs/verify_captcha_test.exs
git commit -m "feat: add VerifyCaptcha plug for gating protected forms"
```

---

### Task 4: `<.cap_widget />` function component

**Files:**
- Create: `lib/shroud_web/components/cap.ex`
- Modify: `lib/shroud_web.ex` (import into html_helpers)

**Interfaces:**
- Consumes: `Shroud.Captcha.enabled?/0`, `Shroud.Captcha.widget_endpoint/0` (Task 2).
- Produces: `<.cap_widget />` usable in any HEEx template.

- [ ] **Step 1: Create the component**

Create `lib/shroud_web/components/cap.ex`:

```elixir
defmodule ShroudWeb.Components.Cap do
  @moduledoc """
  Renders the Cap CAPTCHA widget.

  Renders nothing when Cap is disabled (any CAP_* env var unset), which
  keeps the integration optional for self-hosters.

  The widget script is pinned to a specific version (per Cap's "pin the
  version" guidance) and loaded once. The `<cap-widget>` custom element
  injects its own hidden `cap-token` input into the surrounding form.
  """

  use Phoenix.Component

  alias Shroud.Captcha

  # Pinned per Cap integration guide ("common failure: version unpinned").
  @widget_script_url "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.56"

  attr(:class, :string, default: nil)

  def cap_widget(assigns) do
    if Captcha.enabled?() do
      ~H"""
      <div class={["cap-widget-wrapper", @class]}>
        <script src={@widget_script_url}></script>
        <cap-widget data-cap-api-endpoint={Captcha.widget_endpoint()}></cap-widget>
      </div>
      """
    else
      ~H""
    end
  end

  defp widget_script_url, do: @widget_script_url
end
```

- [ ] **Step 2: Import the component into html_helpers**

In `lib/shroud_web.ex`, in the `defp html_helpers do` block (around line 110, after the `import ShroudWeb.Components.Atoms` line), add:

```elixir
      import ShroudWeb.Components.Cap
```

- [ ] **Step 3: Compile and verify**

Run: `mix compile`
Expected: compiles without warnings.

- [ ] **Step 4: Commit**

```bash
mix format
git add lib/shroud_web/components/cap.ex lib/shroud_web.ex
git commit -m "feat: add cap_widget function component"
```

---

### Task 5: Add `<.cap_widget />` to the three auth forms

**Files:**
- Modify: `lib/shroud_web/controllers/user_registration_html/new.html.heex` (before submit button at line 42)
- Modify: `lib/shroud_web/controllers/user_session_html/new.html.heex` (before submit button at line 51)
- Modify: `lib/shroud_web/controllers/user_reset_password_html/new.html.heex` (before submit button at line 23)

**Interfaces:**
- Consumes: `<.cap_widget />` from Task 4.

- [ ] **Step 1: Add widget to registration form**

In `lib/shroud_web/controllers/user_registration_html/new.html.heex`, insert immediately before the `<div>` containing the submit button (the `<div>` starting at line ~40 with `<%= submit "Sign up" ...`):

```html
        <.cap_widget />

```

- [ ] **Step 2: Add widget to login form**

In `lib/shroud_web/controllers/user_session_html/new.html.heex`, insert immediately before the `<div>` containing the submit button (line ~50 with `<%= submit "Sign in"`):

```html
        <.cap_widget />

```

- [ ] **Step 3: Add widget to reset password form**

In `lib/shroud_web/controllers/user_reset_password_html/new.html.heex`, insert immediately before the `<div>` containing the submit button (line ~22 with `<%= submit "Send instructions"`):

```html
        <.cap_widget />

```

- [ ] **Step 4: Verify forms still render with Cap disabled**

Run: `mix phx.server` (in another terminal) and load `/users/register`, `/users/log_in`, `/users/reset_password`. With no `CAP_*` env vars set, the widget renders nothing and the forms work as before.

(If the dev server can't start without a DB, instead run `mix test test/shroud_web/controllers/user_registration_controller_test.exs` and confirm existing tests still pass — they will fail only if the template broke compilation.)

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/shroud_web/controllers/user_registration_html/new.html.heex \
        lib/shroud_web/controllers/user_session_html/new.html.heex \
        lib/shroud_web/controllers/user_reset_password_html/new.html.heex
git commit -m "feat: render cap_widget in register, login, and reset_password forms"
```

---

### Task 6: Wire the plug into the router

**Files:**
- Modify: `lib/shroud_web/router.ex:81-94` (the `:redirect_if_user_is_authenticated` scope)

**Interfaces:**
- Consumes: `ShroudWeb.Plugs.VerifyCaptcha` from Task 3.

- [ ] **Step 1: Add the plug declaration**

In `lib/shroud_web/router.ex`, in the scope that contains the three POST routes (starts at line 81 with `scope "/", ShroudWeb do` / `pipe_through([:browser, :redirect_if_user_is_authenticated])`), add a `plug` line after the `pipe_through` call:

```elixir
    pipe_through([:browser, :redirect_if_user_is_authenticated])
    plug(:verify_captcha_when_create)
```

Then add the plug function at the end of the module (before the final `end`), alongside the other imported plug helpers:

```elixir
  defp verify_captcha_when_create(conn, _opts) do
    if conn.action == :create do
      ShroudWeb.Plugs.VerifyCaptcha.call(conn, [])
    else
      conn
    end
  end
```

Note: `Phoenix.Controller.action_name/1` gives the action atom; this restricts verification to the `:create` POST handlers (not the GET `:new` form renders), matching `plug ... when action in [:create]` semantics.

- [ ] **Step 2: Verify router compiles**

Run: `mix compile`
Expected: compiles without warnings.

- [ ] **Step 3: Commit**

```bash
mix format
git add lib/shroud_web/router.ex
git commit -m "feat: gate register/login/reset_password create actions with VerifyCaptcha"
```

---

### Task 7: Config — runtime.exs, test.exs, example.env

**Files:**
- Modify: `config/runtime.exs` (near the chatwoot config, lines 6-13)
- Modify: `config/test.exs`
- Modify: `example.env`

**Interfaces:**
- Consumes: env vars `CAP_INSTANCE_URL`, `CAP_SITE_KEY`, `CAP_SECRET_KEY`.
- Produces: app env `:cap_instance_url`, `:cap_site_key`, `:cap_secret_key` (for Task 2) and `:cap_req_options` test stub (for Task 2 tests).

- [ ] **Step 1: Read CAP_* env vars in runtime.exs**

In `config/runtime.exs`, immediately after the chatwoot config block (after line 13, `chatwoot_hmac_token: System.get_env("CHATWOOT_HMAC_TOKEN")`), add:

```elixir

# Optional: Cap CAPTCHA. Set all three of CAP_INSTANCE_URL, CAP_SITE_KEY,
# and CAP_SECRET_KEY to enable. When any is unset, Cap is fully disabled
# (no widget rendered, no verification performed). The instance URL is
# the Cap Standalone base, e.g. http://cap:3000 (in compose) or
# https://cap.yourdomain.com.
config :shroud,
  cap_instance_url: System.get_env("CAP_INSTANCE_URL"),
  cap_site_key: System.get_env("CAP_SITE_KEY"),
  cap_secret_key: System.get_env("CAP_SECRET_KEY")
```

- [ ] **Step 2: Inject Req.Test stub in test.exs**

In `config/test.exs`, add (anywhere in the file; convention is near other app config):

```elixir
# Route Shroud.Captcha's Req requests through Req.Test stubs in tests.
config :shroud, :cap_req_options, plug: {Req.Test, Shroud.Captcha}
```

- [ ] **Step 3: Append CAP_* vars to example.env**

In `example.env`, append at the end:

```env

# Cap CAPTCHA (optional). Set all three to enable Cap on the signup,
# login, and password-reset forms. Leave unset to disable (forms work
# without Cap). See docker-compose.yaml for the cap + valkey services.
CAP_INSTANCE_URL=
CAP_SITE_KEY=
CAP_SECRET_KEY=
```

- [ ] **Step 4: Verify config compiles and Task 2 tests still pass**

Run: `mix test test/shroud/captcha_test.exs`
Expected: PASS — the `:cap_req_options` plug is now set globally for tests.

Run: `mix compile`
Expected: compiles without warnings.

- [ ] **Step 5: Commit**

```bash
mix format
git add config/runtime.exs config/test.exs example.env
git commit -m "feat: wire Cap env config and Req.Test stub"
```

---

### Task 8: Controller tests — forged POST is rejected, valid passes, disabled unchanged

**Files:**
- Modify: `test/shroud_web/controllers/user_registration_controller_test.exs`
- Modify: `test/shroud_web/controllers/user_session_controller_test.exs`
- Modify: `test/shroud_web/controllers/user_reset_password_controller_test.exs`

**Interfaces:**
- Consumes: `Shroud.Captcha` (Task 2), `VerifyCaptcha` plug (Task 3), `Req.Test` (test.exs Task 7).

- [ ] **Step 1: Add Cap tests to registration controller test**

In `test/shroud_web/controllers/user_registration_controller_test.exs`, add a new describe block at the end of the module. Add these imports at the top (after `use ShroudWeb.ConnCase`):

```elixir
  import Req.Test
```

Add the describe block:

```elixir
  describe "POST /users/register with Cap enabled" do
    defp enable_cap do
      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
      Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
    end

    defp disable_cap do
      Application.put_env(:shroud, :cap_instance_url, nil)
      Application.put_env(:shroud, :cap_site_key, nil)
      Application.put_env(:shroud, :cap_secret_key, nil)
    end

    test "rejects a forged POST with no cap-token", %{conn: conn} do
      enable_cap()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: unique_user_email())
        })

      assert redirected_to(conn) == "/users/register"
      assert get_flash(conn, :error) =~ "verification"
    after
      disable_cap()
    end

    test "creates account when cap-token verifies", %{conn: conn} do
      enable_cap()
      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cap-token" => "valid-token"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"
    after
      disable_cap()
    end
  end
```

- [ ] **Step 2: Add Cap tests to session controller test**

In `test/shroud_web/controllers/user_session_controller_test.exs`, add `import Req.Test` after `use ShroudWeb.ConnCase`, and add this describe block at the end (uses the `user_fixture()` from the existing `setup`):

```elixir
  describe "POST /users/log_in with Cap enabled" do
    defp enable_cap do
      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
      Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
    end

    defp disable_cap do
      Application.put_env(:shroud, :cap_instance_url, nil)
      Application.put_env(:shroud, :cap_site_key, nil)
      Application.put_env(:shroud, :cap_secret_key, nil)
    end

    test "rejects a forged POST with no cap-token", %{conn: conn, user: user} do
      enable_cap()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/users/log_in"
      assert get_flash(conn, :error) =~ "verification"
    after
      disable_cap()
    end

    test "logs in when cap-token verifies", %{conn: conn, user: user} do
      enable_cap()
      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()},
          "cap-token" => "valid-token"
        })

      assert get_session(conn, :user_token)
    after
      disable_cap()
    end
  end
```

- [ ] **Step 3: Add Cap tests to reset password controller test**

In `test/shroud_web/controllers/user_reset_password_controller_test.exs`, add `import Req.Test` after `use ShroudWeb.ConnCase`, and add this describe block at the end:

```elixir
  describe "POST /users/reset_password with Cap enabled" do
    defp enable_cap do
      Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
      Application.put_env(:shroud, :cap_site_key, "a1b2c3d4e5")
      Application.put_env(:shroud, :cap_secret_key, "sk-testsecret")
    end

    defp disable_cap do
      Application.put_env(:shroud, :cap_instance_url, nil)
      Application.put_env(:shroud, :cap_site_key, nil)
      Application.put_env(:shroud, :cap_secret_key, nil)
    end

    test "rejects a forged POST with no cap-token", %{conn: conn} do
      enable_cap()

      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => "someone@example.com"}
        })

      assert redirected_to(conn) == "/users/reset_password"
      assert get_flash(conn, :error) =~ "verification"
    after
      disable_cap()
    end

    test "sends reset instructions when cap-token verifies", %{conn: conn} do
      enable_cap()
      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => "someone@example.com"},
          "cap-token" => "valid-token"
        })

      assert redirected_to(conn) == "/users/log_in"
      assert get_flash(conn, :info) =~ "If your email is in our system"
    after
      disable_cap()
    end
  end
```

- [ ] **Step 4: Run all affected controller tests**

Run: `mix test test/shroud_web/controllers/user_registration_controller_test.exs test/shroud_web/controllers/user_session_controller_test.exs test/shroud_web/controllers/user_reset_password_controller_test.exs`
Expected: PASS — all existing tests (Cap disabled, unchanged behavior) + new Cap-enabled tests.

- [ ] **Step 5: Run the full test suite as a regression check**

Run: `mix test`
Expected: PASS — no regressions. The "disabled" path is exercised by every pre-existing test (no `CAP_*` env in test env).

- [ ] **Step 6: Commit**

```bash
mix format
git add test/shroud_web/controllers/user_registration_controller_test.exs \
        test/shroud_web/controllers/user_session_controller_test.exs \
        test/shroud_web/controllers/user_reset_password_controller_test.exs
git commit -m "test: add Cap verification tests for register, login, reset_password"
```

---

### Task 9: Docker Compose — local dev (shroud.email repo)

**Files:**
- Modify: `docker-compose.yaml` (shroud.email repo)

**Interfaces:**
- Produces: local `cap` (port 3000) + `valkey` services for dev testing.

- [ ] **Step 1: Add cap + valkey services to local docker-compose**

Replace the contents of `docker-compose.yaml` with:

```yaml
services:
  db:
    image: postgres:14
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: shroud
    ports:
      - "5432:5432"

  cap:
    image: tiago2/cap:latest
    restart: unless-stopped
    depends_on:
      - valkey
    ports:
      - "3000:3000"
    environment:
      - ADMIN_KEY=${CAP_ADMIN_KEY}
      - REDIS_URL=redis://valkey:6379

  valkey:
    image: valkey/valkey:9-alpine
    restart: unless-stopped
    command: valkey-server --save 60 1 --loglevel warning --maxmemory-policy noeviction
    volumes:
      - valkey_data:/data

volumes:
  valkey_data:
```

- [ ] **Step 2: Generate a CAP_ADMIN_KEY and add to local .env**

Run: `openssl rand -hex 32`
Expected: a 64-char hex string. Copy it.

Append to `.env` (the local dev env, gitignored):

```env
CAP_ADMIN_KEY=<paste the hex here>
CAP_INSTANCE_URL=http://localhost:3000
CAP_SITE_KEY=
CAP_SECRET_KEY=
```

(Leave `CAP_SITE_KEY`/`CAP_SECRET_KEY` blank until Task 11 creates the site key.)

- [ ] **Step 3: Verify services start**

Run: `docker compose up -d cap valkey`
Expected: both containers start; `docker compose logs cap` shows Cap listening on port 3000.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yaml
git commit -m "feat: add cap + valkey services to local dev docker-compose"
```

(Note: `.env` is gitignored — do not commit it.)

---

### Task 10: Docker Compose — hosting repo + README + example.env

**Files:**
- Modify: `~/dev/shroud/hosting/docker-compose.yaml`
- Modify: `~/dev/shroud/hosting/example.env`
- Modify: `~/dev/shroud/hosting/README.md`

**Interfaces:**
- Produces: production compose with `cap` + `valkey`, `CAP_*` env on `web`, documented setup.

- [ ] **Step 1: Add cap + valkey services to hosting docker-compose**

In `~/dev/shroud/hosting/docker-compose.yaml`, add two new services (`cap`, `valkey`) at the same indentation as `web`, `db`, etc. Add them after the `haraka` service block:

```yaml
  cap:
    image: tiago2/cap:latest
    restart: unless-stopped
    depends_on:
      - valkey
    environment:
      - ADMIN_KEY=${CAP_ADMIN_KEY}
      - REDIS_URL=redis://valkey:6379
      - CORS_ORIGIN=https://${APP_DOMAIN}

  valkey:
    image: valkey/valkey:9-alpine
    restart: unless-stopped
    command: valkey-server --save 60 1 --loglevel warning --maxmemory-policy noeviction
    volumes:
      - valkey_data:/data
```

- [ ] **Step 2: Add CAP_* env to the web service**

In the same file, in the `web:` service's `environment:` list, add after the `LOOPS_ACTIVE_USERS_LIST_ID` line:

```yaml
      - CAP_INSTANCE_URL=http://cap:3000
      - CAP_SITE_KEY=${CAP_SITE_KEY}
      - CAP_SECRET_KEY=${CAP_SECRET_KEY}
```

- [ ] **Step 3: Add valkey_data volume**

In the same file, in the top-level `volumes:` block, add:

```yaml
  valkey_data:
```

- [ ] **Step 4: Append CAP_* placeholders to hosting example.env**

In `~/dev/shroud/hosting/example.env`, append at the end:

```env

## Cap CAPTCHA (optional but included in the default compose).
## Set all three to enable Cap on the signup/login/reset forms.
## CAP_ADMIN_KEY: dashboard password. Generate with: openssl rand -hex 32
CAP_ADMIN_KEY=
## Create a site key (rsw + instrumentation) via the dashboard API:
##   curl -X POST http://localhost:3000/server/keys \
##     -H "Authorization: Bot $CAP_ADMIN_KEY" \
##     -d '{"name":"shroud-email","instrumentation":true,"rsw":true}'
CAP_SITE_KEY=
CAP_SECRET_KEY=
```

- [ ] **Step 5: Document Cap setup in README.md**

In `~/dev/shroud/hosting/README.md`, append a new section:

```markdown

## Cap CAPTCHA

The compose file includes a [Cap](https://trycap.dev) self-hosted CAPTCHA
instance (the `cap` + `valkey` services). Cap protects the signup, login,
and password-reset forms. It is **opt-in at the application level**: the
services run by default, but the widget is not rendered and verification
is not performed until you set all three `CAP_*` variables on the `web`
service.

### Setup

1. Generate an admin key and set `CAP_ADMIN_KEY` in `.env`:
   ```bash
   openssl rand -hex 32
   ```

2. Start the services:
   ```bash
   docker compose up -d cap valkey
   ```

3. Create a site key with the strongest challenge combination
   (RSW time-lock + JS instrumentation):
   ```bash
   curl -X POST http://<cap-host>:3000/server/keys \
     -H "Authorization: Bot $CAP_ADMIN_KEY" \
     -H "Content-Type: application/json" \
     -d '{"name":"shroud-email","instrumentation":true,"rsw":true}'
   ```
   The response returns `siteKey` and `secretKey` (shown only once — save it).

4. Set `CAP_SITE_KEY` and `CAP_SECRET_KEY` in `.env` and restart `web`:
   ```bash
   docker compose restart web
   ```

Cap verifies tokens are single-use. The secret key never reaches the
browser; only the site key is public.
```

- [ ] **Step 6: Verify hosting compose is valid**

Run: `cd ~/dev/shroud/hosting && docker compose config > /dev/null`
Expected: no errors (validates the YAML + env interpolation).

- [ ] **Step 7: Commit (in the hosting repo)**

```bash
cd ~/dev/shroud/hosting
git add docker-compose.yaml example.env README.md
git commit -m "feat: add Cap + valkey services and document Cap setup"
```

---

### Task 11: Create the Cap site key + end-to-end verification

**Files:**
- No files (operational verification). Uses local compose from Task 9.

**Prerequisites:** Task 9's local `cap` + `valkey` services running.

- [ ] **Step 1: Create the site key with rsw + instrumentation**

Ensure `cap` service is running (`docker compose up -d cap valkey`).

Run (substitute `$CAP_ADMIN_KEY` from `.env`):
```bash
curl -X POST http://localhost:3000/server/keys \
  -H "Authorization: Bot $CAP_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"shroud-email-local","instrumentation":true,"rsw":true}'
```
Expected: JSON like `{"siteKey":"<10 hex>","secretKey":"sk-..."}`. Copy both.

- [ ] **Step 2: Fill in the local .env**

In `.env`, set:
```env
CAP_SITE_KEY=<siteKey from step 1>
CAP_SECRET_KEY=<secretKey from step 1>
```

- [ ] **Step 3: Verify the widget solves**

Start the dev server: `mix phx.server` (in a terminal).
Open `http://localhost:4000/users/register` in a real browser.
Expected: the Cap checkbox appears and resolves to a checkmark within ~2s. No console errors.
Repeat for `/users/log_in` and `/users/reset_password`.

- [ ] **Step 4: Verify a valid submission passes**

Submit the registration form normally (solve the widget first).
Expected: account created, redirected to `/users/confirm` (existing behavior).

- [ ] **Step 5: Verify a forged submission fails**

```bash
curl -X POST http://localhost:4000/users/register \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user[email]=test@example.com" \
  --data-urlencode "user[password]=somepassword1234"
```
Expected: redirect to `/users/register` with an error flash (302 or 200 re-render with flash). The account is **not** created.

- [ ] **Step 6: Verify single-use enforcement**

This requires capturing a real token from a browser solve. In the browser DevTools, after solving, run:
```js
document.querySelector('cap-widget').token
```
Then submit the form once (token consumed). Attempt a second submission with the same token:
```bash
curl -X POST http://localhost:4000/users/register \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user[email]=test2@example.com" \
  --data-urlencode "user[password]=somepassword1234" \
  --data-urlencode "cap-token=<the token from above>"
```
Expected: rejected (Cap deletes the token on first verification; second use fails).

- [ ] **Step 7: Run the full test suite one final time**

Run: `mix test`
Expected: all tests pass.

- [ ] **Step 8: Final commit (if any cleanup)**

```bash
git status
# If anything changed during verification, commit it.
git add -A && git commit -m "chore: cap integration verification complete"
```

---

## Self-Review

**Spec coverage check** (each spec section → task):

- Decisions table (Standalone, RSW+instrumentation, Req, env-gated, 3 endpoints, valkey naming) → Tasks 1, 2, 9, 10. ✓
- Components: `captcha.ex` → Task 2. `verify_captcha.ex` → Task 3. `cap.ex` component → Task 4. Template edits → Task 5. ✓
- Config (runtime.exs, test.exs, example.env) → Task 7. ✓
- Hosting repo (docker-compose, README, example.env) → Task 10. ✓
- Local dev docker-compose → Task 9. ✓
- Site key creation (rsw + instrumentation) → Task 11. ✓
- Testing (captcha_test, 3 controller tests) → Tasks 2, 8. ✓
- Step 7 verification (widget solves, valid passes, forged fails, single-use) → Task 11. ✓
- Security (single-use, fail-closed, secret never to browser) → encoded in Tasks 2, 3. ✓

**Placeholder scan:** No TBD/TODO/"implement later". The single `# TODO: confirm scheme+host format` from the spec is resolved in Task 10 Step 1 — `CORS_ORIGIN=https://${APP_DOMAIN}` (scheme + host, confirmed from Cap source `CORS_ORIGIN` comma-separated origin list).

**Type consistency:** `enabled?/0`, `verify/1` (`:ok | {:error, atom}`), `widget_endpoint/0` — used identically across Tasks 2, 3, 4. ✓

**One open item noted in spec (CORS_ORIGIN format):** Resolved — Cap's `CORS_ORIGIN` is a comma-separated list of origins (scheme+host). Production sets `https://${APP_DOMAIN}`. Documented in Task 10.

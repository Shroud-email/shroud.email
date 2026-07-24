defmodule Shroud.Accounts.UserNotifierTest do
  use Shroud.DataCase, async: false

  import Shroud.AccountsFixtures

  alias Shroud.Accounts.UserNotifier

  # A throwaway Swoosh adapter that mimics :mimemail.encode raising a MatchError
  # (exactly as gen_smtp does on RFC-5322-invalid addresses like "a..b@example.com").
  # Swoosh.Adapters.SMTP calls :mimemail.encode before any network I/O, so the
  # raise happens synchronously inside deliver/2 — no real SMTP server needed.
  defmodule RaisingAdapter do
    @behaviour Swoosh.Adapter

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def deliver(_email, _config) do
      raise MatchError,
        term: {:error, {1, :smtp_rfc5322_parse, [~c"syntax error before: ", ~c"'.'"]}}
    end

    @impl true
    def validate_dependency, do: :ok
  end

  setup do
    original = Application.get_env(:shroud, Shroud.Mailer, [])
    Application.put_env(:shroud, Shroud.Mailer, Keyword.put(original, :adapter, RaisingAdapter))

    on_exit(fn -> Application.put_env(:shroud, Shroud.Mailer, original) end)

    :ok
  end

  describe "deliver/4 when the mailer raises" do
    test "returns {:error, _} instead of propagating the exception" do
      user = user_fixture()

      # deliver_confirmation_instructions exercises deliver/4 internally.
      result = UserNotifier.deliver_confirmation_instructions(user, "https://example.com/confirm")

      assert match?({:error, _}, result)
    end
  end
end

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

  defmodule Behaviour do
    @moduledoc """
    Behaviour for SpamAssassin scanning. Implemented by `Stub` (no-op),
    `Client` (real spamc call, added in Task 2), and mocked by
    `Shroud.MockSpamAssassin` in tests.
    """
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

    @impl true
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

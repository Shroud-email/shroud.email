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

      # System.cmd in Elixir 1.20 does not support piping data to stdin
      # via an :input option. Write the email to a temp file and use a
      # shell redirect to feed it to spamc.
      tmp_path =
        Path.join(System.tmp_dir!(), "shroud-spamc-#{System.unique_integer([:positive])}.eml")

      case File.write(tmp_path, raw) do
        :ok ->
          try do
            # ponytail: no Elixir-level timeout on this System.cmd — Elixir 1.20's
            # System.cmd has no :timeout option. The timeout lives in spamc's own
            # socket timeout to spamd (~10-195s). If spamd hangs, this call blocks
            # until spamc exits, which can starve the :outgoing_email Oban queue
            # (concurrency 5). Upgrade path: switch to a Port with :timeout, or wrap
            # in Task.async_stream with a timeout, when the flag flips to true in prod.
            cmd = ~s(#{shell_quote(spamc_path)} < #{shell_quote(tmp_path)})

            case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
              {output, 0} ->
                case parse_x_spam_status(output) do
                  {:ok, _} = result -> result
                  :error -> {:error, :no_spam_header}
                end

              {output, _exit_code} ->
                # Non-zero exit: spamd unreachable, message rejected, etc.
                # Include a snippet of the output for prod debugging.
                {:error, {:spamc_nonzero_exit, String.slice(output, 0, 200)}}
            end
          rescue
            # `System.cmd` raises `ErlangError` when the binary is not
            # found. Treat that as a recoverable error, never a crash.
            e in [ErlangError, File.Error] ->
              {:error, {:spamc_unavailable, Exception.message(e)}}
          after
            File.rm(tmp_path)
          end

        {:error, reason} ->
          {:error, {:tmp_write_failed, reason}}
      end
    end

    # POSIX shell-escape: wrap in single quotes, escape embedded single quotes.
    # Makes the interpolated paths in the `sh -c` command injection-proof even
    # if a future config source is less trusted than operator env vars.
    defp shell_quote(s) when is_binary(s) do
      "'" <> String.replace(s, "'", "'\\''") <> "'"
    end

    @doc """
    Pure parser: extracts the `X-Spam-Status` header value from a
    SpamAssassin-annotated message. Case-insensitive on the header name.
    Returns `{:ok, value}` or `:error`.
    """
    @spec parse_x_spam_status(String.t()) :: {:ok, String.t()} | :error
    def parse_x_spam_status(output) when is_binary(output) do
      # Only scan the headers block (everything before the first blank line).
      [headers | _] = String.split(output, ~r/\r?\n\r?\n/, parts: 2)

      headers
      |> String.split(~r/\r?\n/)
      # ponytail: this scans one physical line per header. RFC 5322 folded
      # headers (continuation lines starting with whitespace) would be
      # truncated. SpamAssassin emits X-Spam-Status on a single line in
      # practice; if that ever changes, unfold by joining lines that start
      # with whitespace before matching.
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

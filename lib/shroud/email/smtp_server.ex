defmodule Shroud.Email.SmtpServer do
  # credo:disable-for-this-file Credo.Check.Readability.FunctionNames
  @behaviour :gen_smtp_server_session

  alias Shroud.Email.EmailHandler

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start(options) do
    :gen_smtp_server.start(
      __MODULE__,
      [[], [{:allow_bare_newlines, :ignore}, options]]
    )
  end

  def init(hostname, _session_count, _address, options) do
    banner = ["#{hostname} SMTP shroud server"]
    {:ok, banner, options}
  end

  def handle_HELO(_hostname, state) do
    {:ok, state}
  end

  def handle_EHLO(_hostname, extensions, state) do
    {:ok, extensions, state}
  end

  def handle_MAIL(_from, state) do
    {:ok, state}
  end

  def handle_MAIL_extension(_extension, state) do
    {:ok, state}
  end

  def handle_RCPT(_to, state) do
    {:ok, state}
  end

  def handle_RCPT_extension(_to, state) do
    {:ok, state}
  end

  def handle_DATA(from, to, data, state) do
    %{from: from, to: hd(to), data: data}
    |> EmailHandler.new()
    |> Oban.insert()

    {:ok, "1", state}
  end

  def handle_RSET(state) do
    state
  end

  def handle_VRFY(_address, state) do
    {:ok, "252 VRFY disabled by policy, just send some mail", state}
  end

  def handle_other(verb, _args, state) do
    {["500 Error: command not recognized : '", verb, "'"], state}
  end

  def handle_AUTH(_type, _username, _password, state) do
    {:ok, state}
  end

  def handle_STARTTLS(state) do
    state
  end

  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  def terminate(reason, state) do
    {:ok, reason, state}
  end
end

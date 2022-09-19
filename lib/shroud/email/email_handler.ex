defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email, max_attempts: 100

  require Logger
  alias Shroud.Accounts

  alias Shroud.Email.{
    BounceHandler,
    ReplyAddress,
    IncomingEmailHandler,
    OutgoingEmailHandler
  }

  import Shroud.Accounts.Logging, only: [maybe_log: 2]

  @type mimemail_email :: :mimemail.mimetuple()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}})
      when from in ["", nil] do
    BounceHandler.handle_haraka_bounce_report(to, data)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}})
      when byte_size(data) > 26_214_400 do
    # when the email is too big, cancel

    if is_list(to) do
      Enum.each(to, fn recipient ->
        user = Accounts.get_user_by_alias(recipient)
        maybe_log(user, "Dropping email from #{from} to #{recipient} because it's above 25MB")
      end)
    else
      user = Accounts.get_user_by_alias(to)
      maybe_log(user, "Dropping email from #{from} to #{to} because it's above 25MB")
    end

    # silently drop the email. can probably handle this better but not worth it for now.
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => recipients, "data" => data}})
      when is_list(recipients) do
    # TODO: handle parsing failures from mimemail?
    email = :mimemail.decode(data)

    recipients
    |> Enum.each(&handle_recipient(from, &1, email))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}}) do
    email = :mimemail.decode(data)
    handle_recipient(from, to, email)
  end

  @spec handle_recipient(String.t(), String.t(), mimemail_email) :: :ok | {:error, term()}
  defp handle_recipient(sender, recipient, mimemail_email) do
    if ReplyAddress.is_reply_address?(recipient) do
      OutgoingEmailHandler.handle_outgoing_email(sender, recipient, mimemail_email)
    else
      IncomingEmailHandler.handle_incoming_email(sender, recipient, mimemail_email)
    end
  end
end

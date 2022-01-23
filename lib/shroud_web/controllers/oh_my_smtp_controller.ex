defmodule ShroudWeb.OhMySmtpController do
  use ShroudWeb, :controller
  alias Shroud.Notifier
  require Logger

  def webhook(conn, %{"event" => event, "payload" => payload}) do
    case event do
      "email.spam" ->
        %{"from" => from, "to" => to} = payload
        Logger.error("Email from #{from} to #{to} marked as spam by OhMySMTP")
        Notifier.notify_outgoing_email_marked_as_spam(from, to)

      "email.bounced" ->
        %{"from" => from, "to" => to} = payload
        Logger.error("Email from #{from} to #{to} hard bounced. Failed to forward!")
        Notifier.notify_outgoing_email_bounced(from, to)

      _other ->
        nil
        # do nothing
    end

    send_resp(conn, 200, "")
  end
end

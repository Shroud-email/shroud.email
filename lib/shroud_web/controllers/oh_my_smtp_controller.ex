defmodule ShroudWeb.OhMySmtpController do
  use ShroudWeb, :controller
  alias Shroud.Notifier

  def webhook(conn, %{"event" => event, "payload" => payload}) do
    case event do
      "email.spam" ->
        Notifier.notify_outgoing_email_marked_as_spam(payload["from"], payload["to"])

      "email.bounced" ->
        Notifier.notify_outgoing_email_bounced(payload["from"], payload["to"])

      _other ->
        nil
        # do nothing
    end

    send_resp(conn, 200, "")
  end
end

defmodule ShroudWeb.OhMySmtpController do
  use ShroudWeb, :controller
  alias Shroud.Notifier

  def webhook(conn, %{"event" => "email.spam", "payload" => payload}) do
    Notifier.notify_outgoing_email_marked_as_spam(payload["from"], payload["to"])
    send_resp(conn, 200, "")
  end
end

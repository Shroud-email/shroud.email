defmodule ShroudWeb.SpamCount do
  import Plug.Conn

  alias Shroud.Email

  def fetch_spam_count(conn, _opts) do
    current_user = conn.assigns.current_user

    if current_user do
      spam_count = Email.count_spam_emails(current_user)
      assign(conn, :spam_count, spam_count)
    else
      assign(conn, :spam_count, nil)
    end
  end
end

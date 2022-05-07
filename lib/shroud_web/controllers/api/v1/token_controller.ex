defmodule ShroudWeb.Api.V1.TokenController do
  use ShroudWeb, :controller
  alias Shroud.Accounts

  def create(conn, %{"email" => email, "password" => password} = params) do
    if user = get_user(email, password, params["totp"]) do
      token = Accounts.generate_user_session_token(user)
      render(conn, "token.json", token: Base.encode64(token))
    else
      conn
      |> put_status(403)
      |> put_view(ShroudWeb.ErrorView)
      |> render("error.json", error: "Invalid email, password or TOTP code")
    end
  end

  defp get_user(email, password, totp) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      if user.totp_enabled do
        totp = if is_nil(totp), do: "", else: Integer.to_string(totp)

        if Accounts.TOTP.valid_code?(user, user.totp_secret, totp) do
          user
        else
          nil
        end
      else
        user
      end
    else
      nil
    end
  end
end

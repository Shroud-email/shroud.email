defmodule ShroudWeb.UserConfirmationController do
  use ShroudWeb, :controller

  alias Shroud.Accounts

  def new(conn, _params) do
    render(conn, "new.html", page_title: "Confirm")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &Routes.user_confirmation_url(conn, :edit, &1)
      )
    end

    # In order to prevent user enumeration attacks, regardless of the outcome, show an impartial success/error message.
    conn
    |> put_flash(
      :info,
      "If your email is in our system and it has not been confirmed yet, " <>
        "you will receive an email with instructions shortly."
    )
    |> redirect(to: Routes.user_confirmation_path(conn, :new))
  end

  def edit(conn, %{"token" => token}) do
    render(conn, "edit.html", token: token, page_title: "Confirm")
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def update(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Account confirmed successfully.")
        |> redirect(to: "/")

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            redirect(conn, to: "/")

          %{} ->
            conn
            |> put_flash(:error, "User confirmation link is invalid or it has expired.")
            |> redirect(to: "/")
        end
    end
  end
end

defmodule ShroudWeb.UserRegistrationController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias ShroudWeb.UserAuth

  plug ShroudWeb.Plugs.VerifyCaptcha when action in [:create]

  def new(conn, params) do
    lifetime = params["lifetime"] == "true"
    changeset = Accounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset, page_title: "Sign up", lifetime: lifetime)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        case Accounts.deliver_user_confirmation_instructions(
               user,
               &url(~p"/users/confirm/#{&1}")
             ) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "User created successfully.")
            |> UserAuth.log_in_user(user)

          {:error, _reason} ->
            # The account was created, but we could not send the confirmation
            # email. Don't fail the registration over it; the user can request
            # a new confirmation link from the login page.
            conn
            |> put_flash(
              :warning,
              "Your account was created, but we couldn't send your " <>
                "confirmation email. You can request a new one from the login page."
            )
            |> UserAuth.log_in_user(user)
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          changeset: changeset,
          lifetime: user_params["status"] == "lifetime"
        )

      nil ->
        render(conn, "new.html",
          changeset: User.registration_changeset(%User{}, %{}),
          lifetime: user_params["status"] == "lifetime"
        )
    end
  end
end

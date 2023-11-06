defmodule ShroudWeb.UserRegistrationController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias ShroudWeb.UserAuth
  alias ShroudWeb.Router.Helpers, as: Routes

  def new(conn, params) do
    lifetime = params["lifetime"] == "true"
    changeset = Accounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset, page_title: "Sign up", lifetime: lifetime)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :edit, &1)
          )

        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)

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

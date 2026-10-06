defmodule ShroudWeb.UserRegistrationController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias ShroudWeb.UserAuth

  plug ShroudWeb.Plugs.VerifyCaptcha when action in [:create]

  def new(conn, params) do
    lifetime = params["lifetime"] == "true"

    changeset = Accounts.change_user_registration(%User{})

    render(conn, "new.html",
      changeset: changeset,
      page_title: "Sign up",
      lifetime: lifetime,
      campaign: Map.filter(conn.query_params, fn {_key, value} -> is_binary(value) end)
    )
  end

  def create(conn, %{"user" => user_params}) do
    campaign =
      case user_params["signup_campaign"] do
        params when is_map(params) -> Map.filter(params, fn {_key, value} -> is_binary(value) end)
        _ -> %{}
      end

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Shroud.Analytics.signup(user.id, ~p"/users/register?#{campaign}")

        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        UserAuth.log_in_user(conn, user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          changeset: changeset,
          campaign: campaign,
          lifetime: user_params["status"] == "lifetime"
        )

      nil ->
        render(conn, "new.html",
          changeset: User.registration_changeset(%User{}, %{}),
          campaign: campaign,
          lifetime: user_params["status"] == "lifetime"
        )
    end
  end
end

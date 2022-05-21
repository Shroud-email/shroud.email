defmodule Shroud.Billing do
  alias Shroud.Repo
  alias Shroud.Accounts.User
  alias Shroud.Billing.LifetimeCode
  alias Ecto.Multi
  require Logger

  @salt "lifetime_code"

  def create_lifetime_code() do
    data = :crypto.strong_rand_bytes(16) |> Base.encode64() |> String.slice(0, 16)
    # max_age is 50 years
    Phoenix.Token.sign(ShroudWeb.Endpoint, @salt, data, max_age: 1_577_880_000)
    |> Base.encode64(padding: false)
  end

  @spec redeem_lifetime_code(String.t(), User) ::
          :ok | {:error, :invalid_code} | {:error, :already_redeemed}
  def redeem_lifetime_code(code, %User{} = user) do
    cond do
      not valid_code?(code) ->
        {:error, :invalid_code}

      not unused_code?(code) ->
        {:error, :already_redeemed}

      true ->
        Multi.new()
        |> Multi.insert(
          :lifetime_code,
          LifetimeCode.changeset(%LifetimeCode{}, %{code: code, redeemed_by_id: user.id})
        )
        |> Multi.update(
          :user,
          User.status_changeset(user, %{status: :lifetime, trial_expires_at: nil})
        )
        |> Repo.transaction()

        Logger.info("#{user.email} redeemed a lifetime code!")

        :ok
    end
  end

  defp valid_code?(base64_code) do
    with {:ok, code} <- Base.decode64(base64_code, padding: false),
         {:ok, _data} <- Phoenix.Token.verify(ShroudWeb.Endpoint, @salt, code) do
      true
    else
      _error -> false
    end
  end

  defp unused_code?(code) do
    case Repo.get_by(LifetimeCode, code: code) do
      nil -> true
      _other -> false
    end
  end
end

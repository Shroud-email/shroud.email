defmodule Shroud.Billing do
  import Ecto.Query
  alias Ecto.Multi
  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias Shroud.Billing.LifetimeCode
  alias Shroud.Repo
  require Logger

  @salt "lifetime_code"

  @doc "Records each completed Paddle transaction once before best-effort revenue tracking."
  def record_paddle_revenue(user_id, transaction_id, amount, currency, occurred_at) do
    case Repo.insert_all(
           "tracked_paddle_revenue",
           [%{transaction_id: transaction_id}],
           on_conflict: :nothing,
           conflict_target: [:transaction_id]
         ) do
      {1, _} -> Shroud.Analytics.revenue(user_id, amount, currency, occurred_at)
      {0, _} -> :ok
    end
  end

  def create_lifetime_code() do
    data = :crypto.strong_rand_bytes(16) |> Base.encode64() |> String.slice(0, 16)
    # max_age is 50 years
    Phoenix.Token.sign(ShroudWeb.Endpoint, @salt, data, max_age: 1_577_880_000)
    |> Base.encode64(padding: false)
  end

  @spec redeem_lifetime_code(String.t(), User) ::
          :ok
          | {:error, :invalid_code}
          | {:error, :already_redeemed}
          | {:error, :redemption_failed}
  def redeem_lifetime_code(code, %User{} = user) do
    cond do
      not valid_code?(code) ->
        {:error, :invalid_code}

      not unused_code?(code) ->
        {:error, :already_redeemed}

      true ->
        result =
          Multi.new()
          |> Multi.run(:locked_user, fn repo, _changes ->
            {:ok, repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")}
          end)
          |> Multi.insert(
            :lifetime_code,
            LifetimeCode.changeset(%LifetimeCode{}, %{code: code, redeemed_by_id: user.id})
          )
          |> Multi.update(:user, fn %{locked_user: locked_user} ->
            lifetime_changeset(locked_user)
          end)
          |> Multi.run(:loops_job, fn _repo, %{user: updated_user} ->
            Accounts.enqueue_loops_sync(updated_user)
          end)
          |> Repo.transaction()

        case result do
          {:ok, %{locked_user: prior_user, user: updated_user}} ->
            if is_nil(prior_user.paid_converted_at) and not is_nil(updated_user.paid_converted_at) do
              Shroud.Analytics.paid_conversion(
                user.id,
                updated_user.paid_converted_at,
                :lifetime_code
              )
            end

            Logger.notice("#{user.email} redeemed a lifetime code!")
            :ok

          {:error, _failed_operation, _failed_value, _changes_so_far} ->
            {:error, :redemption_failed}
        end
    end
  end

  defp lifetime_changeset(user) do
    changeset = User.status_changeset(user, %{status: :lifetime})

    if is_nil(user.paid_converted_at) and user.status != :lifetime do
      Ecto.Changeset.put_change(changeset, :paid_converted_at, DateTime.utc_now())
    else
      changeset
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

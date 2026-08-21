defmodule Shroud.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Shroud.Accounts.{LoopsJob, User, UserNotifier, UserNotifierJob, UserToken}
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Notifier
  alias Shroud.Repo

  require Logger

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @spec get_user_by_alias(String.t()) :: User.t() | nil
  def get_user_by_alias(address) when is_binary(address) do
    query =
      from u in User,
        join: e in EmailAlias,
        on: e.user_id == u.id,
        where: e.address == ^address and is_nil(e.deleted_at)

    Repo.one(query)
  end

  def get_user_by_paddle_customer_id(paddle_customer_id)
      when is_binary(paddle_customer_id) do
    Repo.get_by(User, paddle_customer_id: paddle_customer_id)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    if Application.fetch_env!(:shroud, :disable_signups) not in [true, "true", "1", "yes"] do
      case %User{}
           |> User.registration_changeset(attrs)
           |> Repo.insert(returning: true) do
        {:ok, user} ->
          Notifier.notify_user_signed_up_free(user.email)
          Logger.notice("User #{user.email} signed up (free tier)")
          {:ok, user}

        other ->
          other
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset = user |> User.email_changeset(%{email: email}) |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  @doc """
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_update_email_instructions(user, current_email, &url(~p"/settings/confirm_email/\#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc """
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/\#{&1}"))
      {:ok, %Oban.Job{}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/\#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      job =
        %{
          email_function: "deliver_confirmation_instructions",
          email_args: [user.id, confirmation_url_fun.(encoded_token)]
        }
        |> UserNotifierJob.new()
        |> Oban.insert!()

      {:ok, job}
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      case Application.fetch_env(:shroud, :loops_active_users_list_id) do
        {:ok, active_users_list_id} ->
          %{
            user_id: user.id,
            event_name: "user_confirmed",
            event_properties: %{},
            mailing_lists: %{
              active_users_list_id => true
            }
          }
          |> LoopsJob.new()
          |> Oban.insert!()

        _ ->
          Logger.debug("Loops active list not configured")
          nil
      end

      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    # Don't overwrite lifetime status
    status = if user.status == :lifetime, do: :lifetime, else: :free

    attrs = %{
      status: status
    }

    Logger.info("Confirming user #{user.email} with status #{status}")

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/\#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def update_user_theme(user, attrs) do
    user
    |> User.theme_changeset(attrs)
    |> Repo.update()
  end

  def update_paddle_details!(user, attrs \\ %{}) do
    user
    |> User.paddle_changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Reuses or creates one pending Paddle checkout transaction per user and price.

  The row lock intentionally spans transaction creation so concurrent browser
  requests cannot create multiple recurring checkouts before a webhook arrives.
  """
  def get_or_create_paddle_checkout_transaction(
        user_id,
        price_id,
        create_transaction,
        get_transaction
      )
      when is_integer(user_id) and is_binary(price_id) and is_function(create_transaction, 1) and
             is_function(get_transaction, 1) do
    Repo.transaction(fn ->
      user = Repo.one(from user in User, where: user.id == ^user_id, lock: "FOR UPDATE")

      get_or_create_locked_paddle_checkout(
        user,
        price_id,
        create_transaction,
        get_transaction
      )
    end)
    |> case do
      {:ok, transaction} -> {:ok, transaction}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_locked_paddle_checkout(
         nil,
         _price_id,
         _create_transaction,
         _get_transaction
       ),
       do: Repo.rollback(:unknown_user)

  defp get_or_create_locked_paddle_checkout(
         %User{} = user,
         price_id,
         create_transaction,
         get_transaction
       ) do
    cond do
      paid?(user) ->
        Repo.rollback(:subscription_exists)

      pending_paddle_checkout?(user) ->
        reconcile_pending_paddle_checkout(user, price_id, create_transaction, get_transaction)

      true ->
        create_and_store_paddle_checkout(user, price_id, create_transaction)
    end
  end

  defp pending_paddle_checkout?(user), do: is_binary(user.paddle_checkout_transaction_id)

  defp reconcile_pending_paddle_checkout(user, price_id, create_transaction, get_transaction) do
    case get_transaction.(user.paddle_checkout_transaction_id) do
      {:ok, %{status: status}} when status in ["draft", "ready"] ->
        %{id: user.paddle_checkout_transaction_id}

      {:ok, %{status: "canceled"}} ->
        create_and_store_paddle_checkout(user, price_id, create_transaction)

      {:ok, %{status: _status}} ->
        Repo.rollback(:checkout_already_processed)

      {:error, reason} ->
        Repo.rollback(reason)

      _invalid_response ->
        Repo.rollback(:invalid_checkout_transaction)
    end
  end

  defp create_and_store_paddle_checkout(user, price_id, create_transaction) do
    case create_transaction.(user) do
      {:ok, %{id: transaction_id} = transaction} when is_binary(transaction_id) ->
        user
        |> User.paddle_changeset(%{
          paddle_checkout_transaction_id: transaction_id,
          paddle_checkout_price_id: price_id
        })
        |> Repo.update!()

        transaction

      {:error, reason} ->
        Repo.rollback(reason)

      _invalid_response ->
        Repo.rollback(:invalid_checkout_transaction)
    end
  end

  @doc """
  Applies a Paddle subscription event while holding a row lock.

  The customer lookup, checkout-identity fallback, ordering check, update, and
  paid-signup notification share one transaction so concurrent deliveries
  cannot regress subscription state or enqueue duplicate transition notices.
  """
  def apply_paddle_subscription_event(%{
        customer_id: customer_id,
        identity_user_id: identity_user_id,
        subscription_id: subscription_id,
        price_id: price_id,
        status: status,
        plan_expires_at: plan_expires_at,
        event_at: event_at
      }) do
    Repo.transaction(fn ->
      user = lock_paddle_user(customer_id, identity_user_id)

      attrs = %{
        paddle_customer_id: customer_id,
        paddle_subscription_id: subscription_id,
        paddle_price_id: price_id,
        plan_expires_at: plan_expires_at,
        status: status,
        last_paddle_event_at: event_at
      }

      case paddle_subscription_relationship(user, subscription_id, price_id, status) do
        :current -> apply_locked_paddle_event(user, attrs)
        :new -> apply_locked_paddle_event(user, clear_pending_paddle_checkout(attrs))
        :unrelated -> :unrelated_subscription
        :price_conflict -> Repo.rollback(:subscription_price_conflict)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_locked_paddle_event(user, %{last_paddle_event_at: event_at} = attrs) do
    if stale_paddle_event?(event_at, user.last_paddle_event_at) do
      :stale
    else
      update_paddle_subscription(user, attrs)
    end
  end

  defp update_paddle_subscription(user, %{status: status} = attrs) do
    case user |> User.paddle_changeset(attrs) |> Repo.update() do
      {:ok, updated_user} ->
        maybe_notify_paid_signup(updated_user, user.status, status)
        :applied

      {:error, changeset} ->
        Repo.rollback({:invalid_paddle_update, changeset.errors})
    end
  end

  defp maybe_notify_paid_signup(user, prior_status, :active) when prior_status != :active do
    Notifier.notify_user_signed_up(user.email)
  end

  defp maybe_notify_paid_signup(_user, _prior_status, _status), do: :ok

  defp lock_paddle_user(customer_id, identity_user_id) do
    customer_user =
      Repo.one(
        from user in User,
          where: user.paddle_customer_id == ^customer_id,
          lock: "FOR UPDATE"
      )

    case {customer_user, identity_user_id} do
      {%User{id: user_id} = user, user_id} ->
        user

      {%User{}, _identity_user_id} ->
        Repo.rollback(:checkout_identity_conflict)

      {nil, user_id} when is_integer(user_id) ->
        user =
          Repo.one(
            from user in User,
              where: user.id == ^user_id,
              lock: "FOR UPDATE"
          )

        ensure_customer_can_be_bound(user, customer_id)

      {nil, _identity_user_id} ->
        Repo.rollback(:unknown_customer)
    end
  end

  defp ensure_customer_can_be_bound(nil, _customer_id), do: Repo.rollback(:unknown_customer)

  defp ensure_customer_can_be_bound(%User{paddle_customer_id: nil} = user, _customer_id),
    do: user

  defp ensure_customer_can_be_bound(%User{paddle_customer_id: customer_id} = user, customer_id),
    do: user

  defp ensure_customer_can_be_bound(%User{}, _customer_id),
    do: Repo.rollback(:customer_conflict)

  defp paddle_subscription_relationship(
         %User{paddle_subscription_id: nil},
         _subscription_id,
         _price_id,
         _status
       ),
       do: :new

  defp paddle_subscription_relationship(
         %User{paddle_subscription_id: subscription_id, paddle_price_id: price_id},
         subscription_id,
         price_id,
         _status
       ),
       do: :current

  defp paddle_subscription_relationship(
         %User{paddle_subscription_id: subscription_id},
         subscription_id,
         _price_id,
         _status
       ),
       do: :price_conflict

  defp paddle_subscription_relationship(
         %User{status: :free},
         _subscription_id,
         _price_id,
         :active
       ),
       do: :new

  defp paddle_subscription_relationship(_user, _subscription_id, _price_id, _status),
    do: :unrelated

  defp clear_pending_paddle_checkout(attrs) do
    Map.merge(attrs, %{
      paddle_checkout_transaction_id: nil,
      paddle_checkout_price_id: nil
    })
  end

  defp stale_paddle_event?(incoming, last) when not is_nil(last), do: incoming <= last
  defp stale_paddle_event?(_incoming, nil), do: false

  def active?(%User{} = user) do
    user.status in [:active, :lifetime, :free]
  end

  def paid?(%User{} = user) do
    user.status in [:active, :lifetime]
  end

  def admin?(%User{} = user) do
    user.is_admin
  end
end

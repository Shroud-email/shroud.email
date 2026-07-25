defmodule Shroud.Accounts.UserNotifierJob do
  @moduledoc """
  Oban worker that sends transactional emails asynchronously.
  """
  use Oban.Worker, queue: :outgoing_email, max_attempts: 10

  alias Shroud.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_function" => email_function, "email_args" => email_args}}) do
    case email_function do
      "deliver_confirmation_instructions" ->
        apply(UserNotifier, :deliver_confirmation_instructions, email_args)

      "deliver_domain_verified" ->
        apply(UserNotifier, :deliver_domain_verified, email_args)

      "deliver_domain_no_longer_verified" ->
        apply(UserNotifier, :deliver_domain_no_longer_verified, email_args)

      "deliver_incoming_email_marked_as_spam" ->
        apply(UserNotifier, :deliver_incoming_email_marked_as_spam, email_args)

      "deliver_outgoing_email_marked_as_spam" ->
        apply(UserNotifier, :deliver_outgoing_email_marked_as_spam, email_args)

      "deliver_reset_password_instructions" ->
        apply(UserNotifier, :deliver_reset_password_instructions, email_args)

      "deliver_update_email_instructions" ->
        apply(UserNotifier, :deliver_update_email_instructions, email_args)

      other ->
        {:error, {:unknown_email_function, other}}
    end
  end
end

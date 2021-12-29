defmodule Shroud.Accounts.UserNotifierJob do
  use Oban.Worker, queue: :outgoing_email, max_attempts: 10
  alias Shroud.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_function" => email_function, "email_args" => email_args}}) do
    email_function = String.to_existing_atom(email_function)
    apply(Accounts.UserNotifier, email_function, email_args)
  end
end

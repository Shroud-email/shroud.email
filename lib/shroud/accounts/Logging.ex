defmodule Shroud.Accounts.Logging do
  alias Shroud.Accounts.User

  @logging_flag :logging
  @logging_flag_email_data :email_data_logging

  @spec logging_enabled?(User.t() | nil) :: boolean()
  def logging_enabled?(nil), do: false

  def logging_enabled?(%User{} = user) do
    FunWithFlags.enabled?(@logging_flag, for: user)
  end

  @spec email_logging_enabled?(User.t() | nil) :: boolean()
  def email_logging_enabled?(nil), do: false

  def email_logging_enabled?(%User{} = user) do
    FunWithFlags.enabled?(@logging_flag_email_data, for: user)
  end

  @spec any_logging_enabled?(User.t() | nil) :: boolean()
  def any_logging_enabled?(nil), do: false

  def any_logging_enabled?(%User{} = user) do
    logging_enabled?(user) || email_logging_enabled?(user)
  end
end

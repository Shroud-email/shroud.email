defmodule Shroud.Accounts.Logging do
  alias Shroud.Accounts.User
  alias Shroud.S3.S3UploadJob
  require Logger

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

  def maybe_log(nil, _text), do: :ok

  def maybe_log(%User{} = user, text) do
    if logging_enabled?(user) do
      Logger.notice(text)
    end
  end

  @spec store_email(String.t(), String.t(), String.t()) :: :ok
  def store_email(sender, recipient, data) do
    date_time = Application.get_env(:shroud, :datetime_module, Shroud.DateTime)
    s3_path = "/emails/#{sender}-#{recipient}-#{date_time.utc_now_unix()}.eml"

    # Base64 encode the email data to safely store as JSONB in Oban.
    # Raw email data can contain non-UTF-8 bytes which break JSON encoding.
    encoded_data = Base.encode64(data)

    %{path: s3_path, content: encoded_data}
    |> S3UploadJob.new()
    |> Oban.insert!()

    Logger.notice("Storing email from #{sender} to #{recipient} to #{s3_path}")
  end
end

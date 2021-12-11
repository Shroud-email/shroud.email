defmodule Shroud.Accounts.TOTP do
  alias Shroud.Accounts.User
  alias Shroud.Repo

  @spec create_secret() :: binary()
  def create_secret() do
    NimbleTOTP.secret()
  end

  @spec otp_uri(User.t(), String.t()) :: String.t()
  def otp_uri(user, secret) do
    label = "Shroud.email:#{user.email}"
    NimbleTOTP.otpauth_uri(label, secret)
  end

  @spec enable_totp!(User.t(), String.t()) :: User.t()
  def enable_totp!(user, secret) do
    user
    |> User.totp_changeset(%{totp_secret: secret})
    |> Repo.update!()
  end

  @spec disable_totp!(User.t()) :: User.t()
  def disable_totp!(user) do
    user
    |> User.totp_changeset(%{totp_secret: nil})
    |> Repo.update!()
  end

  @doc """
  Returns true if the given OTP is valid. Includes a grace period, so the
  previous code will also work for an additional 30 seconds.
  """
  @spec valid_code?(String.t(), String.t()) :: boolean()
  def valid_code?(secret, otp) do
    time = System.os_time(:second)
    NimbleTOTP.valid?(secret, otp, time: time) or NimbleTOTP.valid?(secret, otp, time: time - 30)
  end
end

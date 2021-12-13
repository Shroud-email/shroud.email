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

  @spec enable_totp!(User.t(), String.t()) :: [String.t()]
  def enable_totp!(user, secret) do
    backup_codes = Enum.to_list(generate_backup_codes())

    user
    |> User.totp_changeset(%{
      totp_secret: secret,
      totp_backup_codes: backup_codes,
      totp_enabled: true
    })
    |> Repo.update!()

    backup_codes
  end

  @spec disable_totp!(User.t()) :: User.t()
  def disable_totp!(user) do
    user
    |> User.totp_changeset(%{totp_enabled: false})
    |> Repo.update!()
  end

  @doc """
  Returns true if the given OTP is valid. Includes a grace period, so the
  previous code will also work for an additional 30 seconds.

  If a backup code is given, consume it from the list of backup codes.
  """
  @spec valid_code?(User.t(), binary, String.t()) :: boolean()
  def valid_code?(user, secret, otp) do
    time = System.os_time(:second)

    cond do
      # Check TOTP code for this 30-second interval
      NimbleTOTP.valid?(secret, otp, time: time) ->
        true

      # Check TOTP code for *previous* 30-second interval
      NimbleTOTP.valid?(secret, otp, time: time - 30) ->
        true

      # Check backup codes, and if found, remove
      Enum.any?(user.totp_backup_codes, &Plug.Crypto.secure_compare(&1, otp)) ->
        updated_backup_codes =
          Enum.filter(user.totp_backup_codes, fn backup_code -> otp != backup_code end)

        user
        |> User.totp_changeset(%{totp_secret: secret, totp_backup_codes: updated_backup_codes})
        |> Repo.update!()

      # Code is not valid
      true ->
        false
    end
  end

  @spec generate_backup_codes() :: [String.t()]
  defp generate_backup_codes() do
    _ = :crypto.rand_seed()
    alphabet = Enum.into(0..9, [], &Integer.to_string/1)

    Enum.map(1..8, fn _index ->
      1..8
      |> Enum.map(fn _ -> Enum.at(alphabet, :rand.uniform(10) - 1) end)
      |> Enum.join("")
    end)
  end
end

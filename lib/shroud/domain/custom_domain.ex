defmodule Shroud.Domain.CustomDomain do
  use Ecto.Schema
  import Ecto.Changeset

  schema "custom_domains" do
    field :catchall_enabled, :boolean, default: false
    field :dkim_verified_at, :naive_datetime
    field :dmarc_verified_at, :naive_datetime
    field :domain, :string
    field :mx_verified_at, :naive_datetime
    field :spf_verified_at, :naive_datetime
    field :verification_code, :string
    field :ownership_verified_at, :naive_datetime
    belongs_to :user, Shroud.Accounts.User

    timestamps()
  end

  @doc false
  def create_changeset(custom_domain, attrs) do
    custom_domain
    |> cast(attrs, [:verification_code, :domain])
    |> validate_required([:verification_code, :domain])
    |> unique_constraint(:domain, message: "already in use")
    |> validate_format(:domain, ~r/^((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,}$/,
      message: "must be a domain, e.g. example.com"
    )
    |> validate_exclusion(:domain, [System.get_env("EMAIL_DOMAIN"), System.get_env("APP_DOMAIN")])
  end

  def update_changeset(custom_domain, attrs) do
    custom_domain
    |> cast(attrs, [:catchall_enabled])
    |> validate_required([:catchall_enabled])
  end
end

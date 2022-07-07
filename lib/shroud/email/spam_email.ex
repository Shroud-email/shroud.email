defmodule Shroud.Email.SpamEmail do
  use Ecto.Schema
  import Ecto.Changeset
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Accounts.User

  schema "spam_emails" do
    field :from, :string
    field :html_body, :string
    field :subject, :string
    field :text_body, :string

    belongs_to :email_alias, EmailAlias
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(spam_email, attrs) do
    spam_email
    |> cast(attrs, [:from, :subject, :html_body, :text_body, :user_id, :email_alias_id])
    |> validate_required([:from, :user_id, :email_alias_id])
  end
end

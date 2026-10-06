defmodule Shroud.Inboxes.Message do
  use Ecto.Schema

  schema "inbox_messages" do
    belongs_to :email_alias, Shroud.Aliases.EmailAlias
    field :storage_key, :string
    field :delivery_id, :string
    field :sender, :string
    field :subject, :string
    field :size, :integer
    field :stored, :boolean, default: false
    field :read, :boolean, default: false
    field :spam, :boolean, default: false
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

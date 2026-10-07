defmodule Shroud.Email.UnsubscribeRelay do
  use Ecto.Schema

  schema "email_unsubscribe_relays" do
    field :token_hash, :binary, redact: true
    field :recipe, Shroud.Encrypted.Binary, redact: true
    field :generation, :integer
    belongs_to :alias, Shroud.Aliases.EmailAlias

    timestamps(updated_at: false)
  end
end

defmodule Shroud.Encrypted.StringList do
  use Cloak.Ecto.StringList, vault: Shroud.Vault
end

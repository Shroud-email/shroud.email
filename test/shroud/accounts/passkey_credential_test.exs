defmodule Shroud.Accounts.PasskeyCredentialTest do
  use Shroud.DataCase

  alias Shroud.{Accounts, Repo}
  alias Shroud.Accounts.PasskeyCredential
  import Shroud.AccountsFixtures

  test "users get distinct opaque handles that survive reload" do
    first = user_fixture()
    second = user_fixture()

    assert byte_size(first.passkey_handle) == 32
    assert first.passkey_handle != second.passkey_handle
    assert Repo.reload!(first).passkey_handle == first.passkey_handle
  end

  test "a user can own multiple unique credentials but cannot remove another user's" do
    first = user_fixture()
    second = user_fixture()
    id = :crypto.strong_rand_bytes(32)

    assert {:ok, key} =
             %PasskeyCredential{
               user_id: first.id,
               credential_id: id,
               public_key: <<1>>,
               label: "Laptop"
             }
             |> Repo.insert()

    assert {:ok, _} =
             %PasskeyCredential{
               user_id: first.id,
               credential_id: :crypto.strong_rand_bytes(32),
               public_key: <<2>>,
               label: "Phone"
             }
             |> Repo.insert()

    assert length(Accounts.list_passkeys(first)) == 2
    assert Accounts.get_passkey(id).user_id == first.id
    assert {:error, :not_found} = Accounts.remove_passkey(second, id)
    assert Accounts.get_passkey(id)
    assert :ok = Accounts.remove_passkey(first, id)
    assert Accounts.get_passkey(id) == nil
    assert {:error, :not_found} = Accounts.remove_passkey(first, id)
    assert key.credential_id == id
  end

  test "credential IDs cannot be registered to two accounts" do
    id = :crypto.strong_rand_bytes(32)
    first = user_fixture()
    second = user_fixture()

    assert {:ok, _} =
             %PasskeyCredential{user_id: first.id}
             |> PasskeyCredential.changeset(%{credential_id: id, public_key: <<1>>})
             |> Repo.insert()

    assert {:error, _} =
             %PasskeyCredential{user_id: second.id}
             |> PasskeyCredential.changeset(%{credential_id: id, public_key: <<2>>})
             |> Repo.insert()
  end

  test "credential changesets reject missing ownership and a nil counter" do
    attrs = %{credential_id: :crypto.strong_rand_bytes(32), public_key: <<1>>}
    missing_owner = PasskeyCredential.changeset(%PasskeyCredential{}, attrs)
    refute missing_owner.valid?
    assert Keyword.has_key?(missing_owner.errors, :user_id)

    nil_counter =
      PasskeyCredential.changeset(
        %PasskeyCredential{user_id: user_fixture().id},
        Map.put(attrs, :sign_count, nil)
      )

    refute nil_counter.valid?
    assert Keyword.has_key?(nil_counter.errors, :sign_count)
  end
end

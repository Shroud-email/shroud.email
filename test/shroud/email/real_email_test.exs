defmodule Shroud.Email.RealEmailTests do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  import Shroud.{AccountsFixtures, AliasesFixtures}
  import Swoosh.TestAssertions

  alias Shroud.Email.EmailHandler

  @files [
    "test/support/data/real/simple.eml",
    "test/support/data/real/integrityinstitute.eml"
  ]

  setup do
    user = user_fixture(%{email: "recipient@example.com"})
    email_alias = alias_fixture(%{user_id: user.id, address: "alias@example.com"})
    %{user: user, email_alias: email_alias}
  end

  test "forward real emails", %{user: user, email_alias: email_alias} do
    FunWithFlags.enable(:email_data_logging, for_actor: user)

    @files
    |> Enum.each(fn path ->
      data = File.read!(path)

      perform_job(EmailHandler, %{
        from: "sender@example.com",
        to: email_alias.address,
        data: data
      })

      assert_email_sent(fn email ->
        [{_to_name, to_address}] = email.to
        assert to_address == user.email

        {_from_name, from_address} = email.from
        assert from_address == "sender_at_example.com_alias@example.com"
      end)
    end)
  end
end

defmodule Shroud.InboxesTest do
  use Shroud.DataCase
  import Mox
  import Shroud.AccountsFixtures
  import Shroud.AliasesFixtures
  import Shroud.InboxesFixtures
  alias Shroud.{Aliases, Inboxes, Repo, Vault}
  alias Shroud.Email.{EmailHandler, IncomingEmailHandler, OutgoingEmailHandler, ReplyAddress}
  alias Shroud.Inboxes.Message
  alias Shroud.S3.MockS3Client

  setup :verify_on_exit!

  setup do
    user = user_fixture()
    inbox = alias_fixture(%{user_id: user.id, delivery_mode: :inbox})
    %{user: user, inbox: inbox}
  end

  test "incoming mail uses encrypted S3 storage, not forwarding; job retries are idempotent", %{
    user: user,
    inbox: inbox
  } do
    data = email_with_attachment()

    expect(MockS3Client, :put_email!, fn key, ciphertext ->
      assert key =~ "inboxes/#{inbox.id}/"
      refute ciphertext == data
      assert Vault.decrypt!(ciphertext) == data
      :ok
    end)

    job = %Oban.Job{
      id: 12_345,
      args: %{
        "from" => "travel@example.com",
        "to" => inbox.address,
        "data" => Base.encode64(data)
      }
    }

    assert :ok = EmailHandler.perform(job)
    assert :ok = EmailHandler.perform(job)
    assert [message] = Inboxes.list_messages(user, inbox.address).entries
    assert message.subject == "Your itinerary"
    refute message.read
    assert is_nil(inbox.retention_days)
    assert Repo.reload!(inbox).forwarded == 0
    refute_received {:email, _}

    expect(MockS3Client, :put_email!, fn _, _ -> :ok end)
    assert :ok = EmailHandler.perform(%{job | id: 12_346})
    assert length(Inboxes.list_messages(user, inbox.address).entries) == 2
  end

  test "failed uploads leave a hidden reservation and can retry", %{user: user, inbox: inbox} do
    expect(MockS3Client, :put_email!, fn _, _ -> raise "S3 unavailable" end)

    assert_raise RuntimeError, "S3 unavailable", fn ->
      Inboxes.store(inbox, "travel@example.com", email_with_attachment(), "retry")
    end

    assert Inboxes.list_messages(user, inbox.address).entries == []
    assert Repo.aggregate(Message, :count) == 1

    expect(MockS3Client, :put_email!, fn _, _ -> :ok end)
    assert :ok = Inboxes.store(inbox, "travel@example.com", email_with_attachment(), "retry")
    assert [%Message{stored: true}] = Inboxes.list_messages(user, inbox.address).entries
  end

  test "retrieval preserves attachment bytes and does not mark read", %{user: user, inbox: inbox} do
    message = message_fixture(inbox)

    expect(MockS3Client, :get_email!, fn key ->
      assert key == message.storage_key
      Vault.encrypt!(email_with_attachment())
    end)

    {loaded, email} = Inboxes.read_message!(user, message.id)
    refute loaded.read
    refute Repo.reload!(message).read
    assert email.text_body =~ "09:45"
    assert [attachment] = email.attachments
    assert attachment.filename == "itinerary.pdf"
    assert attachment.content_type == "application/pdf"
    assert attachment.data == <<"%PDF-1.4\n", 0, 1, 2>>
    assert Inboxes.set_read!(user, message.id, true).read
    refute Inboxes.set_read!(user, message.id, false).read
  end

  test "all operations enforce ownership before accessing S3", %{inbox: inbox} do
    outsider = user_fixture()
    message = message_fixture(inbox)

    for operation <- [
          fn -> Inboxes.list_messages(outsider, inbox.address) end,
          fn -> Inboxes.read_message!(outsider, message.id) end,
          fn -> Inboxes.set_read!(outsider, message.id, true) end,
          fn -> Inboxes.delete_message!(outsider, message.id) end,
          fn -> Inboxes.set_retention(outsider, inbox.address, 1) end
        ] do
      assert_raise Ecto.NoResultsError, operation
    end
  end

  test "text and attached emails remain attachments rather than replacing the body", %{
    user: user,
    inbox: inbox
  } do
    for {type, filename, bytes} <- [
          {"text/plain", "notes.txt", "Separate notes"},
          {"message/rfc822", "original.eml",
           "From: other@example.com\r\nSubject: Attached\r\n\r\nSeparate email"}
        ] do
      data =
        email_with_attachment()
        |> String.replace("application/pdf", type)
        |> String.replace("itinerary.pdf", filename)
        |> String.replace("JVBERi0xLjQKAAEC", Base.encode64(bytes))

      message = message_fixture(inbox)
      expect(MockS3Client, :get_email!, fn _ -> Vault.encrypt!(data) end)
      {_, email} = Inboxes.read_message!(user, message.id)
      assert email.text_body =~ "Your train leaves at 09:45"
      assert [attachment] = email.attachments
      assert attachment.filename == filename
      assert attachment.data == bytes
    end
  end

  test "disabled inboxes and blocked senders do not store mail", %{inbox: inbox} do
    {:ok, inbox} = Aliases.update_email_alias(inbox, %{enabled: false})

    assert :ok =
             IncomingEmailHandler.handle_incoming_email(
               "travel@example.com",
               inbox.address,
               email_with_attachment()
             )

    {:ok, inbox} =
      Aliases.update_email_alias(inbox, %{
        enabled: true,
        blocked_addresses: ["travel@example.com"]
      })

    assert :ok =
             IncomingEmailHandler.handle_incoming_email(
               "travel@example.com",
               inbox.address,
               email_with_attachment()
             )

    assert Repo.aggregate(Message, :count) == 0
  end

  test "spam stays in the inbox without a notification to the regular email", %{
    user: user,
    inbox: inbox
  } do
    expect(MockS3Client, :put_email!, fn _, _ -> :ok end)
    data = "X-Spam-Status: Yes, score=8.0 required=5.0\r\n" <> email_with_attachment()

    assert :ok =
             IncomingEmailHandler.handle_incoming_email(
               "travel@example.com",
               inbox.address,
               data
             )

    assert [%Message{spam: true}] = Inboxes.list_messages(user, inbox.address).entries
    assert Shroud.Email.list_spam_emails(user) == []
  end

  test "inbox aliases cannot use the outgoing reverse-alias path", %{user: user, inbox: inbox} do
    recipient = ReplyAddress.to_reply_address("external@example.com", inbox.address)

    assert :ok =
             OutgoingEmailHandler.handle_outgoing_email(
               user.email,
               recipient,
               email_with_attachment()
             )

    refute_received {:email, _}
    assert Repo.reload!(inbox).replied == 0
  end

  test "long subjects are stored without truncation", %{user: user, inbox: inbox} do
    subject = String.duplicate("A long subject. ", 30)

    data =
      String.replace(email_with_attachment(), "Subject: Your itinerary", "Subject: #{subject}")

    expect(MockS3Client, :put_email!, fn _, _ -> :ok end)
    assert :ok = Inboxes.store(inbox, "travel@example.com", data, "long-subject")
    assert [message] = Inboxes.list_messages(user, inbox.address).entries
    assert message.subject == String.trim(subject)
  end

  test "retention defaults to forever, validates days, and can be reset", %{
    user: user,
    inbox: inbox
  } do
    assert {:error, _} = Inboxes.set_retention(user, inbox.address, 0)
    assert {:error, _} = Inboxes.set_retention(user, inbox.address, -1)
    assert {:ok, %{retention_days: 14}} = Inboxes.set_retention(user, inbox.address, "14")
    assert {:ok, %{retention_days: nil}} = Inboxes.set_retention(user, inbox.address, "")
  end

  test "cleanup expires only mail outside retention and preserves forever mail", %{
    user: user,
    inbox: forever
  } do
    timed = alias_fixture(%{user_id: user.id, delivery_mode: :inbox, retention_days: 2})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old = message_fixture(timed, %{inserted_at: DateTime.add(now, -3, :day)})
    recent = message_fixture(timed, %{inserted_at: DateTime.add(now, -1, :day)})
    permanent = message_fixture(forever, %{inserted_at: DateTime.add(now, -1000, :day)})

    expect(MockS3Client, :delete_email!, fn key ->
      assert key == old.storage_key
      :ok
    end)

    Inboxes.cleanup()
    assert is_nil(Repo.get(Message, old.id))
    assert Repo.get!(Message, recent.id)
    assert Repo.get!(Message, permanent.id)
  end

  test "deleted messages are hidden immediately; failed S3 deletion remains retryable", %{
    user: user,
    inbox: inbox
  } do
    message = message_fixture(inbox)
    Inboxes.delete_message!(user, message.id)
    assert Inboxes.list_messages(user, inbox.address).entries == []
    expect(MockS3Client, :delete_email!, fn _ -> raise "S3 unavailable" end)
    assert_raise RuntimeError, "S3 unavailable", fn -> Inboxes.cleanup() end
    assert Repo.get!(Message, message.id).deleted_at

    expect(MockS3Client, :delete_email!, fn key ->
      assert key == message.storage_key
      :ok
    end)

    Inboxes.cleanup()
    assert is_nil(Repo.get(Message, message.id))
  end

  test "deleted aliases leave their S3 objects available for cleanup", %{user: user, inbox: inbox} do
    message = message_fixture(inbox)
    {:ok, _} = Aliases.delete_email_alias(inbox.id)
    assert_raise Ecto.NoResultsError, fn -> Inboxes.get_message!(user, message.id) end

    expect(MockS3Client, :delete_email!, fn key ->
      assert key == message.storage_key
      :ok
    end)

    Inboxes.cleanup()
    assert is_nil(Repo.get(Message, message.id))
  end

  test "hard-deleted aliases retain a cleanup record for their S3 objects", %{inbox: inbox} do
    message = message_fixture(inbox)
    Repo.delete!(inbox)
    assert is_nil(Repo.reload!(message).email_alias_id)

    expect(MockS3Client, :delete_email!, fn key ->
      assert key == message.storage_key
      :ok
    end)

    Inboxes.cleanup()
    assert is_nil(Repo.get(Message, message.id))
  end
end

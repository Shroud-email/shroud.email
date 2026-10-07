defmodule Shroud.Email.UnsubscribeTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.{AccountsFixtures, AliasesFixtures}
  import Swoosh.TestAssertions

  alias Ecto.Adapters.SQL
  alias Shroud.{Aliases, Repo}

  alias Shroud.Email.{
    EmailHandler,
    IncomingEmailHandler,
    ParsedEmail,
    ReplyAddress,
    Unsubscribe,
    UnsubscribeRelay
  }

  @sender "news@example.com"
  @url "<https://example.com/unsubscribe?id=abc%2B123>"
  @marker "List-Unsubscribe=One-Click"

  setup do
    user = user_fixture(%{status: :active})
    %{user: user, email_alias: alias_fixture(%{user_id: user.id})}
  end

  test "all four preferences choose the original or the specified local action", %{user: user} do
    for {preference, action, forward?} <- [
          {:forward_then_block, :block, true},
          {:forward_then_disable, :disable, true},
          {:always_block, :block, false},
          {:always_disable, :disable, false}
        ],
        original? <- [true, false] do
      email_alias = alias_fixture(%{user_id: user.id})
      message = message(if original?, do: attestation(@url, @marker), else: nil)

      email =
        Unsubscribe.add_headers(
          Swoosh.Email.new(),
          %{user | unsubscribe_behavior: preference},
          email_alias,
          @sender,
          message
        )

      if original? and forward? do
        assert email.headers["List-Unsubscribe"] == @url
      else
        token =
          email.headers["List-Unsubscribe"]
          |> String.trim_leading("<")
          |> String.trim_trailing(">")
          |> URI.parse()
          |> Map.fetch!(:path)
          |> String.replace_prefix("/unsubscribe/", "")

        assert {:ok, updated} = Unsubscribe.consume(token)
        assert updated.enabled == (action == :block)
        assert updated.blocked_addresses == if(action == :block, do: [@sender], else: [])
      end

      assert email.headers["List-Unsubscribe-Post"] == @marker
      refute Map.has_key?(email.headers, "x-shroud-unsubscribe")
    end
  end

  test "verified unsubscribe values have a 4096-byte limit", %{
    user: user,
    email_alias: email_alias
  } do
    prefix = "<https://example.com/unsubscribe?token="

    for bytes <- [4096, 4097] do
      url = prefix <> String.duplicate("a", bytes - byte_size(prefix) - 1) <> ">"

      email =
        Unsubscribe.add_headers(
          Swoosh.Email.new(),
          user,
          email_alias,
          @sender,
          message(attestation(url, @marker))
        )

      if bytes == 4096 do
        assert email.headers["List-Unsubscribe"] == url
      else
        assert email.headers["List-Unsubscribe"] =~ "/unsubscribe/"
      end
    end
  end

  test "mailto expiry, renewal and cleanup preserve only valid relays", %{
    user: user,
    email_alias: email_alias
  } do
    recipient = mailto_relay(user, email_alias)

    recent =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-89 * 86_400)
      |> NaiveDateTime.truncate(:second)

    expired =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-91 * 86_400)
      |> NaiveDateTime.truncate(:second)

    Repo.update_all(UnsubscribeRelay, set: [inserted_at: recent])
    assert {0, _} = Unsubscribe.prune_relays()
    assert :ok = Unsubscribe.relay_email(user.email, recipient)
    assert_email_sent()

    Repo.update_all(UnsubscribeRelay, set: [inserted_at: expired])
    assert :ok = Unsubscribe.relay_email(user.email, recipient)
    refute_email_sent()

    assert mailto_relay(user, email_alias) == recipient
    assert {0, _} = Unsubscribe.prune_relays()
    assert :ok = Unsubscribe.relay_email(user.email, recipient)
    assert_email_sent()

    Repo.update_all(UnsubscribeRelay, set: [inserted_at: expired])
    assert {1, _} = Unsubscribe.prune_relays()
    assert Repo.aggregate(UnsubscribeRelay, :count) == 0

    assert mailto_relay(user, email_alias) == recipient
    assert :ok = Unsubscribe.relay_email(user.email, recipient)
    assert_email_sent()

    assert {:ok, blocked} = Aliases.block_sender(email_alias, @sender)
    assert {:ok, current} = Aliases.unblock_sender(blocked, @sender)
    assert {1, _} = Unsubscribe.prune_relays()
    mailto_relay(user, current)
    assert {:ok, _} = Aliases.delete_email_alias(email_alias.id)
    assert {1, _} = Unsubscribe.prune_relays()
    assert {0, _} = Unsubscribe.prune_relays()
  end

  test "ordinary verified unsubscribe is preserved without inventing one-click support", %{
    user: user,
    email_alias: email_alias
  } do
    original = "<mailto:leave@example.com?subject=unsubscribe>, " <> @url

    email =
      Unsubscribe.add_headers(
        Swoosh.Email.new(),
        user,
        email_alias,
        @sender,
        message(attestation(original, nil))
      )

    assert email.headers["List-Unsubscribe"] =~
             ~r/^<mailto:unsubscribe_[0-9a-f]{48}@email\.shroud\.test\?subject=unsubscribe>, /

    assert String.ends_with?(email.headers["List-Unsubscribe"], @url)

    refute Map.has_key?(email.headers, "List-Unsubscribe-Post")
  end

  test "free users can relay verified mailto unsubscribe but cannot send ordinary replies" do
    user = user_fixture(%{status: :free})
    email_alias = alias_fixture(%{user_id: user.id})
    original = "<mailto:leave@example.com?subject=List+leave&body=remove%0D%0Arecipient%2Bid>"

    data =
      "From: #{@sender}\r\nTo: #{email_alias.address}\r\nSubject: News\r\nX-Shroud-Unsubscribe: #{attestation(original, nil)}\r\n\r\nNews"

    assert :ok = perform_job(EmailHandler, %{from: @sender, to: email_alias.address, data: data})

    assert_receive {:email, forwarded}

    uri =
      forwarded.headers["List-Unsubscribe"]
      |> String.trim_leading("<")
      |> String.trim_trailing(">")
      |> URI.parse()

    assert Unsubscribe.relay_address?(uri.path)
    {local, _} = Shroud.Util.extract_email_parts(uri.path)
    assert byte_size(local) <= 64
    assert uri.query == "subject=List+leave&body=remove%0D%0Arecipient%2Bid"

    malicious =
      "From: #{user.email}\r\nTo: other@example.com\r\nCc: extra@example.com\r\nReply-To: #{user.email}\r\nSubject: Arbitrary message\r\nContent-Type: multipart/mixed; boundary=evil\r\n\r\n--evil\r\nContent-Type: text/plain\r\n\r\nOrdinary content\r\n--evil\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=evil.txt\r\n\r\nAttachment\r\n--evil--"

    assert :ok = perform_job(EmailHandler, %{from: user.email, to: uri.path, data: malicious})

    assert_email_sent(fn email ->
      assert email.from == {"", email_alias.address}
      assert email.to == [{"", "leave@example.com"}]
      assert email.subject == "List+leave"
      assert email.text_body == "remove\r\nrecipient+id"
      assert email.cc == [] and email.bcc == [] and email.attachments == []
      assert email.headers == %{} and email.reply_to == nil and email.html_body == nil
    end)

    ordinary = ReplyAddress.to_reply_address("leave@example.com", email_alias.address)
    assert :ok = perform_job(EmailHandler, %{from: user.email, to: ordinary, data: malicious})
    refute_email_sent()
  end

  test "mailto capabilities reject other owners, unknown tokens, altered domains and inactive accounts",
       %{user: user, email_alias: email_alias} do
    recipient = mailto_relay(user, email_alias)
    other = user_fixture(%{status: :free})

    for {sender, target} <- [
          {other.email, recipient},
          {"unknown@example.com", recipient},
          {user.email, "unsubscribe_" <> String.duplicate("0", 48) <> "@email.shroud.test"},
          {user.email, String.replace(recipient, "@email.shroud.test", "@elsewhere.example")}
        ] do
      assert :ok =
               perform_job(EmailHandler, %{
                 from: sender,
                 to: target,
                 data: "Subject: unsubscribe\r\n\r\nunsubscribe"
               })

      refute_email_sent()
    end

    for status <- [:lead, :inactive] do
      user |> Ecto.Changeset.change(status: status) |> Repo.update!()
      assert :ok = perform_job(EmailHandler, %{from: user.email, to: recipient, data: ""})
      refute_email_sent()
    end
  end

  test "mailto capabilities are deduplicated, encrypted and revoked on re-enable or deletion", %{
    user: user,
    email_alias: email_alias
  } do
    recipient = mailto_relay(user, email_alias)
    assert mailto_relay(user, email_alias) == recipient
    assert Repo.aggregate(UnsubscribeRelay, :count) == 1

    %{rows: [[recipe]]} =
      SQL.query!(
        Repo,
        "SELECT recipe FROM email_unsubscribe_relays WHERE alias_id = $1",
        [email_alias.id]
      )

    refute recipe =~ "leave@example.com"

    assert {:ok, disabled} = Aliases.update_email_alias(email_alias, %{enabled: false})
    assert {:ok, enabled} = Aliases.update_email_alias(disabled, %{enabled: true})
    assert :ok = perform_job(EmailHandler, %{from: user.email, to: recipient, data: ""})
    refute_email_sent()

    new_recipient = mailto_relay(user, enabled)
    refute new_recipient == recipient
    assert :ok = perform_job(EmailHandler, %{from: user.email, to: new_recipient, data: ""})

    assert_email_sent(fn email ->
      assert email.subject == "unsubscribe"
      assert email.text_body == "unsubscribe"
      assert email.from == {"", email_alias.address}
    end)

    assert {:ok, _} = Aliases.delete_email_alias(email_alias.id)
    assert :ok = perform_job(EmailHandler, %{from: user.email, to: new_recipient, data: ""})
    refute_email_sent()
    Repo.delete!(Repo.reload!(email_alias))
    assert Repo.aggregate(UnsubscribeRelay, :count) == 0
  end

  test "untrusted, expired, malformed and non-HTTPS one-click metadata falls back", %{
    user: user,
    email_alias: email_alias
  } do
    for metadata <- [
          nil,
          attestation(@url, @marker) <> "tampered",
          attestation(@url, @marker, System.system_time(:second) - 604_801),
          attestation(@url, @marker, System.system_time(:second) + 61),
          attestation("<http://example.com/unsubscribe>", @marker),
          attestation("<https://example.com:invalid/unsubscribe>", @marker),
          attestation("<https://example.com/unsubscribe?token=%XX>", @marker),
          attestation(@url <> ", <https://other.example/unsubscribe>", @marker),
          attestation("<javascript:alert(1)>", nil),
          attestation("<mailto:leave@example.com?%63c=other@example.com>", nil),
          attestation("<mailto:leave@example.com?reply-to=real@example.com>", nil),
          attestation(
            "<mailto:leave@example.com?subject=unsubscribe%0d%0aBcc:other@example.com>",
            nil
          ),
          attestation("<mailto:leave@example.com?subject=first&Subject=second>", nil),
          attestation("<mailto:leave%0d%0aInjected@example.com>", nil),
          attestation("<mailto:leave%00@example.com>", nil),
          attestation("<mailto:leave%FF@example.com>", nil),
          attestation("<mailto:leave@example.com?subject=%FF>", nil),
          attestation("<mailto:leave@example.com?body=%FF>", nil),
          attestation("<mailto:leave@example.com#fragment>", nil),
          attestation(@url <> "\r\nX-Evil: yes", nil),
          attestation(@url, "List-Unsubscribe=Something-Else")
        ] do
      email =
        Unsubscribe.add_headers(Swoosh.Email.new(), user, email_alias, @sender, message(metadata))

      assert email.headers["List-Unsubscribe"] =~ "/unsubscribe/"
      assert email.headers["List-Unsubscribe-Post"] == @marker
    end

    assert Repo.aggregate(UnsubscribeRelay, :count) == 0
  end

  test "blocking is idempotent, alias-scoped, and revoked after unblocking", %{
    user: user,
    email_alias: email_alias
  } do
    other = alias_fixture(%{user_id: user.id})
    token = Unsubscribe.token(email_alias, :block, String.upcase(@sender))
    assert {:ok, blocked} = Unsubscribe.consume(token)
    assert {:ok, _} = Unsubscribe.consume(token)
    assert Repo.reload!(email_alias).blocked_addresses == [@sender]
    assert Repo.reload!(other).blocked_addresses == []

    assert {:ok, _} = Aliases.block_sender(email_alias, "another@example.com")
    assert {:ok, unblocked} = Aliases.unblock_sender(blocked, @sender)
    assert unblocked.blocked_addresses == ["another@example.com"]
    assert {:error, :invalid} = Unsubscribe.consume(token)
    assert {:ok, _} = Unsubscribe.consume(Unsubscribe.token(unblocked, :block, @sender))
  end

  test "disabling is idempotent and old capabilities cannot disable a re-enabled alias", %{
    email_alias: email_alias
  } do
    token = Unsubscribe.token(email_alias, :disable, @sender)
    assert {:ok, disabled} = Unsubscribe.consume(token)
    refute disabled.enabled
    assert {:ok, _} = Unsubscribe.consume(token)
    assert {:ok, enabled} = Aliases.update_email_alias(disabled, %{enabled: true})
    assert {:error, :invalid} = Unsubscribe.consume(token)
    assert Repo.reload!(enabled).enabled
    assert {:error, :invalid} = Unsubscribe.consume(token <> "invalid")
  end

  test "deleted alias capabilities are rejected", %{email_alias: email_alias} do
    token = Unsubscribe.token(email_alias, :disable, @sender)
    assert {:ok, _} = Aliases.delete_email_alias(email_alias.id)
    assert {:error, :invalid} = Unsubscribe.consume(token)
  end

  test "an old capability cannot affect an alias recreated at the same address", %{
    user: user,
    email_alias: email_alias
  } do
    token = Unsubscribe.token(email_alias, :disable, @sender)
    Repo.delete!(email_alias)
    recreated = alias_fixture(%{user_id: user.id, address: email_alias.address})
    assert {:error, :invalid} = Unsubscribe.consume(token)
    assert Repo.reload!(recreated).enabled
  end

  test "forwarded headers survive parsing and blocking suppresses only the selected sender", %{
    email_alias: email_alias,
    user: user
  } do
    data =
      "From: News <news@example.com>\r\nTo: #{email_alias.address}\r\nSubject: Test\r\nList-Unsubscribe: #{@url}\r\nList-Unsubscribe-Post: #{@marker}\r\n\r\nHello"

    assert :ok = IncomingEmailHandler.handle_incoming_email(@sender, email_alias.address, data)

    assert_email_sent(fn email ->
      assert [{_name, address}] = email.to
      assert address == user.email
      assert email.headers["List-Unsubscribe"] =~ "/unsubscribe/"
      assert email.headers["List-Unsubscribe-Post"] == @marker
    end)

    assert {:ok, _} = Unsubscribe.consume(Unsubscribe.token(email_alias, :block, @sender))
    assert :ok = IncomingEmailHandler.handle_incoming_email(@sender, email_alias.address, data)
    refute_email_sent()

    assert :ok =
             IncomingEmailHandler.handle_incoming_email(
               "different@example.com",
               email_alias.address,
               data
             )

    assert_email_sent()

    trusted_data =
      String.replace(
        data,
        "Subject: Test",
        "Subject: Test\r\nX-Shroud-Unsubscribe: " <> attestation(@url, @marker)
      )

    parsed = Mailex.parse!(trusted_data)
    email = ParsedEmail.parse(parsed, @sender, email_alias.address).swoosh_email
    forwarded = Unsubscribe.add_headers(email, user, email_alias, @sender, parsed)
    assert forwarded.headers["List-Unsubscribe"] == @url
    refute Map.has_key?(forwarded.headers, "x-shroud-unsubscribe")
  end

  defp message(metadata) do
    headers = %{
      "list-unsubscribe" => @url,
      "list-unsubscribe-post" => @marker,
      "authentication-results" => "dkim=pass"
    }

    %{
      headers: if(metadata, do: Map.put(headers, "x-shroud-unsubscribe", metadata), else: headers)
    }
  end

  defp mailto_relay(user, email_alias) do
    email =
      Unsubscribe.add_headers(
        Swoosh.Email.new(),
        user,
        email_alias,
        @sender,
        message(attestation("<mailto:leave@example.com>", nil))
      )

    email.headers["List-Unsubscribe"]
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> URI.parse()
    |> Map.fetch!(:path)
  end

  defp attestation(unsubscribe, post, timestamp \\ System.system_time(:second)) do
    payload =
      Jason.encode!(%{unsubscribe: unsubscribe, post: post, timestamp: timestamp})
      |> Base.url_encode64(padding: false)

    secret = Application.fetch_env!(:shroud, :unsubscribe_attestation_secret)

    mac =
      :crypto.mac(:hmac, :sha256, secret, "shroud-unsubscribe:" <> payload)
      |> Base.url_encode64(padding: false)

    payload <> "." <> mac
  end
end

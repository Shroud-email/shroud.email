defmodule Shroud.EmailTest do
  use Shroud.DataCase, async: true
  alias Shroud.Repo
  alias Shroud.Email
  alias Shroud.Email.Tracker
  import Shroud.{AccountsFixtures, AliasesFixtures, EmailFixtures}

  setup do
    changeset = Tracker.changeset(%Tracker{}, %{name: "Tracker Co.", pattern: "tracker\.co"})
    tracker = Repo.insert!(changeset)

    user = user_fixture()
    email_alias = alias_fixture(%{user_id: user.id})

    %{tracker: tracker, user: user, email_alias: email_alias}
  end

  describe "list_trackers/0" do
    test "fetches all trackers", %{tracker: tracker} do
      trackers = Email.list_trackers()

      assert length(trackers) == 1
      assert hd(trackers).name == tracker.name
      assert hd(trackers).pattern == tracker.pattern
    end
  end

  describe "store_spam_email!/3" do
    test "saves the spam email", %{user: user, email_alias: email_alias} do
      attrs = %{from: "spammer@example.com", subject: "Spam", text_body: "spam"}
      spam_email = Email.store_spam_email!(attrs, user, email_alias)

      assert spam_email.from == "spammer@example.com"
      assert spam_email.subject == "Spam"
      assert spam_email.text_body == "spam"
      assert spam_email.user_id == user.id
      assert spam_email.email_alias_id == email_alias.id
    end

    test "converts CRLF to LF", %{user: user, email_alias: email_alias} do
      attrs = %{
        from: "spammer@example.com",
        subject: "Spam",
        text_body: "hello\r\n\r\nworld",
        html_body: "hello\r\n\r\nworld"
      }

      spam_email = Email.store_spam_email!(attrs, user, email_alias)

      assert spam_email.text_body == "hello\n\nworld"
      assert spam_email.html_body == "hello\n\nworld"
    end

    test "removes <script> tags", %{user: user, email_alias: email_alias} do
      attrs = %{
        from: "spammer@example.com",
        subject: "Spam",
        html_body: "<p>hi</p><script>alert('xss')</script>"
      }

      spam_email = Email.store_spam_email!(attrs, user, email_alias)

      assert spam_email.html_body == "<p>hi</p>alert('xss')"
    end

    test "prevents other XSS", %{user: user, email_alias: email_alias} do
      attrs = %{
        from: "spammer@example.com",
        subject: "Spam",
        html_body: "<p>hi</p><img src='abc' onerror='alert(1)' />"
      }

      spam_email = Email.store_spam_email!(attrs, user, email_alias)

      assert spam_email.html_body == "<p>hi</p><img src=\"abc\" />"
    end
  end

  describe "list_spam_emails/1" do
    test "lists spam emails for a user", %{user: user, email_alias: email_alias} do
      spam_email_fixture(%{}, user, email_alias)
      spam_email_fixture(%{}, user, email_alias)

      assert length(Email.list_spam_emails(user)) == 2
    end

    test "does not list other user's spam emails", %{user: user} do
      other_user = user_fixture()
      other_alias = alias_fixture(%{user_id: other_user.id})
      spam_email_fixture(%{}, other_user, other_alias)

      assert Enum.empty?(Email.list_spam_emails(user))
    end
  end

  describe "count_spam_emails/1" do
    test "counts spam emails for a user", %{user: user, email_alias: email_alias} do
      spam_email_fixture(%{}, user, email_alias)
      spam_email_fixture(%{}, user, email_alias)

      assert Email.count_spam_emails(user) == 2
    end

    test "does not count other user's spam emails", %{user: user} do
      other_user = user_fixture()
      other_alias = alias_fixture(%{user_id: other_user.id})
      spam_email_fixture(%{}, other_user, other_alias)

      assert Email.count_spam_emails(user) == 0
    end
  end

  describe "delete_old_spam_emails/0" do
    test "deletes spam emails older than 7 days" do
      # 7 days and 1 hour ago
      old_date =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-7 * 24 * 60 * 60, :second)
        |> NaiveDateTime.add(-1 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      spam_email = spam_email_fixture(%{inserted_at: old_date})

      assert 1 == Email.delete_old_spam_emails()
      assert spam_email |> Repo.reload() |> is_nil()
    end

    test "does not delete recent spam emails" do
      spam_email = spam_email_fixture()

      assert 0 == Email.delete_old_spam_emails()
      refute spam_email |> Repo.reload() |> is_nil()
    end
  end
end

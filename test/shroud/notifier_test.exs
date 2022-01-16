defmodule Shroud.NotifierTest do
  use Shroud.DataCase, async: true
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.{Notifier, NotifierJob}

  test "notify_user_started_trial/1" do
    Notifier.notify_user_started_trial("user@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "🧑 **user@example.com** just signed up for a free trial!"}}
    )
  end

  test "notify_user_signed_up/1" do
    Notifier.notify_user_signed_up("user@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "🎉 **user@example.com** just signed up for a paid plan!"}}
    )
  end

  test "notify_outgoing_email_marked_as_spam/2" do
    Notifier.notify_outgoing_email_marked_as_spam("from@example.com", "to@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{
        payload: %{
          "content" =>
            "⚠️ Email from **from@example.com** to **to@example.com** marked as spam by OhMySMTP"
        }
      }
    )
  end

  test "notify_outgoing_email_bounced/2" do
    Notifier.notify_outgoing_email_bounced("from@example.com", "to@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{
        payload: %{
          "content" =>
            "⚠️ Email from **from@example.com** to **to@example.com** hard bounced. Failed to forward!"
        }
      }
    )
  end
end

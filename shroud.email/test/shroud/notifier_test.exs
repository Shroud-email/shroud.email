defmodule Shroud.NotifierTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.{Notifier, NotifierJob}

  setup do
    url = Application.fetch_env!(:shroud, :notifier_webhook_url)
    on_exit(fn -> Application.put_env(:shroud, :notifier_webhook_url, url) end)
  end

  test "does not enqueue notifications when the webhook is disabled" do
    email = Shroud.AccountsFixtures.unique_user_email()

    for url <- [nil, ""] do
      Application.put_env(:shroud, :notifier_webhook_url, url)

      assert :ok = Notifier.notify_user_signed_up_free(email)
      assert :ok = Notifier.notify_user_signed_up(email)
    end

    Application.delete_env(:shroud, :notifier_webhook_url)

    assert :ok = Notifier.notify_user_signed_up_free(email)
    assert :ok = Notifier.notify_user_signed_up(email)

    refute_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "**#{email}** just signed up (free tier)!"}}
    )

    refute_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "🎉 **#{email}** just signed up for a paid plan!"}}
    )
  end

  test "notify_user_signed_up_free/1" do
    Notifier.notify_user_signed_up_free("user@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "**user@example.com** just signed up (free tier)!"}}
    )
  end

  test "notify_user_signed_up/1" do
    Notifier.notify_user_signed_up("user@example.com")

    assert_enqueued(
      worker: NotifierJob,
      args: %{payload: %{"content" => "🎉 **user@example.com** just signed up for a paid plan!"}}
    )
  end
end

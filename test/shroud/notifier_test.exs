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
end

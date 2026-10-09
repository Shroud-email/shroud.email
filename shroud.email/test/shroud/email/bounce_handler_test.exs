defmodule Shroud.Email.BounceHandlerTest do
  use Shroud.DataCase, async: true
  import ExUnit.CaptureLog
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.Email.BounceHandler

  describe "handle_haraka_bounce_report/2" do
    test "logs a warning without email data or an archive" do
      Sentry.Test.setup_sentry(dedup_events: false)

      log =
        capture_log(fn ->
          assert :ok =
                   BounceHandler.handle_haraka_bounce_report("test@test.com", "email-contents")
        end)

      assert log =~ "Received an unclassified email bounce report"
      refute log =~ "test@test.com"
      refute log =~ "email-contents"
      refute_enqueued(worker: Shroud.S3.S3UploadJob)
    end
  end
end

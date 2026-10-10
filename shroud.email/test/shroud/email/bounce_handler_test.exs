defmodule Shroud.Email.BounceHandlerTest do
  use Shroud.DataCase, async: true
  import ExUnit.CaptureLog
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.Email.BounceHandler

  describe "handle_haraka_bounce_report/2" do
    test "archives the report and sends its object path to Sentry" do
      Sentry.Test.setup_sentry(dedup_events: false)

      log =
        capture_log(fn ->
          assert :ok =
                   BounceHandler.handle_haraka_bounce_report("test@test.com", "email-contents")
        end)

      assert [upload] = all_enqueued(worker: Shroud.S3.S3UploadJob)
      assert upload.args["content"] == "email-contents"
      assert upload.args["path"] =~ "/bounces/test@test.com-"
      assert log =~ "Received bounce report from Haraka! See #{upload.args["path"]}."
      refute log =~ "email-contents"
      assert [event] = Sentry.Test.pop_sentry_reports()
      assert event.extra == %{s3_path: upload.args["path"]}
    end
  end
end

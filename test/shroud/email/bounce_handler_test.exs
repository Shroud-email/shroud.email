defmodule Shroud.Email.BounceHandlerTest do
  use Shroud.DataCase, async: true
  import ExUnit.CaptureLog
  import Mox
  use Oban.Testing, repo: Shroud.Repo
  alias Shroud.Email.BounceHandler

  setup :verify_on_exit!

  describe "handle_haraka_bounce_report/2" do
    test "logs a warning and uploads the email to S3" do
      Shroud.MockDateTime
      |> stub(:utc_now_unix, fn ->
        1_656_358_048
      end)

      assert capture_log(fn ->
               BounceHandler.handle_haraka_bounce_report("test@test.com", "email-contents")
             end) =~
               "Received bounce report from Haraka! See /bounces/test@test.com-1656358048.eml."

      assert_enqueued(
        worker: Shroud.S3.S3UploadJob,
        args: %{
          path: "/bounces/test@test.com-1656358048.eml",
          contents: "email-contents"
        }
      )
    end
  end
end

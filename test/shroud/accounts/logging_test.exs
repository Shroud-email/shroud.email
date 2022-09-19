defmodule Shroud.Accounts.LoggingTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.Accounts.Logging
  alias Shroud.S3.S3UploadJob

  setup :verify_on_exit!

  describe "store_email/3" do
    test "uploads an email to S3" do
      Shroud.MockDateTime
      |> stub(:utc_now_unix, fn ->
        1_656_358_048
      end)

      Logging.store_email("sender@example.com", "recipient@example.com", "data")

      assert_enqueued(
        worker: S3UploadJob,
        args: %{
          path: "/emails/sender@example.com-recipient@example.com-1656358048.eml",
          content: "data"
        }
      )
    end
  end
end

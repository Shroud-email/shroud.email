defmodule Shroud.S3.S3UploadJobTest do
  use Shroud.DataCase
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.S3.S3UploadJob

  setup :verify_on_exit!

  describe "perform/1" do
    test "uploads to s3" do
      Shroud.S3.MockS3Client
      |> expect(:put_email!, fn path, content ->
        assert path == "/emails/yolo.eml"
        assert content == "my email content\n"

        :done
      end)

      assert :ok =
               perform_job(S3UploadJob, %{
                 path: "/emails/yolo.eml",
                 contents: "my email content\n"
               })
    end
  end
end

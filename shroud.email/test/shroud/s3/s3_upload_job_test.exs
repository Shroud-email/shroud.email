defmodule Shroud.S3.S3UploadJobTest do
  use Shroud.DataCase
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.S3.S3UploadJob

  setup :verify_on_exit!

  describe "perform/1" do
    test "uploads Base64 encoded content to s3" do
      raw_content = "my email content\n"

      Shroud.S3.MockS3Client
      |> expect(:put_email!, fn path, content ->
        assert path == "/emails/yolo.eml"
        assert content == raw_content

        :done
      end)

      # New jobs have Base64 encoded content
      assert :ok =
               perform_job(S3UploadJob, %{
                 path: "/emails/yolo.eml",
                 content: Base.encode64(raw_content)
               })
    end

    test "handles legacy jobs with non-Base64 encoded content" do
      # Legacy jobs (created before Base64 encoding was added) have raw content.
      # This test ensures backwards compatibility during deployment transition.
      raw_content = "my legacy email content\n"

      Shroud.S3.MockS3Client
      |> expect(:put_email!, fn path, content ->
        assert path == "/emails/legacy.eml"
        # Should receive raw content since it's not valid Base64
        assert content == raw_content

        :done
      end)

      assert :ok =
               perform_job(S3UploadJob, %{
                 path: "/emails/legacy.eml",
                 content: raw_content
               })
    end
  end
end

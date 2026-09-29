defmodule Shroud.S3.S3UploadJob do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"path" => path, "content" => content}}) do
    # Decode Base64 encoded email content (encoded in Logging.store_email to safely store as JSONB).
    # Falls back to raw content for backwards compatibility with jobs created before encoding was added.
    decoded_content =
      case Base.decode64(content) do
        {:ok, decoded} -> decoded
        :error -> content
      end

    client_impl().put_email!(path, decoded_content)
    :ok
  end

  defp client_impl do
    Application.get_env(:shroud, :s3_client, Shroud.S3.S3Client)
  end
end

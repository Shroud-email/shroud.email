defmodule Shroud.S3.S3UploadJob do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"path" => path, "contents" => contents}}) do
    client_impl().put_email!(path, contents)
    :ok
  end

  defp client_impl do
    Application.get_env(:shroud, :s3_client, Shroud.S3.S3Client)
  end
end

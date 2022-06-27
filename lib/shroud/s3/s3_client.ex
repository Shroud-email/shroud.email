defmodule Shroud.S3.S3Client do
  alias ExAws.S3

  @callback put_email!(String.t(), String.t()) :: term()

  def put_email!(path, contents) do
    bucket = Application.fetch_env!(:shroud, :bounces)[:s3_bucket]

    bucket
    |> S3.put_object(path, contents)
    |> ExAws.request!()
  end
end

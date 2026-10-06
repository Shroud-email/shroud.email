defmodule Shroud.S3.S3Client do
  alias ExAws.S3

  @callback put_email!(String.t(), String.t()) :: term()
  @callback get_email!(String.t()) :: binary()
  @callback delete_email!(String.t()) :: term()

  def get_email!(path) do
    bucket = Application.fetch_env!(:shroud, :bounces)[:s3_bucket]
    %{body: body} = bucket |> S3.get_object(path) |> ExAws.request!()
    body
  end

  def delete_email!(path) do
    bucket = Application.fetch_env!(:shroud, :bounces)[:s3_bucket]
    bucket |> S3.delete_object(path) |> ExAws.request!()
  end

  def put_email!(path, contents) do
    bucket = Application.fetch_env!(:shroud, :bounces)[:s3_bucket]

    bucket
    |> S3.put_object(path, contents)
    |> ExAws.request!()
  end
end

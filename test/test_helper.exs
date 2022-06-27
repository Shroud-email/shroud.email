ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Shroud.Repo, :manual)

Mox.defmock(Shroud.MockHTTPoison, for: HTTPoison.Base)
Application.put_env(:shroud, :http_client, Shroud.MockHTTPoison)

Mox.defmock(Shroud.S3.MockS3Client, for: Shroud.S3.S3Client)
Application.put_env(:shroud, :s3_client, Shroud.S3.MockS3Client)

Mox.defmock(Shroud.MockDateTime, for: Shroud.DateTimeBehaviour)
Application.put_env(:shroud, :datetime_module, Shroud.MockDateTime)

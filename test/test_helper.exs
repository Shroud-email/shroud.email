ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Shroud.Repo, :manual)

Mox.defmock(Shroud.MockHTTPoison, for: HTTPoison.Base)
Application.put_env(:shroud, :http_client, Shroud.MockHTTPoison)

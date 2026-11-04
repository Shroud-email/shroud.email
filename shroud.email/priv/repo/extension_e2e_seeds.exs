import Ecto.Query
alias Shroud.{Accounts, Repo}
alias Shroud.Aliases.EmailAlias
alias Shroud.Domain.CustomDomain

repo = Application.fetch_env!(:shroud, Repo)

unless Mix.env() == :test and System.get_env("EXTENSION_E2E") == "1" and
         repo[:database] == "shroud_extension_e2e" and
         repo[:hostname] in ["localhost", "127.0.0.1"] do
  raise "Extension fixtures require the isolated local shroud_extension_e2e test database"
end

Application.put_env(:shroud, :minimal, true)
Application.put_env(:shroud, :app_domain, "localhost")
Application.put_env(:shroud, :email_domain, "fog.shroud.test")
endpoint = Application.fetch_env!(:shroud, ShroudWeb.Endpoint)

Application.put_env(
  :shroud,
  ShroudWeb.Endpoint,
  Keyword.merge(endpoint,
    server: System.get_env("EXTENSION_E2E_SEED_ONLY") != "1",
    http: [ip: {127, 0, 0, 1}, port: 4407],
    url: [host: "localhost", scheme: "http", port: 4407]
  )
)

{:ok, _} = Application.ensure_all_started(:shroud)
now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

for {name, status, count} <- [{"free", :free, 2}, {"paid", :active, 25}] do
  email = "extension-#{name}@example.test"

  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} =
          Accounts.register_user(%{email: email, password: "extension test passphrase"})

        user

      user ->
        user
    end

  user = user |> Ecto.Changeset.change(status: status, confirmed_at: now) |> Repo.update!()
  Repo.delete_all(from a in EmailAlias, where: a.user_id == ^user.id)

  for index <- 1..count do
    %EmailAlias{}
    |> Ecto.Changeset.change(%{
      user_id: user.id,
      address: "#{name}-#{index}@fog.shroud.test",
      title: "Example #{index}",
      enabled: index != 2,
      inserted_at: NaiveDateTime.add(now, -index)
    })
    |> Repo.insert!()
  end

  if status == :active do
    domain =
      Repo.get_by(CustomDomain, user_id: user.id, domain: "custom.example.test") ||
        %CustomDomain{}

    domain
    |> Ecto.Changeset.change(%{
      user_id: user.id,
      domain: "custom.example.test",
      verification_code: "extension-e2e",
      ownership_verified_at: now,
      dkim_verified_at: now,
      dmarc_verified_at: now,
      mx_verified_at: now,
      spf_verified_at: now
    })
    |> Repo.insert_or_update!()
  end
end

IO.puts("Extension E2E Phoenix ready at http://localhost:4407")

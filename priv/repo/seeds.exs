# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Shroud.Repo.insert!(%Shroud.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Shroud.Aliases
alias Shroud.Accounts.User
alias Shroud.Repo
alias Shroud.Domain
alias Shroud.Email

user =
  %User{}
  |> User.registration_changeset(%{
    email: "test@test.com",
    password: "123456789012",
    status: :active
  })
  |> Repo.insert!(returning: true)

user
|> User.confirm_changeset(%{status: :active})
|> Repo.update!()

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

{:ok, domain} = Domain.create_custom_domain(user, %{domain: "verified.com"})

domain
|> Ecto.Changeset.change(%{
  ownership_verified_at: now,
  mx_verified_at: now,
  spf_verified_at: now,
  dkim_verified_at: now,
  dmarc_verified_at: now
})
|> Repo.update!()

user
|> Domain.create_custom_domain(%{domain: "unverified.com"})

aliases = [
  %{title: "e-shop.co"},
  %{title: "1337 Newsletter", enabled: false},
  %{description: "Lorem ipsum"},
  %{title: "Anonymous contact address"},
  %{
    enabled: false,
    description: "Haxx0r ipsum brute force server continue void snarf case it's a feature."
  },
  %{title: "Twitter"},
  %{title: ""}
]

Enum.each(aliases, fn alias_attrs ->
  Aliases.create_random_email_alias(user, alias_attrs)

  # Sleep to ensure that the aliases are created in the correct order (i.e. not at the exact same timestamp)
  :timer.sleep(500)
end)

Aliases.create_email_alias(%{
  user_id: user.id,
  title: "Airport WiFi",
  description: "Created via catch-all",
  address: "airport@verified.com"
})

user
|> Aliases.list_aliases()
|> Enum.each(fn email_alias ->
  number_forwarded = :rand.uniform(20)
  number_blocked = :rand.uniform(5)

  Enum.each(1..number_forwarded, fn _ ->
    Aliases.increment_forwarded!(email_alias)
  end)

  Enum.each(1..number_blocked, fn _ ->
    Aliases.increment_blocked!(email_alias)
  end)

  Email.store_spam_email!(
    %{text_body: "Lorem ipsum", from: "spammer@test.com", subject: "Spam"},
    user,
    email_alias
  )
end)

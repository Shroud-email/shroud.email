defmodule Mix.Tasks.AddDomainFk do
  use Mix.Task
  @app :shroud
  alias Shroud.Repo
  import Ecto.Query
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Domain.CustomDomain

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(@app)

    Repo.all(from(d in CustomDomain))
    |> Enum.each(fn domain ->
      # get all aliases for this domain
      aliases =
        from(a in EmailAlias, where: ilike(a.address, ^"%@#{domain.domain}"))
        |> Repo.all()
        |> Enum.map(&Map.get(&1, :id))

      # update them with the domain id
      from(a in EmailAlias, where: a.id in ^aliases)
      |> Repo.update_all(set: [domain_id: domain.id])
    end)
  end
end

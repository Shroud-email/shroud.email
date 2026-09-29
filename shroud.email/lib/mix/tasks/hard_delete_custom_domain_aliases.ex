defmodule Mix.Tasks.HardDeleteCustomDomainAliases do
  use Mix.Task
  @app :shroud
  alias Shroud.Repo
  import Ecto.Query
  alias Shroud.Aliases.EmailAlias

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(@app)

    from(ea in EmailAlias, where: not is_nil(ea.deleted_at) and not is_nil(ea.domain_id))
    |> Repo.delete_all()
  end
end

defmodule Shroud.Mcp.ResourceOwners do
  @moduledoc "Boruta's account adapter; browser authentication stays with Shroud."
  @behaviour Boruta.Oauth.ResourceOwners
  alias Shroud.{Accounts, Mcp, Repo}

  @impl true
  def get_by(sub: sub) do
    with {id, ""} <- Integer.parse(sub),
         %Accounts.User{confirmed_at: confirmed} <- Repo.get(Accounts.User, id),
         true <- not is_nil(confirmed) do
      {:ok, %Boruta.Oauth.ResourceOwner{sub: sub}}
    else
      _ -> {:error, "Account unavailable"}
    end
  end

  def get_by(_params), do: {:error, "Browser sign-in required"}

  @impl true
  def check_password(_owner, _password), do: {:error, "Browser sign-in required"}

  @impl true
  def authorized_scopes(_owner) do
    Enum.map(Mcp.permissions(), fn {name, _} -> %Boruta.Oauth.Scope{name: name} end)
  end
end

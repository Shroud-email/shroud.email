defmodule ShroudWeb.Api.V1.TokenJSON do
  def render("token.json", %{token: token}) do
    %{token: token}
  end
end

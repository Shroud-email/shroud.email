defmodule ShroudWeb.Api.V1.TokenView do
  use ShroudWeb, :view

  def render("token.json", %{token: token}) do
    %{token: token}
  end

  # def render("error.json", %{error: error}) do
  #   %{error: error}
  # end
end

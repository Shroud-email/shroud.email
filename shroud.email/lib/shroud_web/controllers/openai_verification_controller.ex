defmodule ShroudWeb.OpenaiVerificationController do
  use ShroudWeb, :controller

  def show(conn, _params) do
    case Application.get_env(:shroud, :openai_apps_challenge) do
      token when is_binary(token) and token != "" -> text(conn, token)
      _ -> conn |> put_status(404) |> text("Not found")
    end
  end
end

defmodule ShroudWeb.ErrorJSON do
  def render("error.json", %{error: error}) do
    %{error: error}
  end

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

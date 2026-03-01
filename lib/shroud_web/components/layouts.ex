defmodule ShroudWeb.Layouts do
  use ShroudWeb, :html

  def active_class(conn, path, default_class, active_class \\ "active") do
    if path == Phoenix.Controller.current_path(conn) do
      default_class <> " " <> active_class
    else
      default_class
    end
  end

  embed_templates("layouts/*")
end

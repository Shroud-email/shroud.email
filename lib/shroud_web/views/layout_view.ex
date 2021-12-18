defmodule ShroudWeb.LayoutView do
  use ShroudWeb, :view

  # Phoenix LiveDashboard is available only in development by default,
  # so we instruct Elixir to not warn if the dashboard route is missing.
  @compile {:no_warn_undefined, {Routes, :live_dashboard_path, 2}}

  def active_class(conn, path, default_class, active_class \\ "active") do
    if path == Phoenix.Controller.current_path(conn) do
      default_class <> " " <> active_class
    else
      default_class
    end
  end
end

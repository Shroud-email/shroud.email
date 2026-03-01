defmodule ShroudWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels and so on.

  This can be used in your application as:

      use ShroudWeb, :controller
      use ShroudWeb, :html

  The definitions below will be executed for every
  controller, component, etc, so keep them short and clean,
  focused on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
      use Gettext, backend: ShroudWeb.Gettext

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      use PhoenixHTMLHelpers

      alias Phoenix.Flash

      import ShroudWeb.ErrorHelpers
      import ShroudWeb.Components.Atoms

      use Gettext, backend: ShroudWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view(opts \\ []) do
    quote do
      @opts Keyword.merge(
              [
                layout: {ShroudWeb.Layouts, :live}
              ],
              unquote(opts)
            )
      use Phoenix.LiveView, @opts

      on_mount(ShroudWeb.UserLiveAuth)
      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def component do
    quote do
      use Phoenix.Component, global_prefixes: ~w(x-)

      unquote(view_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      use Gettext, backend: ShroudWeb.Gettext
    end
  end

  defp view_helpers do
    quote do
      import Phoenix.HTML
      use PhoenixHTMLHelpers

      import Phoenix.Component

      alias Phoenix.Flash

      import ShroudWeb.ErrorHelpers
      use Gettext, backend: ShroudWeb.Gettext

      import ShroudWeb.Components.Atoms

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ShroudWeb.Endpoint,
        router: ShroudWeb.Router,
        statics: ShroudWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

defmodule ShroudWeb.Components.Cap do
  @moduledoc """
  Renders the Cap CAPTCHA widget.

  Renders nothing when Cap is disabled (any CAP_* env var unset), which
  keeps the integration optional for self-hosters.

  The widget JS is bundled into the main `app.js` esbuild bundle (a
  side-effect import in `assets/js/app.js` self-registers the
  `<cap-widget>` custom element); its version is pinned in
  `assets/package.json`. The `<cap-widget>` element injects its own hidden
  `cap-token` input into the surrounding form.
  """

  use Phoenix.Component

  alias Shroud.Captcha

  attr(:class, :string, default: nil)

  def cap_widget(assigns) do
    if Captcha.enabled?() do
      ~H"""
      <div
        class={["cap-widget-wrapper w-full mb-2", @class]}
        style="--cap-widget-width: 100%"
      >
        <cap-widget
          data-cap-api-endpoint={Captcha.widget_endpoint()}
          class="block w-full"
        >
        </cap-widget>
      </div>
      """
    else
      ~H""
    end
  end
end

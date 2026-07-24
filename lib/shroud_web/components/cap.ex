defmodule ShroudWeb.Components.Cap do
  @moduledoc """
  Renders the Cap CAPTCHA widget.

  Renders nothing when Cap is disabled (any CAP_* env var unset), which
  keeps the integration optional for self-hosters.

  The widget script is pinned to a specific version (per Cap's "pin the
  version" guidance) and loaded once. The `<cap-widget>` custom element
  injects its own hidden `cap-token` input into the surrounding form.
  """

  use Phoenix.Component

  alias Shroud.Captcha

  attr(:class, :string, default: nil)

  def cap_widget(assigns) do
    if Captcha.enabled?() do
      ~H"""
      <div
        class={["cap-widget-wrapper w-full mb-2", @class]}
        style={"--cap-widget-width: 100%"}
      >
        <script src={widget_script_url()}>
        </script>
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

  # Pinned per Cap integration guide ("common failure: version unpinned").
  defp widget_script_url,
    do: "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.56"
end

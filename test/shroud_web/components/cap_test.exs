defmodule ShroudWeb.Components.CapTest do
  # Mutates global Application env (cap_*) that other tests read via
  # Captcha.enabled?/0, so it must run serially to stay isolation-safe.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest
  alias ShroudWeb.Components.Cap

  @endpoint_url "https://cap.example.com/abc-site-key/"

  setup do
    on_exit(fn ->
      [:cap_instance_url, :cap_site_key, :cap_secret_key]
      |> Enum.each(&Application.delete_env(:shroud, &1))
    end)

    :ok
  end

  defp disable_cap,
    do:
      [:cap_instance_url, :cap_site_key, :cap_secret_key]
      |> Enum.each(&Application.delete_env(:shroud, &1))

  defp enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com")
    Application.put_env(:shroud, :cap_site_key, "abc-site-key")
    Application.put_env(:shroud, :cap_secret_key, "secret")
  end

  test "renders nothing when Cap is disabled" do
    disable_cap()
    assert Shroud.Captcha.enabled?() == false
    html = render_component(&Cap.cap_widget/1, %{class: "mt-4"})
    assert html == ""
  end

  test "renders the widget element and the endpoint when enabled" do
    enable_cap()
    html = render_component(&Cap.cap_widget/1, %{class: "mt-4"})

    assert html =~ ~s(data-cap-api-endpoint="#{@endpoint_url}")
    assert html =~ ~s(<cap-widget)
    assert html =~ "cap-widget-wrapper"
    assert html =~ "mt-4"

    # The widget JS is bundled via app.js, not loaded from a CDN, so the
    # rendered markup must never reference the CDN or emit a <script> tag.
    refute html =~ "cdn.jsdelivr.net"
    refute html =~ "<script"
  end
end

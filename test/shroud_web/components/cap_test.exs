defmodule ShroudWeb.Components.CapTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias ShroudWeb.Components.Cap

  @pinned "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.56"
  @endpoint_url "https://cap.example.com/abc-site-key/"

  setup do
    prev = Application.get_all_env(:shroud)

    on_exit(fn ->
      # restore by deleting keys we set, then re-applying originals
      [:cap_instance_url, :cap_site_key, :cap_secret_key]
      |> Enum.each(&Application.delete_env(:shroud, &1))

      for {k, v} <- prev, is_map(v) do
        for {kk, vv} <- v,
            do: Application.put_env(:shroud, k, Map.put(prev[k] || %{}, kk, vv), persistent: true)
      end
    end)

    :ok
  end

  defp disable_cap,
    do:
      [:cap_instance_url, :cap_site_key, :cap_secret_key]
      |> Enum.each(&Application.delete_env(:shroud, &1))

  defp enable_cap do
    Application.put_env(:shroud, :cap_instance_url, "https://cap.example.com", persistent: true)
    Application.put_env(:shroud, :cap_site_key, "abc-site-key", persistent: true)
    Application.put_env(:shroud, :cap_secret_key, "secret", persistent: true)
  end

  test "renders nothing when Cap is disabled" do
    disable_cap()
    assert Shroud.Captcha.enabled?() == false
    html = render_component(&Cap.cap_widget/1, %{class: "mt-4"})
    assert html == ""
  end

  test "renders the pinned widget script and the endpoint when enabled" do
    enable_cap()
    html = render_component(&Cap.cap_widget/1, %{class: "mt-4"})

    assert html =~ ~s(src="#{@pinned}")
    assert html =~ ~s(data-cap-api-endpoint="#{@endpoint_url}")
    assert html =~ ~s(<cap-widget)
    assert html =~ "cap-widget-wrapper"
    assert html =~ "mt-4"
  end
end

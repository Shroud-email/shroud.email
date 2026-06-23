defmodule ShroudWeb.Components.CopyToClipboardButtonTest do
  use ShroudWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ShroudWeb.Components.CopyToClipboardButton

  defp render_button(text) do
    assigns = %{text: text, class: ""}

    render_component(&copy_to_clipboard_button/1, assigns)
  end

  test "renders the text in a data attribute" do
    html = render_button("hello@example.com")

    assert html =~ ~s(data-clipboard-text="hello@example.com")
    # The click handler reads from the data attribute, never interpolates the value.
    assert html =~ "$el.dataset.clipboardText"
  end

  test "does not interpolate the value into the JS click handler" do
    html = render_button("alice's alias")

    # The raw value must never appear inside the x-on:click handler.
    refute html =~ "writeText('alice's alias')"
  end

  test "escapes a single quote so the markup is not broken" do
    html = render_button("alice's alias")

    # HEEx HTML-escapes the attribute, so the value lands safely in the data attribute.
    assert html =~ "data-clipboard-text=\"alice&#39;s alias\""
  end

  test "escapes script-injection content" do
    html = render_button("</script><script>alert(1)</script>")

    refute html =~ "<script>alert(1)</script>"
    assert html =~ "&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;"
  end
end

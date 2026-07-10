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

  test "escapes script-injection content" do
    html = render_button("</script><script>alert(1)</script>")

    refute html =~ "<script>alert(1)</script>"
  end
end

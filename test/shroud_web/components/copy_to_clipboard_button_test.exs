defmodule ShroudWeb.Components.CopyToClipboardButtonTest do
  use ShroudWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ShroudWeb.Components.CopyToClipboardButton

  defp render_button(text, attrs \\ %{}) do
    assigns = Map.merge(%{text: text}, attrs)

    render_component(&copy_to_clipboard_button/1, assigns)
  end

  test "renders the text in a data attribute" do
    html = render_button("hello@example.com")

    assert html =~ ~s(data-clipboard-text="hello@example.com")
    # The click handler reads from the data attribute, never interpolates the value.
    assert html =~ "$el.dataset.clipboardText"
  end

  test "renders an accessible label and optional id" do
    html = render_button("hello@example.com", %{id: "copy-alias-1"})

    assert html =~ ~s(id="copy-alias-1")
    assert html =~ ~s(aria-label="Copy hello@example.com to clipboard")
  end

  test "escapes script-injection content" do
    html = render_button("</script><script>alert(1)</script>")

    refute html =~ "<script>alert(1)</script>"
  end
end

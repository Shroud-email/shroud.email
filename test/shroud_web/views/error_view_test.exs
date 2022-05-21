defmodule ShroudWeb.ErrorViewTest do
  use ShroudWeb.ConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "renders 404.html" do
    rendered = render_to_string(ShroudWeb.ErrorView, "404.html", [])

    assert rendered =~ "404 error"
    assert rendered =~ "Lost in the fog"
  end

  test "renders 500.html" do
    rendered = render_to_string(ShroudWeb.ErrorView, "500.html", [])

    assert rendered =~ "500 error"
    assert rendered =~ "Something went wrong"
  end
end

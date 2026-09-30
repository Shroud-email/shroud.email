defmodule ShroudWeb.UserSettingsBillingTest do
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures

  alias Shroud.Accounts.User
  alias Shroud.Repo

  setup %{conn: conn} do
    user = user_fixture() |> User.confirm_changeset() |> Repo.update!()
    %{conn: log_in_user(conn, user)}
  end

  test "renders a disabled checkout when Paddle.js configuration is incomplete", %{conn: conn} do
    original = Application.fetch_env!(:shroud, :billing)

    Application.put_env(
      :shroud,
      :billing,
      Keyword.merge(original, paddle_client_token: nil, paddle_yearly_price_id: nil)
    )

    on_exit(fn -> Application.put_env(:shroud, :billing, original) end)

    html = conn |> get(~p"/settings/billing") |> html_response(200)
    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query("#upgrade-button[disabled]") |> Enum.any?()
    refute document |> LazyHTML.query("#upgrade-button[data-paddle-checkout]") |> Enum.any?()
  end

  test "renders a disabled checkout launcher without mutable customer email", %{conn: conn} do
    html = conn |> get(~p"/settings/billing") |> html_response(200)
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#upgrade-button[disabled][data-paddle-checkout]")
           |> Enum.any?()

    refute document |> LazyHTML.query("#upgrade-button[data-customer-email]") |> Enum.any?()
  end

  test "renders a Paddle price preview target instead of a hard-coded currency", %{conn: conn} do
    html = conn |> get(~p"/settings/billing") |> html_response(200)
    document = LazyHTML.from_fragment(html)

    price = LazyHTML.query(document, "#upgrade-price[data-paddle-price-id='pri_test_yearly']")

    assert Enum.any?(price)
    assert LazyHTML.text(price) =~ "Loading price"

    refute html =~ "$35"
    refute html =~ "USD"
  end
end

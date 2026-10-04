defmodule ShroudWeb.Components.ButtonTest do
  use ExUnit.Case, async: true
  use Phoenix.Component, global_prefixes: ~w(x-)

  import Phoenix.LiveViewTest
  import ShroudWeb.Components.Atoms, only: [button: 1]

  test "preserves submit values and disabled state" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.button id="allow" type="submit" name="decision" value="allow" text="Connect" />
      <.button
        id="deny"
        type="submit"
        name="decision"
        value="deny"
        intent={:white}
        disabled={true}
        text="Cancel"
      />
      """)

    document = Floki.parse_fragment!(html)

    assert [_] =
             Floki.find(
               document,
               "#allow[type=submit][name=decision][value=allow]:not([disabled])"
             )

    assert [_] = Floki.find(document, "#deny[type=submit][name=decision][value=deny][disabled]")
  end

  test "preserves Alpine, LiveView and icon-only content" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.button
        id="action"
        click="block_sender"
        phx-value-sender="sender@example.com"
        phx-disable-with="Blocking…"
        alpine_click="editing = true"
        x-show="!editing"
        intent={:white}
        size={:icon}
      >
        <span class="sr-only">Block sender</span>
        <svg aria-hidden="true"></svg>
      </.button>
      """)

    document = Floki.parse_fragment!(html)
    [button] = Floki.find(document, "#action.p-2[type=button]")
    assert Floki.attribute(button, "phx-click") == ["block_sender"]
    assert Floki.attribute(button, "phx-value-sender") == ["sender@example.com"]
    assert Floki.attribute(button, "phx-disable-with") == ["Blocking…"]
    assert Floki.attribute(button, "@click") == ["editing = true"]
    assert Floki.attribute(button, "x-show") == ["!editing"]
    assert Floki.text(Floki.find(button, ".sr-only")) == "Block sender"
    assert [_] = Floki.find(button, "svg[aria-hidden=true]")
  end

  test "navigation actions remain links, including LiveView patches" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.button id="billing" href="/checkout/billing" text="Billing" />
      <.button id="connections" patch="/settings/connections" intent={:white} text="Connections" />
      <.button id="aliases" navigate="/" text="Aliases" />
      """)

    document = Floki.parse_fragment!(html)
    assert [_] = Floki.find(document, "a#billing[href='/checkout/billing']")

    assert [_] =
             Floki.find(
               document,
               "a#connections[href='/settings/connections'][data-phx-link=patch]"
             )

    assert [_] = Floki.find(document, "a#aliases[href='/'][data-phx-link=redirect]")
    assert [] = Floki.find(document, "button")
  end
end

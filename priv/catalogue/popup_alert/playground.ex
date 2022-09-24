defmodule ShroudWeb.Catalogue.PopupAlert.Example do
  use Surface.Catalogue.Playground,
    subject: ShroudWeb.Components.PopupAlert,
    height: "300px"
  alias ShroudWeb.Components.Button

  @props [
      show: false,
      id: "modal",
      title: "My modal",
      text: "Lorem ipsum dolor sit amet",
      icon: Heroicons.Outline.GlobeAltIcon
  ]

  def render(assigns) do
    ~F"""
    <PopupAlert :props={@props}>
      <:buttons>
        <Button text="Close" icon={Heroicons.Outline.XIcon} />
      </:buttons>
    </PopupAlert>
    """
  end
end

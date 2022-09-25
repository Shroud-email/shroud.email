defmodule ShroudWeb.Api.V1.EmailAliasView do
  use ShroudWeb, :view

  def render("index.json", %{
        email_aliases: email_aliases,
        page_number: page_number,
        page_size: page_size,
        total_pages: total_pages,
        total_entries: total_entries
      }) do
    %{
      email_aliases: render_many(email_aliases, __MODULE__, "email_alias.json", as: :data),
      page_number: page_number,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  def render("email_alias.json", %{data: data}) do
    %{
      address: data.address,
      enabled: data.enabled,
      title: data.title,
      notes: data.notes,
      forwarded: data.forwarded,
      blocked: data.blocked,
      blocked_addresses: data.blocked_addresses
    }
  end
end

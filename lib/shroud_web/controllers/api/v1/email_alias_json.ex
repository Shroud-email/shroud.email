defmodule ShroudWeb.Api.V1.EmailAliasJSON do
  def render("index.json", %{
        email_aliases: email_aliases,
        page_number: page_number,
        page_size: page_size,
        total_pages: total_pages,
        total_entries: total_entries
      }) do
    %{
      email_aliases: Enum.map(email_aliases, &data/1),
      page_number: page_number,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  def render("email_alias.json", %{data: data}) do
    data(data)
  end

  defp data(email_alias) do
    %{
      address: email_alias.address,
      enabled: email_alias.enabled,
      title: email_alias.title,
      notes: email_alias.notes,
      forwarded: email_alias.forwarded,
      blocked: email_alias.blocked,
      blocked_addresses: email_alias.blocked_addresses
    }
  end
end

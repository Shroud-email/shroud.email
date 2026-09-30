defmodule ShroudWeb.Api.V1.DomainJSON do
  def render("index.json", %{
        domains: domains,
        page_number: page_number,
        page_size: page_size,
        total_pages: total_pages,
        total_entries: total_entries
      }) do
    %{
      domains: Enum.map(domains, &data/1),
      page_number: page_number,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  def render("domain.json", %{data: data}) do
    data(data)
  end

  defp data(domain) do
    %{"domain" => domain.domain}
  end
end

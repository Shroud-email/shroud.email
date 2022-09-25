defmodule ShroudWeb.Api.V1.DomainView do
  use ShroudWeb, :view

  def render("index.json", %{
        domains: domains,
        page_number: page_number,
        page_size: page_size,
        total_pages: total_pages,
        total_entries: total_entries
      }) do
    %{
      domains: render_many(domains, __MODULE__, "domain.json", as: :data),
      page_number: page_number,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  def render("domain.json", %{data: data}) do
    %{
      "domain" => data.domain
    }
  end
end

defmodule Shroud.Email.EnricherTest do
  use ExUnit.Case, async: true
  use ShroudWeb, :verified_routes

  alias Shroud.Util
  alias Shroud.Email.{Enricher, ParsedEmail}

  defp build_email(removed_trackers) do
    html = "<html><body><p>hi</p></body></html>"
    {:ok, parsed_html} = Floki.parse_document(html)
    swoosh = Swoosh.Email.new(from: {"", "sender@example.com"}, html_body: html)

    %ParsedEmail{
      to: "alias@shroud.test",
      from: "sender@example.com",
      swoosh_email: swoosh,
      parsed_html: parsed_html,
      removed_trackers: removed_trackers
    }
  end

  test "uses the friendly tracker name in the report, falling back to the domain" do
    email =
      build_email([
        %{name: "MailChimp", domain: "list-manage.com"},
        %{name: nil, domain: "unknowntracker.com"}
      ])

    result = Enricher.process(email)

    expected_data =
      %{
        sender: "sender@example.com",
        email_alias: "alias@shroud.test",
        trackers: ["MailChimp", "unknowntracker.com"]
      }
      |> Util.uri_encode_map!()

    expected_url = ShroudWeb.Endpoint.url() <> ~p"/email-report/#{expected_data}"

    assert result.swoosh_email.html_body =~ expected_url
    assert result.swoosh_email.html_body =~ "removed 2 trackers."
  end

  test "deduplicates repeated labels in the report" do
    email =
      build_email([
        %{name: "Mailgun", domain: "a.example.com"},
        %{name: "Mailgun", domain: "b.example.com"}
      ])

    result = Enricher.process(email)

    assert result.swoosh_email.html_body =~ "removed 1 tracker."
  end
end

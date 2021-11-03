defmodule Shroud.Swoosh.Adapters.OhMySmtp do
  @moduledoc ~S"""
  An adapter that sends email using the OhMySMTP API.

  For reference: [OhMySMTP API docs](https://docs.ohmysmtp.com/reference/overview)

  ## Example

      # config/config.exs
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.OhMySmtp,
        api_key: "my-api-key"

      # lib/sample/mailer.ex
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end
  """

  use Swoosh.Adapter, required_config: [:api_key]

  alias Swoosh.Email
  import Swoosh.Email.Render

  @api_endpoint "https://app.ohmysmtp.com/api/v1/send"

  @impl true
  def deliver(%Email{} = email, config \\ []) do
    headers = prepare_headers(config)
    params = email |> prepare_body() |> Swoosh.json_library().encode!

    case Swoosh.ApiClient.post(@api_endpoint, headers, params, email) do
      {:ok, 200, _headers, body} ->
        {:ok, %{id: Swoosh.json_library().decode!(body)["id"]}}

      {:ok, code, _headers, body} when code > 399 ->
        case Swoosh.json_library().decode(body) do
          {:ok, error} -> {:error, {code, error}}
          {:error, _} -> {:error, {code, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # TODO: implement deliver_many
  @impl true
  def deliver_many(_emails, _config \\ []) do
    raise "Not implemented"
  end

  # def deliver_many([], _config) do
  #   {:ok, []}
  # end

  defp prepare_headers(config) do
    [
      {"User-Agent", "swoosh/#{Swoosh.version()}"},
      {"OhMySMTP-Server-Token", config[:api_key]},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp prepare_body(email) do
    %{}
    |> prepare_from(email)
    |> prepare_to(email)
    |> prepare_subject(email)
    |> prepare_html(email)
    |> prepare_text(email)
    |> prepare_cc(email)
    |> prepare_bcc(email)
    |> prepare_reply_to(email)
    |> prepare_tags(email)
  end

  defp prepare_from(body, %{from: from}), do: Map.put(body, "from", render_recipient(from))

  defp prepare_to(body, %{to: to}), do: Map.put(body, "to", render_recipient(to))

  defp prepare_cc(body, %{cc: []}), do: body
  defp prepare_cc(body, %{cc: cc}), do: Map.put(body, "cc", render_address(cc))

  defp prepare_bcc(body, %{bcc: []}), do: body
  defp prepare_bcc(body, %{bcc: bcc}), do: Map.put(body, "bcc", render_address(bcc))

  # TODO: handle attachments

  defp prepare_reply_to(body, %{reply_to: nil}), do: body

  defp prepare_reply_to(body, %{reply_to: {_name, address}}),
    do: Map.put(body, "replyto", address)

  defp prepare_subject(body, %{subject: ""}), do: body
  defp prepare_subject(body, %{subject: subject}), do: Map.put(body, "subject", subject)

  defp prepare_text(body, %{text_body: nil}), do: body
  defp prepare_text(body, %{text_body: text_body}), do: Map.put(body, "textbody", text_body)

  defp prepare_html(body, %{html_body: nil}), do: body
  defp prepare_html(body, %{html_body: html_body}), do: Map.put(body, "htmlbody", html_body)

  defp prepare_tags(body, %{provider_options: %{tags: tags}}) do
    Map.put(body, "tags", tags)
  end

  defp prepare_tags(body, _), do: body

  defp render_address(nil), do: ""
  defp render_address({nil, address}), do: address
  defp render_address({"", address}), do: address
  defp render_address({_name, address}), do: address
  defp render_address([]), do: ""
end

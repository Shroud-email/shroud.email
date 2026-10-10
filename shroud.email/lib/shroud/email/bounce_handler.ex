defmodule Shroud.Email.BounceHandler do
  @moduledoc """
  Handles various kinds of bounces.
  """
  require Logger
  alias Shroud.Accounts
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Email.DeliveryMarker
  alias Shroud.RateLimit
  alias Shroud.S3.S3UploadJob

  @doc """
  Handles delivery reports using authenticated context returned in message headers.
  Archives reports to S3 and includes the object path in Sentry alerts.
  """
  @spec handle_haraka_bounce_report(String.t(), String.t()) :: :ok
  def handle_haraka_bounce_report(to, data) do
    s3_path = "/bounces/#{to}-#{date_time().utc_now_unix()}.eml"

    %{path: s3_path, content: data}
    |> S3UploadJob.new()
    |> Oban.insert!()

    Logger.warning("Received bounce report from Haraka! See #{s3_path}.")

    case parse_report(to, data) do
      {:ok, %{action: "failed"} = report} ->
        handle_failure(to, Map.put(report, :s3_path, s3_path))

      {:ok, _report} ->
        :ok

      :error ->
        report_unclassified(s3_path)
    end
  end

  def delivery_status_report?(data) do
    headers = data |> String.split(~r/\r?\n\r?\n/, parts: 2) |> hd()

    try do
      case Mailex.parse(headers <> "\r\n\r\n") do
        {:ok, message} -> delivery_status_mime?(message)
        _ -> false
      end
    rescue
      _exception -> Regex.match?(~r/^content-type:\s*multipart\/report(?:\s|;|$)/im, headers)
    end
  end

  defp parse_report(to, data) do
    with {:ok, message} <- Mailex.parse(data),
         true <- delivery_status_mime?(message),
         [_human, delivery_status, original] <- message.parts,
         %{content_type: %{type: "message", subtype: "delivery-status"}, body: body}
         when is_binary(body) <- delivery_status,
         {:ok, headers} <- original_headers(original),
         marker when is_binary(marker) <- headers["x-shroud-delivery"],
         {:ok, context} <- DeliveryMarker.verify(marker, to),
         {:ok, action, status} <- recipient_status(body, context.recipient) do
      subject = headers["subject"]

      subject =
        if is_binary(subject) and
             Base.encode64(:crypto.hash(:sha256, subject)) == context.subject_hash,
           do: subject,
           else: nil

      {:ok,
       Map.merge(context, %{marker: marker, action: action, status: status, subject: subject})}
    else
      _ -> :error
    end
  rescue
    _exception -> :error
  end

  defp delivery_status_mime?(%{
         content_type: %{type: "multipart", subtype: "report", params: params}
       }) do
    String.downcase(Map.get(params, "report-type", "")) == "delivery-status"
  end

  defp delivery_status_mime?(_message), do: false

  defp original_headers(%{
         content_type: %{type: "text", subtype: "rfc822-headers"},
         body: body
       })
       when is_binary(body) do
    with {:ok, message} <- Mailex.parse(body <> "\r\n\r\n"), do: {:ok, message.headers}
  end

  defp original_headers(%{
         content_type: %{type: "message", subtype: "rfc822"},
         parts: [%{headers: headers}]
       }),
       do: {:ok, headers}

  defp original_headers(_original), do: :error

  defp recipient_status(body, recipient) do
    matches =
      body
      |> String.split(~r/\r?\n\r?\n/, trim: true)
      |> Enum.flat_map(fn block ->
        with {:ok, message} <- Mailex.parse(block <> "\r\n\r\n"),
             value when is_binary(value) <- message.headers["final-recipient"],
             [type, address] <- String.split(value, ";", parts: 2),
             true <- String.downcase(String.trim(type)) == "rfc822",
             true <- String.trim(address) == recipient do
          [message.headers]
        else
          _ -> []
        end
      end)

    with [headers] <- matches,
         action when is_binary(action) <- headers["action"],
         action when action in ["failed", "delayed", "delivered", "relayed", "expanded"] <-
           String.downcase(action),
         status when is_binary(status) <- headers["status"] || generic_smtp_status(headers),
         [code] <- Regex.run(~r/\A[245]\.\d{1,3}\.\d{1,3}(?=\s|\z)/, status),
         true <- action != "failed" or String.starts_with?(code, ["4.", "5."]) do
      {:ok, action, code}
    else
      _ -> :error
    end
  end

  defp generic_smtp_status(headers) do
    case Regex.run(~r/\Asmtp;\s*([45])\d{2}(?=\s|\z)/i, headers["diagnostic-code"] || "") do
      [_, class] -> class <> ".0.0"
      _ -> nil
    end
  end

  defp handle_failure(to, report) do
    case Accounts.get_user_by_alias(to) do
      %{id: user_id} = user when user_id == report.user_id ->
        case report.direction do
          "incoming" ->
            report_event(
              "Failed to forward incoming email to a user's inbox",
              ["shroud-incoming-forwarding-bounce"],
              %{delivery_status: report.status},
              report.s3_path
            )

          "outgoing" ->
            notify_user(user, to, report)
        end

      _ ->
        report_unclassified(report.s3_path)
    end
  end

  defp notify_user(user, email_alias, report) do
    key = {:bounce_notification, :crypto.hash(:sha256, report.marker)}

    case RateLimit.hit(key, :timer.minutes(15), 1) do
      {:allow, _count} ->
        %{
          email_function: :deliver_outgoing_email_bounced,
          email_args: [
            user.id,
            email_alias,
            report.recipient,
            report.subject,
            failure_reason(report.status),
            report.status
          ]
        }
        |> UserNotifierJob.new()
        |> Oban.insert!()

        if String.starts_with?(report.status, ["4.", "5.4.", "5.7."]) do
          report_event(
            "Outgoing email rejected by routing or policy",
            ["shroud-outgoing-delivery-rejection"],
            %{delivery_status: report.status},
            report.s3_path
          )
        end

        :ok

      {:deny, _retry_after} ->
        :ok
    end
  end

  defp failure_reason(status) do
    cond do
      String.starts_with?(status, "5.1.") ->
        "The recipient's address was rejected."

      String.starts_with?(status, "5.2.") ->
        "The recipient's mailbox could not accept the email."

      String.starts_with?(status, "5.3.") ->
        "The recipient's mail system could not accept the email."

      String.starts_with?(status, ["4.", "5.4."]) ->
        "Delivery attempts ended without reaching the recipient."

      String.starts_with?(status, "5.7.") ->
        "The recipient's mail server rejected the email for policy or security reasons."

      true ->
        "The recipient's mail server reported a delivery failure."
    end
  end

  defp report_unclassified(s3_path) do
    report_event(
      "Received an unclassified email bounce report",
      ["shroud-unclassified-email-bounce"],
      %{},
      s3_path
    )
  end

  defp report_event(message, fingerprint, tags, s3_path) do
    event =
      Sentry.Event.create_event(
        message: message,
        level: :warning,
        fingerprint: fingerprint
      )

    # Allow only operational fields; inherited context can contain email data.
    %Sentry.Event{
      event_id: event.event_id,
      timestamp: event.timestamp,
      environment: event.environment,
      release: event.release,
      message: event.message,
      level: event.level,
      fingerprint: event.fingerprint,
      tags: tags,
      extra: %{s3_path: s3_path}
    }
    |> Sentry.send_event()

    :ok
  end

  defp date_time do
    Application.get_env(:shroud, :datetime_module, Shroud.DateTime)
  end
end

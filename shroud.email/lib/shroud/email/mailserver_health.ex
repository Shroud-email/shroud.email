defmodule Shroud.Email.MailserverHealth do
  @moduledoc "Read-only diagnostics for the configured mail domain."

  @max_mx 5
  @timeout 2_500

  def run do
    domain = Application.fetch_env!(:shroud, :email_domain)
    {dns_results, targets} = dns_checks(domain)

    public_results =
      targets
      |> Task.async_stream(&smtp_checks(&1, 25, :verified),
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(targets)
      |> Enum.flat_map(fn
        {{:ok, results}, _host} ->
          results

        {{:exit, _reason}, host} ->
          [
            row("SMTP #{host}:25", :unknown, "Probe timed out")
            | skipped_tls("#{host}:25", :verified)
          ]
      end)

    inbound_port = Application.fetch_env!(:shroud, :mailer)[:smtp_options][:port]
    relay = Application.get_env(:shroud, Shroud.Mailer, [])

    private_results =
      smtp_checks("localhost", inbound_port, :greeting) ++
        case relay[:adapter] do
          Swoosh.Adapters.SMTP ->
            mode =
              case relay[:tls] do
                :always -> :starttls
                :if_available -> :optional_starttls
                _ -> :greeting
              end

            smtp_checks(relay[:relay], relay[:port], mode)

          _ ->
            [row("Outbound relay", :unknown, "SMTP relay is not configured in this environment")]
        end

    %{checked_at: DateTime.utc_now(), results: dns_results ++ public_results ++ private_results}
  end

  @doc "Probe a configured SMTP endpoint without submitting mail or credentials."
  def smtp_checks(host, port, mode) do
    label = "#{host}:#{port}"
    deadline = System.monotonic_time(:millisecond) + @timeout

    case :gen_tcp.connect(
           to_charlist(host),
           port,
           [:binary, packet: :line, active: false, packet_size: 4096],
           @timeout
         ) do
      {:ok, socket} ->
        try do
          smtp_session(socket, label, host, mode, deadline)
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} ->
        [
          row("SMTP #{label}", :fail, "Connection failed: #{inspect(reason)}")
          | skipped_tls(label, mode)
        ]
    end
  end

  defp smtp_session(socket, label, host, mode, deadline) do
    case response(socket, "220", deadline) do
      {:ok, greeting} ->
        smtp_result = row("SMTP #{label}", :pass, String.trim(greeting))

        if mode == :greeting do
          [smtp_result]
        else
          [smtp_result | starttls_checks(socket, label, host, mode, deadline)]
        end

      {:error, reason} ->
        [
          row("SMTP #{label}", :fail, "Invalid greeting: #{inspect(reason)}")
          | skipped_tls(label, mode)
        ]
    end
  end

  defp starttls_checks(socket, label, host, mode, deadline) do
    with :ok <- :gen_tcp.send(socket, "EHLO shroud.email\r\n"),
         {:ok, lines} <- response(socket, "250", deadline),
         true <- Regex.match?(~r/(?:^|\n)250[ -]STARTTLS\b/i, lines) do
      starttls(socket, label, host, mode, deadline)
    else
      false ->
        [
          tls_unavailable(label, mode, "Not advertised by EHLO")
          | skipped_certificate(label, mode)
        ]

      {:error, reason} ->
        [
          row("STARTTLS #{label}", :fail, "EHLO failed: #{inspect(reason)}")
          | skipped_certificate(label, mode)
        ]
    end
  end

  defp starttls(socket, label, host, mode, deadline) do
    with :ok <- :gen_tcp.send(socket, "STARTTLS\r\n"),
         {:ok, _} <- response(socket, "220", deadline) do
      tls_options =
        if mode == :verified do
          [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            server_name_indication: to_charlist(host)
          ]
        else
          [verify: :verify_none]
        end

      # A line-oriented TCP socket must become raw before TLS takes ownership.
      with :ok <- :inet.setopts(socket, packet: :raw),
           {:ok, tls_socket} <-
             :ssl.connect(socket, [active: false] ++ tls_options, remaining(deadline)) do
        :ssl.close(tls_socket)

        [
          row("STARTTLS #{label}", :pass, "TLS handshake succeeded")
          | certificate_success(label, mode)
        ]
      else
        {:error, reason} ->
          [
            tls_unavailable(label, mode, "TLS handshake failed: #{inspect(reason)}")
            | certificate_failure(label, mode, reason)
          ]
      end
    else
      {:error, reason} ->
        [
          tls_unavailable(label, mode, "Upgrade rejected: #{inspect(reason)}")
          | skipped_certificate(label, mode)
        ]
    end
  end

  defp tls_unavailable(label, :optional_starttls, detail),
    do: row("STARTTLS #{label}", :unknown, "#{detail}; configured to permit plaintext fallback")

  defp tls_unavailable(label, _mode, detail), do: row("STARTTLS #{label}", :fail, detail)

  defp certificate_success(label, :verified),
    do: [row("Certificate #{label}", :pass, "Trusted chain, hostname and validity verified")]

  defp certificate_success(_label, _mode), do: []

  defp certificate_failure(label, :verified, reason),
    do: [row("Certificate #{label}", :fail, "Verification failed: #{inspect(reason)}")]

  defp certificate_failure(_label, _mode, _reason), do: []

  defp skipped_tls(_label, :greeting), do: []

  defp skipped_tls(label, mode),
    do: [
      row("STARTTLS #{label}", :unknown, "SMTP greeting unavailable")
      | skipped_certificate(label, mode)
    ]

  defp skipped_certificate(label, :verified),
    do: [row("Certificate #{label}", :unknown, "STARTTLS unavailable")]

  defp skipped_certificate(_label, _mode), do: []

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp response(socket, expected, deadline), do: response(socket, expected, deadline, [], 0)

  defp response(_socket, _expected, _deadline, _lines, 30), do: {:error, :too_many_lines}

  defp response(socket, expected, deadline, lines, count) do
    case :gen_tcp.recv(socket, 0, remaining(deadline)) do
      {:ok, <<code::binary-size(3), ?-, _::binary>> = line} when code == expected ->
        response(socket, expected, deadline, [String.trim(line) | lines], count + 1)

      {:ok, <<code::binary-size(3), ?\s, _::binary>> = line} when code == expected ->
        {:ok, Enum.reverse([String.trim(line) | lines]) |> Enum.join("\n")}

      {:ok, line} ->
        {:error, {:unexpected_response, String.trim(line)}}

      error ->
        error
    end
  end

  def dns_checks(domain, lookup \\ &resolve/2) do
    {mx_result, targets} =
      case lookup.(domain, :mx) do
        {:ok, records} ->
          all_targets =
            records
            |> Enum.filter(fn {priority, host} -> is_integer(priority) and is_list(host) end)
            |> Enum.sort()
            |> Enum.map(fn {_priority, host} ->
              host |> to_string() |> String.trim_trailing(".")
            end)
            |> Enum.reject(&(&1 == ""))
            |> Enum.uniq()

          targets = Enum.take(all_targets, @max_mx)

          result =
            cond do
              targets == [] ->
                row("MX", :fail, "No usable MX records for #{domain}")

              length(all_targets) > @max_mx ->
                row(
                  "MX",
                  :unknown,
                  "#{Enum.join(targets, ", ")}; #{length(all_targets) - @max_mx} not probed"
                )

              true ->
                row("MX", :pass, Enum.join(targets, ", "))
            end

          {result, targets}

        {:error, reason} ->
          {row("MX", :unknown, "DNS lookup failed: #{inspect(reason)}"), []}
      end

    addresses = Enum.map(targets, &address_check(&1, lookup))

    {[
       mx_result | addresses
     ] ++
       [
         policy_check("SPF", domain, lookup),
         policy_check("DKIM", "shroudemail._domainkey.#{domain}", lookup),
         policy_check("DMARC", "_dmarc.#{domain}", lookup)
       ], targets}
  end

  defp address_check(host, lookup) do
    records = [lookup.(host, :a), lookup.(host, :aaaa)]

    addresses =
      for {:ok, values} <- records,
          value <- values,
          is_tuple(value),
          address = :inet.ntoa(value),
          is_list(address),
          do: to_string(address)

    cond do
      addresses != [] ->
        row("MX #{host} A/AAAA", :pass, Enum.join(addresses, ", "))

      Enum.all?(records, &match?({:ok, _}, &1)) ->
        row("MX #{host} A/AAAA", :fail, "No IP addresses")

      true ->
        row("MX #{host} A/AAAA", :unknown, "Address lookup failed: #{inspect(records)}")
    end
  end

  defp policy_check(name, domain, lookup) do
    case lookup.(domain, :txt) do
      {:ok, records} ->
        policies =
          Enum.map(records, fn record -> Enum.map_join(record, &to_string/1) end)

        version = %{"SPF" => "v=spf1", "DKIM" => "v=DKIM1", "DMARC" => "v=DMARC1"}[name]
        matching = Enum.filter(policies, &String.starts_with?(&1, version))
        policy_result(name, domain, matching)

      {:error, reason} ->
        row(name, :unknown, "DNS lookup failed: #{inspect(reason)}")
    end
  end

  defp policy_result(name, domain, [policy]) do
    if valid_policy?(name, policy) do
      row(name, :pass, policy)
    else
      detail =
        if name == "SPF",
          do: "Invalid SPF policy or no sender authorization at #{domain}: #{policy}",
          else: "Invalid #{name} record at #{domain}"

      row(name, :fail, detail)
    end
  end

  defp policy_result(name, domain, []), do: row(name, :fail, "No #{name} record at #{domain}")

  defp policy_result(name, domain, _),
    do: row(name, :fail, "Multiple #{name} records at #{domain}")

  defp valid_policy?("SPF", value) do
    [version | terms] = String.split(value)

    String.downcase(version) == "v=spf1" and Enum.all?(terms, &valid_spf_term?/1) and
      Regex.match?(
        ~r/(?:^|\s)(?:[+?~\-]?(?:mx|a)(?![a-z])|[+?~\-]?(?:ip4:|ip6:|include:|exists:)|redirect=)/i,
        value
      )
  end

  defp valid_policy?("DMARC", value),
    do: Regex.match?(~r/^v=DMARC1;.*\bp=(none|quarantine|reject)(?:;|$)/i, value)

  defp valid_policy?("DKIM", value) do
    with [_, key] <- Regex.run(~r/^v=DKIM1;.*\bp=([A-Za-z0-9+\/=]+)(?:;|$)/i, value),
         {:ok, decoded} <- Base.decode64(key) do
      try do
        match?(
          {:SubjectPublicKeyInfo, _, _},
          :public_key.der_decode(:SubjectPublicKeyInfo, decoded)
        )
      rescue
        _ -> false
      end
    else
      _ -> false
    end
  end

  defp valid_spf_term?(term) do
    mechanism = term |> String.replace(~r/^[+?~\-]/, "") |> String.downcase()

    cond do
      mechanism in ["all", "a", "mx", "ptr"] ->
        true

      String.starts_with?(mechanism, ["ip4:", "ip6:"]) ->
        [kind, address] = String.split(mechanism, ":", parts: 2)
        valid_spf_address?(kind, address)

      String.starts_with?(mechanism, ["a:", "a/", "mx:", "mx/"]) ->
        Regex.match?(
          ~r/^(?:a|mx)(?::[^\s\/]+)?(?:\/(?:[0-9]|[12][0-9]|3[0-2]))?(?:\/\/(?:[0-9]|[1-9][0-9]|1[01][0-9]|12[0-8]))?$/,
          mechanism
        )

      true ->
        Regex.match?(~r/^(?:include:|exists:|ptr:|redirect=|exp=)[^\s\/]+$/, mechanism) or
          (Regex.match?(~r/^[a-z][a-z0-9_.-]*=[^\s]+$/, mechanism) and
             not String.starts_with?(mechanism, ["redirect=", "exp="]))
    end
  end

  defp valid_spf_address?(kind, address) do
    [ip | cidr] = String.split(address, "/")
    size = if kind == "ip4", do: 4, else: 8
    max_prefix = if kind == "ip4", do: 32, else: 128

    case :inet.parse_strict_address(to_charlist(ip)) do
      {:ok, tuple} -> tuple_size(tuple) == size and valid_spf_prefix?(cidr, max_prefix)
      _ -> false
    end
  end

  defp valid_spf_prefix?([], _max), do: true

  defp valid_spf_prefix?([prefix], max) do
    case Integer.parse(prefix) do
      {number, ""} -> number >= 0 and number <= max
      _ -> false
    end
  end

  defp valid_spf_prefix?(_prefixes, _max), do: false

  defp resolve(domain, type) do
    case :inet_res.resolve(to_charlist(domain), :in, type, timeout: @timeout, retry: 1) do
      {:ok, message} ->
        {:ok,
         message
         |> :inet_dns.msg(:anlist)
         |> Enum.filter(&(:inet_dns.rr(&1, :type) == type))
         |> Enum.map(&:inet_dns.rr(&1, :data))}

      {:error, :nxdomain} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp row(name, status, detail), do: %{name: name, status: status, detail: detail}
end

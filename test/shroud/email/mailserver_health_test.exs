defmodule Shroud.Email.MailserverHealthTest do
  use ExUnit.Case, async: true

  alias Shroud.Email.MailserverHealth

  @public_key "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC6df2FKTlPQDg3O4eoccdfQx61gHlHTI9N//jzXzEZshXhdRkiZL4gUWduxZb7Rk8++31cYgPCJXJrlHeFnnGlBIdc9nGvi6APS3ZjXkxLo6RaaxmmfFliR1XhvvhqzD5MqbA8pKwsvD93FsyLfmlKesZRouevRhpMuyWzgqQiswIDAQAB"

  test "reports each MX address and rejects malformed authentication records" do
    dns = fn
      "email.shroud.test", :mx ->
        {:ok, [{10, ~c"mx1.example"}, {20, ~c"mx2.example"}]}

      "mx1.example", :a ->
        {:ok, [{192, 0, 2, 1}]}

      "mx1.example", :aaaa ->
        {:ok, []}

      "mx2.example", :a ->
        {:ok, []}

      "mx2.example", :aaaa ->
        {:ok, []}

      "email.shroud.test", :txt ->
        {:ok, [[~c"v=spf1 mx ", ~c"-all"]]}

      "shroudemail._domainkey.email.shroud.test", :txt ->
        {:ok, [[to_charlist("v=DKIM1; p=#{@public_key}")]]}

      "_dmarc.email.shroud.test", :txt ->
        {:ok, [[~c"v=DMARC1; p=reject"]]}
    end

    {results, targets} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert targets == ["mx1.example", "mx2.example"]
    assert Enum.find(results, &(&1.name == "MX mx1.example A/AAAA")).status == :pass
    assert Enum.find(results, &(&1.name == "MX mx2.example A/AAAA")).status == :fail
    assert Enum.find(results, &(&1.name == "SPF")).status == :pass
    assert Enum.find(results, &(&1.name == "DKIM")).status == :pass
    assert Enum.find(results, &(&1.name == "DMARC")).status == :pass
  end

  test "distinguishes failed DNS lookup from missing records" do
    dns = fn
      "email.shroud.test", :mx -> {:error, :timeout}
      "email.shroud.test", :txt -> {:ok, []}
      _, :txt -> {:error, :servfail}
    end

    {results, []} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert Enum.find(results, &(&1.name == "MX")).status == :unknown
    assert Enum.find(results, &(&1.name == "SPF")).status == :fail
    assert Enum.find(results, &(&1.name == "DKIM")).status == :unknown
  end

  test "does not pass multiple SPF policies or a non-key DKIM value" do
    dns = fn
      "email.shroud.test", :mx -> {:ok, []}
      "email.shroud.test", :txt -> {:ok, [[~c"v=spf1 mx -all"], [~c"v=spf1 +all"]]}
      "shroudemail._domainkey.email.shroud.test", :txt -> {:ok, [[~c"v=DKIM1; p=not-a-key"]]}
      "_dmarc.email.shroud.test", :txt -> {:ok, []}
    end

    {results, []} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert Enum.find(results, &(&1.name == "SPF")).status == :fail
    assert Enum.find(results, &(&1.name == "DKIM")).status == :fail
  end

  test "a deny-all SPF policy does not indicate outgoing mail is authorized" do
    dns = fn
      "email.shroud.test", :mx -> {:ok, []}
      "email.shroud.test", :txt -> {:ok, [[~c"v=spf1 -all"]]}
      _, :txt -> {:ok, []}
    end

    {results, _targets} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert Enum.find(results, &(&1.name == "SPF")).status == :fail
  end

  test "reports MX targets omitted by the probe limit instead of claiming complete success" do
    hosts = for index <- 1..6, do: {index, ~c"mx#{index}.example"}

    dns = fn
      "email.shroud.test", :mx -> {:ok, hosts}
      _, :a -> {:ok, [{192, 0, 2, 1}]}
      _, :aaaa -> {:ok, []}
      _, :txt -> {:ok, []}
    end

    {results, targets} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert length(targets) == 5
    assert Enum.find(results, &(&1.name == "MX")).status == :unknown
    assert Enum.find(results, &(&1.name == "MX")).detail =~ "1 not probed"
  end

  test "null MX is not a usable mail server" do
    dns = fn
      "email.shroud.test", :mx -> {:ok, [{0, ~c"."}]}
      _, :txt -> {:ok, []}
    end

    {results, targets} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert targets == []
    assert Enum.find(results, &(&1.name == "MX")).status == :fail
    refute Enum.any?(results, &String.starts_with?(&1.name, "MX "))
  end

  test "an MX host with a CNAME answer still reports its actual A address" do
    dns = fn
      "email.shroud.test", :mx -> {:ok, [{10, ~c"alias.example"}]}
      "alias.example", :a -> {:ok, [~c"target.example", {192, 0, 2, 7}]}
      "alias.example", :aaaa -> {:ok, []}
      _, :txt -> {:ok, []}
    end

    {results, _targets} = MailserverHealth.dns_checks("email.shroud.test", dns)

    assert Enum.find(results, &(&1.name == "MX alias.example A/AAAA")).detail == "192.0.2.7"
  end

  test "a STARTTLS advertisement alone cannot pass a rejected upgrade" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    start_supervised!(
      {Task,
       fn ->
         {:ok, socket} = :gen_tcp.accept(listener)
         :ok = :gen_tcp.send(socket, "220 mx.example ESMTP\r\n")
         {:ok, _ehlo} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "250-mx.example\r\n250-STARTTLS\r\n250 SIZE 10000\r\n")
         {:ok, _starttls} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "454 TLS unavailable\r\n")
         :gen_tcp.close(socket)
       end}
    )

    results = MailserverHealth.smtp_checks("localhost", port, :verified)

    assert Enum.find(results, &String.starts_with?(&1.name, "STARTTLS")).status == :fail
    assert Enum.find(results, &String.starts_with?(&1.name, "Certificate")).status == :unknown
    :gen_tcp.close(listener)
  end

  test "a STARTTLS acceptance without a valid TLS handshake fails certificate verification" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    start_supervised!(
      {Task,
       fn ->
         {:ok, socket} = :gen_tcp.accept(listener)
         :ok = :gen_tcp.send(socket, "220 mx.example ESMTP\r\n")
         {:ok, _ehlo} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "250-mx.example\r\n250 STARTTLS\r\n")
         {:ok, _starttls} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "220 Ready\r\n")
         :gen_tcp.close(socket)
       end}
    )

    results = MailserverHealth.smtp_checks("localhost", port, :verified)

    assert Enum.find(results, &String.starts_with?(&1.name, "STARTTLS")).status == :fail
    assert Enum.find(results, &String.starts_with?(&1.name, "Certificate")).status == :fail
    :gen_tcp.close(listener)
  end

  test "a successful STARTTLS handshake passes the private relay probe" do
    certificates =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
          peer: [key: {:rsa, 2048, 65_537}, digest: :sha256]
        },
        client_chain: %{
          root: [key: {:rsa, 2048, 65_537}, digest: :sha256],
          peer: [key: {:rsa, 2048, 65_537}, digest: :sha256]
        }
      })

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    start_supervised!(
      {Task,
       fn ->
         {:ok, socket} = :gen_tcp.accept(listener)
         :ok = :gen_tcp.send(socket, "220 relay.example ESMTP\r\n")
         {:ok, _ehlo} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "250-relay.example\r\n250 STARTTLS\r\n")
         {:ok, _starttls} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "220 Ready\r\n")

         {:ok, tls_socket} =
           :ssl.handshake(
             socket,
             [cert: certificates.server_config[:cert], key: certificates.server_config[:key]],
             3000
           )

         :ssl.close(tls_socket)
       end}
    )

    results = MailserverHealth.smtp_checks("localhost", port, :starttls)

    assert Enum.find(results, &String.starts_with?(&1.name, "SMTP")).status == :pass

    assert Enum.find(results, &String.starts_with?(&1.name, "STARTTLS")).status == :pass,
           inspect(results)

    :gen_tcp.close(listener)
  end

  test "a greeting without STARTTLS cannot pass the TLS check" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    start_supervised!(
      {Task,
       fn ->
         {:ok, socket} = :gen_tcp.accept(listener)
         :ok = :gen_tcp.send(socket, "220 mx.example ESMTP\r\n")
         {:ok, _ehlo} = :gen_tcp.recv(socket, 0, 2000)
         :ok = :gen_tcp.send(socket, "250-mx.example\r\n250 SIZE 10000\r\n")
         :gen_tcp.close(socket)
       end}
    )

    results = MailserverHealth.smtp_checks("localhost", port, :verified)

    assert Enum.find(results, &String.starts_with?(&1.name, "SMTP")).status == :pass
    assert Enum.find(results, &String.starts_with?(&1.name, "STARTTLS")).status == :fail
    assert Enum.find(results, &String.starts_with?(&1.name, "Certificate")).status == :unknown
    :gen_tcp.close(listener)
  end

  test "a closed port fails the connection without pretending to verify a certificate" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :gen_tcp.close(listener)

    results = MailserverHealth.smtp_checks("localhost", port, :verified)

    assert Enum.find(results, &String.starts_with?(&1.name, "SMTP")).status == :fail
    assert Enum.find(results, &String.starts_with?(&1.name, "Certificate")).status == :unknown
  end
end

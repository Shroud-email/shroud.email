defmodule ShroudWeb.Plugs.RateLimitTest do
  use ExUnit.Case, async: true

  alias ShroudWeb.Plugs.RateLimit

  setup do
    policy = {:test, make_ref()}

    opts = RateLimit.init(policy: policy, scale: 60_000, limit: 2, by: & &1.remote_ip)
    %{opts: opts, policy: policy}
  end

  test "allows the limit, then halts with 429 and rounded-up retry guidance", %{opts: opts} do
    conn = Plug.Test.conn(:get, "/")

    assert RateLimit.call(conn, opts).state == :unset
    assert RateLimit.call(conn, opts).state == :unset
    rejected = RateLimit.call(conn, opts)

    assert rejected.status == 429
    assert rejected.halted
    assert rejected.resp_body == "Too many requests. Please try again later."
    assert [retry_after] = Plug.Conn.get_resp_header(rejected, "retry-after")
    assert String.to_integer(retry_after) in 1..60
    assert Plug.Conn.get_resp_header(rejected, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "changing paths or forged forwarding headers does not change the actor", %{opts: opts} do
    for path <- ["/aliases/one", "/domains/two"] do
      RateLimit.call(Plug.Test.conn(:get, path), opts)
    end

    conn =
      Plug.Test.conn(:get, "/another?token=different")
      |> Plug.Conn.put_req_header("x-forwarded-for", "192.0.2.100")
      |> RateLimit.call(opts)

    assert conn.status == 429
  end

  test "separates actors and policies", %{opts: opts} do
    conn = Plug.Test.conn(:get, "/")
    for _ <- 1..2, do: RateLimit.call(conn, opts)
    assert RateLimit.call(conn, opts).status == 429

    other_actor = %{conn | remote_ip: {192, 0, 2, 42}}
    assert RateLimit.call(other_actor, opts).state == :unset

    other_policy = RateLimit.init(policy: make_ref(), scale: 60_000, limit: 2, by: & &1.remote_ip)
    assert RateLimit.call(conn, other_policy).state == :unset
  end

  test "supports account identity independent of client IP", %{policy: policy} do
    opts =
      RateLimit.init(policy: policy, scale: 60_000, limit: 1, by: & &1.assigns.current_user.id)

    conn = Plug.Test.conn(:post, "/") |> Plug.Conn.assign(:current_user, %{id: 42})
    assert RateLimit.call(conn, opts).state == :unset
    assert RateLimit.call(%{conn | remote_ip: {192, 0, 2, 42}}, opts).status == 429
    assert RateLimit.call(Plug.Conn.assign(conn, :current_user, %{id: 43}), opts).state == :unset
  end

  test "atomic backend admits only the configured number concurrently", %{policy: policy} do
    results =
      1..50
      |> Task.async_stream(fn _ -> Shroud.RateLimit.hit(policy, 60_000, 7) end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:allow, _}, &1)) == 7
    assert Enum.count(results, &match?({:deny, _}, &1)) == 43
  end
end

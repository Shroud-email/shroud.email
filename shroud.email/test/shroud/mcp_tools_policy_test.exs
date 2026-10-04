defmodule Shroud.McpToolsPolicyTest do
  use Shroud.DataCase, async: false
  import Shroud.OAuthFixtures
  import ExUnit.CaptureLog
  alias Shroud.{Aliases, Repo}
  alias Shroud.Mcp.Tools

  setup do
    original = Application.get_env(:ex_mcp, :json_schema, [])
    on_exit(fn -> Application.put_env(:ex_mcp, :json_schema, original) end)
    user = confirmed_user()
    %{connection: %{user: user, user_id: user.id}, original: original}
  end

  test "schema mismatches remain input errors without logging private values", context do
    log =
      capture_log(fn ->
        assert {:error, "Invalid tool arguments", %{error_code: "INVALID_ARGUMENT"}} =
                 Tools.call(context.connection, "create_alias", %{
                   "title" => "PRIVATE_TITLE",
                   "unexpected" => "PRIVATE_VALUE"
                 })
      end)

    refute log =~ "PRIVATE"
    assert Repo.aggregate(Aliases.EmailAlias, :count) == 0
  end

  test "validator policy failures are retryable, sanitized and never execute the tool", context do
    Application.put_env(:ex_mcp, :json_schema, validation_timeout_ms: -1)
    args = %{"title" => "PRIVATE_TITLE", "notes" => "PRIVATE_NOTES"}

    log =
      capture_log(fn ->
        assert {:error, "Tool unavailable; please try again.",
                %{error_code: "SERVICE_UNAVAILABLE"}} =
                 Tools.call(context.connection, "create_alias", args)
      end)

    assert log =~ "MCP schema validation unavailable (invalid_schema_policy_option)"
    refute log =~ "PRIVATE_TITLE"
    refute log =~ "PRIVATE_NOTES"
    assert Repo.aggregate(Aliases.EmailAlias, :count) == 0
    Application.put_env(:ex_mcp, :json_schema, context.original)
    assert {:ok, _} = Tools.call(context.connection, "create_alias", args)
  end
end

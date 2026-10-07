defmodule ShroudWeb.UnsubscribeController do
  use ShroudWeb, :controller

  alias Shroud.Email.Unsubscribe

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> text(
      "Use your email app's unsubscribe button, or manage blocked senders and aliases in Shroud.email."
    )
  end

  def create(conn, %{"token" => token}) do
    content_type =
      conn
      |> get_req_header("content-type")
      |> List.first("")
      |> String.split(";")
      |> List.first()

    with true <- content_type in ["application/x-www-form-urlencoded", "multipart/form-data"],
         %{"List-Unsubscribe" => "One-Click"} <- conn.body_params,
         {:ok, _alias} <- Unsubscribe.consume(token) do
      conn |> put_resp_header("cache-control", "no-store") |> send_resp(204, "")
    else
      _ ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(400, "Invalid unsubscribe request.")
    end
  end
end

defmodule ShroudWeb.InboxAttachmentController do
  use ShroudWeb, :controller
  alias Shroud.Inboxes

  def show(conn, %{"id" => id, "index" => index}) do
    user = conn.assigns.current_user

    with true <- Inboxes.enabled?(user),
         {index, ""} when index >= 0 <- Integer.parse(index),
         {_message, email} <- Inboxes.read_message!(user, id),
         attachment when not is_nil(attachment) <- Enum.at(email.attachments, index) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_download({:binary, attachment.data},
        filename: Path.basename(attachment.filename),
        content_type: "application/octet-stream"
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end

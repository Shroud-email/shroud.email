defmodule Shroud.InboxesFixtures do
  def email_with_attachment do
    """
    From: Travel Desk <travel@example.com>
    To: inbox@example.com
    Subject: Your itinerary
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="inbox-test"

    --inbox-test
    Content-Type: text/plain; charset=utf-8

    Your train leaves at 09:45. <script>Not markup</script>
    --inbox-test
    Content-Type: application/pdf
    Content-Disposition: attachment; filename="itinerary.pdf"
    Content-Transfer-Encoding: base64

    JVBERi0xLjQKAAEC
    --inbox-test--
    """
    |> String.replace("\n", "\r\n")
  end

  def message_fixture(inbox, attrs \\ %{}) do
    Shroud.Repo.insert!(
      struct!(
        Shroud.Inboxes.Message,
        Map.merge(
          %{
            email_alias_id: inbox.id,
            storage_key: "inboxes/test/#{Ecto.UUID.generate()}",
            delivery_id: Ecto.UUID.generate(),
            sender: "travel@example.com",
            subject: "Your itinerary",
            size: byte_size(email_with_attachment()),
            stored: true
          },
          attrs
        )
      )
    )
  end
end

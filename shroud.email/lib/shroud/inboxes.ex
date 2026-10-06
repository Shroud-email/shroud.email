defmodule Shroud.Inboxes do
  @moduledoc "Persistent inbox aliases with encrypted MIME contents in S3."
  import Ecto.Query
  alias Shroud.{Aliases, Repo, Vault}
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Email.{InboxEmail, SpamHandler}
  alias Shroud.Inboxes.Message

  def enabled?(user), do: FunWithFlags.enabled?(:agent_inboxes, for: user)

  def get_inbox!(user, address) do
    user
    |> Aliases.aliases_query()
    |> where([a], a.delivery_mode == :inbox)
    |> Repo.get_by!(address: address)
  end

  # Each recipient's Oban job is a delivery, so retries do not create duplicate mail.
  def store(email_alias, sender, data, delivery_id) do
    delivery_id = "#{email_alias.id}:#{delivery_id}"
    key = "inboxes/#{email_alias.id}/#{delivery_id}.eml"

    reservation =
      Repo.transaction(fn ->
        current =
          Repo.one!(from a in EmailAlias, where: a.id == ^email_alias.id, lock: "FOR UPDATE")

        cond do
          current.deleted_at || not current.enabled ->
            :ok

          Repo.get_by(Message, delivery_id: delivery_id) ->
            Repo.get_by!(Message, delivery_id: delivery_id)

          true ->
            email = InboxEmail.parse(data, sender, current.address)

            Repo.insert!(%Message{
              email_alias_id: current.id,
              delivery_id: delivery_id,
              storage_key: key,
              sender: sender,
              subject: email.subject,
              size: byte_size(data),
              spam: SpamHandler.spam?(data)
            })
        end
      end)

    case reservation do
      {:ok, %Message{id: id}} -> store_contents(id, data)
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Reserve the S3 key durably before uploading; a failed upload stays retryable.
  defp store_contents(id, data) do
    Repo.transaction(fn ->
      message = Repo.one(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")

      if message && not message.stored && is_nil(message.deleted_at) && message.email_alias_id do
        s3().put_email!(message.storage_key, Vault.encrypt!(data))
        message |> Ecto.Changeset.change(stored: true) |> Repo.update!()
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_messages(user, address, page \\ 1) do
    inbox = get_inbox!(user, address)

    from(m in visible_messages(user),
      where: m.email_alias_id == ^inbox.id,
      order_by: [desc: m.id]
    )
    |> Repo.paginate(page: page, page_size: 20)
  end

  def get_message!(user, id), do: Repo.get!(visible_messages(user), id)

  def read_message!(user, id) do
    message = get_message!(user, id)
    inbox = Repo.get!(EmailAlias, message.email_alias_id)
    data = message.storage_key |> s3().get_email!() |> Vault.decrypt!()
    {message, InboxEmail.parse(data, message.sender, inbox.address)}
  end

  def set_read!(user, id, read) when is_boolean(read) do
    user |> get_message!(id) |> Ecto.Changeset.change(read: read) |> Repo.update!()
  end

  def delete_message!(user, id) do
    user
    |> get_message!(id)
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()
  end

  def set_retention(user, address, days) do
    user |> get_inbox!(address) |> Aliases.update_email_alias(%{retention_days: days})
  end

  # Keep tombstones until S3 deletion succeeds, so failures can be retried.
  def cleanup do
    cleanup_candidates()
    |> Repo.all()
    |> Enum.each(fn message ->
      Repo.transaction(fn ->
        eligible_ids = from m in cleanup_candidates(), select: m.id

        current =
          Repo.one(
            from m in Message,
              where: m.id == ^message.id and m.id in subquery(eligible_ids),
              lock: "FOR UPDATE"
          )

        if current do
          s3().delete_email!(current.storage_key)
          Repo.delete!(current)
        end
      end)
    end)
  end

  defp cleanup_candidates do
    from(m in Message,
      left_join: a in EmailAlias,
      on: a.id == m.email_alias_id,
      where:
        not is_nil(m.deleted_at) or is_nil(a.id) or not is_nil(a.deleted_at) or
          (not is_nil(a.retention_days) and
             fragment(
               "? <= timezone('UTC', now()) - (? * interval '1 day')",
               m.inserted_at,
               a.retention_days
             ))
    )
  end

  defp visible_messages(user) do
    from(m in Message,
      join: a in EmailAlias,
      on: a.id == m.email_alias_id,
      where:
        a.user_id == ^user.id and a.delivery_mode == :inbox and
          is_nil(a.deleted_at) and is_nil(m.deleted_at) and m.stored
    )
  end

  defp s3, do: Application.get_env(:shroud, :s3_client, Shroud.S3.S3Client)
end

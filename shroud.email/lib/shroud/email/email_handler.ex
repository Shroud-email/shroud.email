defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email, max_attempts: 100

  alias Shroud.Accounts
  alias Shroud.Repo

  import Ecto.Query

  alias Shroud.Email.{
    BounceHandler,
    ReplyAddress,
    IncomingEmailHandler,
    OutgoingEmailHandler
  }

  import Shroud.Accounts.Logging, only: [maybe_log: 2]

  @type mimemail_email :: :mimemail.mimetuple()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}} = job) do
    # Decode Base64 encoded email data (encoded in SmtpServer to safely store as JSONB)
    decoded_data = decode_data(data)
    do_perform(job, from, to, decoded_data)
  end

  defp do_perform(_job, from, to, data) when byte_size(data) > 26_214_400 do
    # when the email is too big, cancel

    if is_list(to) do
      Enum.each(to, fn recipient ->
        user = Accounts.get_user_by_alias(recipient)
        maybe_log(user, "Dropping email from #{from} to #{recipient} because it's above 25MB")
      end)
    else
      user = Accounts.get_user_by_alias(to)
      maybe_log(user, "Dropping email from #{from} to #{to} because it's above 25MB")
    end

    # silently drop the email. can probably handle this better but not worth it for now.
    :ok
  end

  defp do_perform(job, from, recipients, data) when is_list(recipients) do
    fan_out(job, from, recipients, data)
  end

  defp do_perform(job, from, to, data) do
    cond do
      postmaster?(to) -> forward_postmaster(data)
      from in ["", nil] -> BounceHandler.handle_haraka_bounce_report(to, data)
      true -> handle_recipient(from, to, data, job.id || Ecto.UUID.generate())
    end
  end

  defp postmaster?(recipient) do
    String.downcase(recipient) == "postmaster@#{String.downcase(Shroud.Util.email_domain())}"
  end

  defp forward_postmaster(data) do
    destination = Application.get_env(:shroud, :admin_user_email)

    cond do
      destination in [nil, ""] ->
        {:error, :postmaster_destination_missing}

      postmaster?(destination) ->
        {:error, :postmaster_forwarding_loop}

      true ->
        email =
          Swoosh.Email.new()
          |> Swoosh.Email.to(destination)
          |> Swoosh.Email.from({"Shroud postmaster", "noreply@#{Shroud.Util.email_domain()}"})
          |> Swoosh.Email.subject("Mail to postmaster@#{Shroud.Util.email_domain()}")
          |> Swoosh.Email.text_body("The original postmaster message is attached.")
          |> Swoosh.Email.attachment(
            Swoosh.Attachment.new({:data, data},
              filename: "postmaster.eml",
              content_type: "message/rfc822"
            )
          )

        case Shroud.Mailer.deliver(email) do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end
    end
  end

  defp fan_out(%Oban.Job{id: id}, from, recipients, data) do
    # Save recipient jobs and the parent's fan-out completion flag together.
    # The flag prevents duplicate jobs on retry, even after children are pruned.
    # Lock the parent so concurrent executions cannot both create jobs.
    case Repo.transaction(fn ->
           parent = Repo.one!(from j in Oban.Job, where: j.id == ^id, lock: "FOR UPDATE")

           unless parent.meta["fan_out_completed"] do
             encoded_data = Base.encode64(data)

             # Each child stores the payload so it can retry after the parent is
             # pruned. Storage and write I/O scale with the recipient count.
             recipients
             |> Enum.uniq()
             |> Enum.map(&new(%{from: from, to: &1, data: encoded_data}))
             |> Oban.insert_all()

             parent
             |> Ecto.Changeset.change(meta: Map.put(parent.meta, "fan_out_completed", true))
             |> Repo.update!()
           end
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Decode Base64 encoded email data. Falls back to raw data for backwards
  # compatibility with jobs created before encoding was added.
  defp decode_data(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  @spec handle_recipient(String.t(), String.t(), String.t(), integer() | String.t()) ::
          :ok | {:error, term()}
  defp handle_recipient(sender, recipient, data, delivery_id) do
    if ReplyAddress.reply_address?(recipient) do
      OutgoingEmailHandler.handle_outgoing_email(sender, recipient, data)
    else
      IncomingEmailHandler.handle_incoming_email(sender, recipient, data, delivery_id)
    end
  end
end

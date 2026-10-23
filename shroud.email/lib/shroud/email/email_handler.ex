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

  @doc "Queues an SMTP envelope bound to its recipient accounts."
  def enqueue(sender, recipients, data) do
    Repo.transaction(fn ->
      recipients = List.wrap(recipients) |> Enum.uniq()
      owners = Map.new(recipients, &{&1, recipient_user_id(&1)})
      user_ids = owners |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

      # Serialize admission with deletion, including a deletion already in progress.
      Repo.all(
        from u in Accounts.User,
          where: u.id in ^user_ids,
          order_by: u.id,
          lock: "FOR UPDATE"
      )

      recipients = Enum.filter(recipients, &(owners[&1] == recipient_user_id(&1)))

      if recipients != [] do
        %{from: sender, to: recipients, data: Base.encode64(data)}
        |> new(meta: %{recipient_user_ids: Map.take(owners, recipients)})
        |> Oban.insert!()
      end
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}} = job) do
    Logger.metadata(oban_job_id: job.id)

    # Decode Base64 encoded email data (encoded in SmtpServer to safely store as JSONB)
    decoded_data = decode_data(data)

    if is_list(to) do
      do_perform(job, from, to, decoded_data)
    else
      deliver_to_current_owner(job, from, to, decoded_data)
    end
  end

  defp deliver_to_current_owner(job, sender, recipient, data) do
    user_id = recipient_user_id(recipient)

    # A worker may already hold a job that deletion removed from the database.
    current =
      if Ecto.get_meta(job, :state) == :loaded, do: Repo.get(Oban.Job, job.id), else: job

    if current && current.args["to"] == recipient &&
         Map.get(current.meta["recipient_user_ids"] || %{}, recipient, user_id) == user_id do
      do_perform(current, sender, recipient, data, user_id)
    else
      :ok
    end
  end

  defp recipient_user_id(recipient) do
    address =
      if ReplyAddress.reply_address?(recipient),
        do: elem(ReplyAddress.from_reply_address(recipient), 1),
        else: recipient

    {_local, domain} = Shroud.Util.extract_email_parts(address)
    user = Accounts.get_user_by_alias(address)
    custom_domain = if is_nil(user), do: Shroud.Domain.get_custom_domain(domain)

    cond do
      postmaster?(recipient) -> nil
      user -> user.id
      custom_domain -> custom_domain.user_id
      true -> nil
    end
  end

  @doc "Removes an account's queued deliveries without dropping other envelope recipients."
  def delete_user_jobs(addresses, domains) do
    jobs =
      from j in Oban.Job,
        where: j.worker == "Shroud.Email.EmailHandler",
        where:
          fragment(
            """
            EXISTS (
              SELECT 1 FROM jsonb_array_elements_text(
                CASE jsonb_typeof(?->'to') WHEN 'array' THEN ?->'to'
                ELSE jsonb_build_array(?->>'to') END
              ) AS r(address)
              WHERE r.address = ANY(?) OR split_part(r.address, '@', 2) = ANY(?)
              OR EXISTS (SELECT 1 FROM unnest(?::text[]) AS a(address)
                         WHERE right(r.address, length(a.address) + 1) = '_' || a.address)
            )
            """,
            j.args,
            j.args,
            j.args,
            ^addresses,
            ^domains,
            ^addresses
          )

    # Lock list jobs against fan-out, then remove scalar children in a fresh query.
    # A fan-out that finishes while we wait is visible to the second query.
    for job <-
          Repo.all(
            from j in jobs,
              where: fragment("jsonb_typeof(?->'to') = 'array'", j.args),
              lock: "FOR UPDATE"
          ) do
      remaining =
        Enum.reject(job.args["to"], fn recipient ->
          {_local, domain} = Shroud.Util.extract_email_parts(recipient)

          recipient in addresses or domain in domains or
            Enum.any?(addresses, &String.ends_with?(recipient, "_" <> &1))
        end)

      if remaining == [] do
        Repo.delete!(job)
      else
        job
        |> Ecto.Changeset.change(
          args: Map.put(job.args, "to", remaining),
          meta: recipient_meta(job.meta, remaining)
        )
        |> Repo.update!()
      end
    end

    Repo.delete_all(from j in jobs, where: fragment("jsonb_typeof(?->'to') != 'array'", j.args))
  end

  defp do_perform(job, from, to, data, user_id \\ nil)

  defp do_perform(_job, from, to, data, _user_id) when byte_size(data) > 26_214_400 do
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

  defp do_perform(job, from, recipients, data, _user_id) when is_list(recipients) do
    fan_out(job, from, recipients, data)
  end

  defp do_perform(_job, from, to, data, user_id) do
    cond do
      postmaster?(to) ->
        forward_postmaster(data)

      from in ["", nil] or BounceHandler.delivery_status_report?(data) ->
        BounceHandler.handle_haraka_bounce_report(to, data)

      true ->
        handle_recipient(from, to, data, user_id)
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

  defp fan_out(%Oban.Job{id: id}, from, _recipients, data) do
    # Save recipient jobs and the parent's fan-out completion flag together.
    # The flag prevents duplicate jobs on retry, even after children are pruned.
    # Lock the parent so concurrent executions cannot both create jobs.
    case Repo.transaction(fn ->
           parent = Repo.one(from j in Oban.Job, where: j.id == ^id, lock: "FOR UPDATE")

           if parent && parent.meta["fan_out_completed"] != true do
             encoded_data = Base.encode64(data)

             # Each child stores the payload so it can retry after the parent is
             # pruned. Storage and write I/O scale with the recipient count.
             parent.args["to"]
             |> Enum.uniq()
             |> Enum.map(
               &new(%{from: from, to: &1, data: encoded_data},
                 meta: recipient_meta(Map.take(parent.meta, ["recipient_user_ids"]), [&1])
               )
             )
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

  defp recipient_meta(meta, recipients) do
    if owners = meta["recipient_user_ids"],
      do: Map.put(meta, "recipient_user_ids", Map.take(owners, recipients)),
      else: meta
  end

  # Decode Base64 encoded email data. Falls back to raw data for backwards
  # compatibility with jobs created before encoding was added.
  defp decode_data(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  @spec handle_recipient(String.t(), String.t(), String.t(), integer() | nil) ::
          :ok | {:error, term()}
  defp handle_recipient(sender, recipient, data, user_id) do
    if ReplyAddress.reply_address?(recipient) do
      OutgoingEmailHandler.handle_outgoing_email(sender, recipient, data, user_id)
    else
      IncomingEmailHandler.handle_incoming_email(sender, recipient, data, user_id)
    end
  end
end

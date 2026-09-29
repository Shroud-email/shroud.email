defmodule Shroud.Email do
  import Ecto.Query

  alias Shroud.Repo
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Accounts.User
  alias Shroud.Email.Tracker
  alias Shroud.Email.TrackerDomain
  alias Shroud.Email.SpamEmail
  alias Shroud.Util

  def list_trackers() do
    query =
      from t in Tracker,
        select: %Tracker{name: t.name, pattern: t.pattern}

    Repo.all(query)
  end

  def create_tracker(attrs) do
    %Tracker{}
    |> Tracker.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records that each of the given tracking `domains` was blocked in an email
  today, incrementing the per-day count for each one. Domains are expected to be
  deduplicated already (one increment per domain per email).
  """
  @spec record_blocked_domains([String.t()]) :: :ok
  def record_blocked_domains([]), do: :ok

  def record_blocked_domains(domains) when is_list(domains) do
    today = Date.utc_today()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # One row per distinct domain; deduplicating also guarantees no domain
    # appears twice in the same insert, which would break ON CONFLICT.
    entries =
      domains
      |> Enum.uniq()
      |> Enum.map(fn domain ->
        %{domain: domain, date: today, count: 1, inserted_at: now, updated_at: now}
      end)

    # Single statement to avoid an N+1 when an email contains several trackers.
    Repo.insert_all(TrackerDomain, entries,
      on_conflict: [inc: [count: 1]],
      conflict_target: [:domain, :date]
    )

    :ok
  end

  @spec store_spam_email!(map(), User.t(), EmailAlias.t()) :: SpamEmail.t()
  def store_spam_email!(attrs, user, email_alias) do
    html_body =
      if Map.get(attrs, :html_body) do
        attrs.html_body
        |> Util.crlf_to_lf()
        |> HtmlSanitizeEx.Scrubber.scrub(Shroud.Email.SpamEmailScrubber)
      else
        nil
      end

    text_body = if Map.get(attrs, :text_body), do: Util.crlf_to_lf(attrs.text_body), else: nil

    attrs =
      Map.merge(attrs, %{
        html_body: html_body,
        text_body: text_body
      })

    %SpamEmail{}
    |> Ecto.Changeset.change(attrs)
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Ecto.Changeset.put_assoc(:email_alias, email_alias)
    |> Repo.insert!()
  end

  @spec list_spam_emails(User.t()) :: [SpamEmail.t()]
  def list_spam_emails(%User{} = user) do
    query =
      from e in SpamEmail,
        where: e.user_id == ^user.id,
        join: ea in assoc(e, :email_alias),
        preload: [email_alias: ea]

    Repo.all(query)
  end

  @spec count_spam_emails(User.t()) :: integer()
  def count_spam_emails(%User{} = user) do
    query =
      from e in SpamEmail,
        where: e.user_id == ^user.id,
        select: count()

    Repo.one(query)
  end

  @spec get_spam_email!(integer()) :: SpamEmail.t()
  def get_spam_email!(id) do
    Repo.get!(SpamEmail, id) |> Repo.preload([:email_alias])
  end

  def delete_spam_email!(%SpamEmail{} = spam_email) do
    Repo.delete!(spam_email)
  end

  @spec delete_old_spam_emails() :: integer()
  def delete_old_spam_emails() do
    query =
      from e in SpamEmail,
        where: e.inserted_at < datetime_add(^NaiveDateTime.utc_now(), -7, "day")

    {num_deleted, _returned} = Repo.delete_all(query)
    num_deleted
  end
end

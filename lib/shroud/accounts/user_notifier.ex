defmodule Shroud.Accounts.UserNotifier do
  import Swoosh.Email

  alias Shroud.{Accounts, EmailTemplate, Mailer, Util, Repo}
  alias Shroud.Domain.CustomDomain
  alias ShroudWeb.Endpoint
  alias ShroudWeb.Router.Helpers, as: Routes

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, html_body, text_body) do
    email =
      new()
      |> to(recipient)
      |> from({"Shroud.email", "noreply@#{Util.email_domain()}"})
      |> reply_to({"Shroud.email", "contact@shroud.email"})
      |> subject(subject)
      |> html_body(html_body)
      |> text_body(text_body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    html_body =
      EmailTemplate.ConfirmationInstructions.render(
        user_email: user.email,
        confirmation_link: url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    To finish signing up for Shroud.email, please confirm your address
    by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """

    deliver(user.email, "Confirmation instructions", html_body, text_body)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    html_body =
      EmailTemplate.ResetPasswordInstructions.render(
        user_email: user.email,
        reset_link: url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    You can reset your password for Shroud.email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    deliver(user.email, "Reset password", html_body, text_body)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    html_body =
      EmailTemplate.UpdateEmailInstructions.render(
        user_email: user.email,
        update_email_link: url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    You can change your email on Shroud.email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    deliver(user.email, "Update email", html_body, text_body)
  end

  def deliver_trial_expiring_notice(user_id) do
    user = Accounts.get_user!(user_id)
    billing_url = Routes.user_settings_url(Endpoint, :billing)
    expiry_date = Timex.format!(user.trial_expires_at, "{D} {Mshort} '{YY}")

    html_body =
      EmailTemplate.TrialExpiringNotice.render(
        user_email: user.email,
        expiry_date: expiry_date,
        billing_url: billing_url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    Your Shroud.email trial is expiring soon, on #{expiry_date}.

    We hope you've found Shroud.email's unlimited aliases and tracker blocking useful!
    To avoid interrupting the service, you can sign up at the following URL:

    #{billing_url}

    If you have any questions, please let us know on contact@shroud.email.

    ==============================
    """

    deliver(user.email, "Your Shroud.email trial is expiring!", html_body, text_body)
  end

  def deliver_trial_expired_notice(user_id) do
    user = Accounts.get_user!(user_id)
    billing_url = Routes.user_settings_url(Endpoint, :billing)

    html_body =
      EmailTemplate.TrialExpiredNotice.render(
        user_email: user.email,
        billing_url: billing_url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    Your Shroud.email trial has expired.

    You'll no longer be able to create new aliases.

    To re-activate your aliases and your account, you can sign up at the following URL:

    #{billing_url}

    If you have any questions, please let us know on contact@shroud.email.

    ==============================
    """

    deliver(user.email, "Your Shroud.email trial has expired", html_body, text_body)
  end

  def deliver_outgoing_email_marked_as_spam(user_id, email_alias, recipient) do
    user = Accounts.get_user!(user_id)

    html_body =
      EmailTemplate.OutgoingEmailMarkedAsSpam.render(
        user_email: user.email,
        email_alias: email_alias,
        recipient: recipient,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    Your email to #{recipient} (via #{email_alias}) was not delivered as our
    systems detected it as spam.

    Please edit your email and try again, or contact us on support@shroud.email for
    further help.

    ==============================
    """

    deliver(user.email, "Your email was not delivered", html_body, text_body)
  end

  def deliver_incoming_email_marked_as_spam(user_id, email_alias) do
    user = Accounts.get_user!(user_id)
    spam_url = Routes.spam_email_index_path(Endpoint, :index)

    html_body =
      EmailTemplate.IncomingEmailMarkedAsSpam.render(
        user_email: user.email,
        email_alias: email_alias,
        spam_url: spam_url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    An email sent to one of your aliases (#{email_alias}) was marked as spam.
    We did not forward this email as it would likely be refused by your mail provider.

    You can view this email on our web app: #{spam_url}

    It will be deleted in 7 days.

    ==============================
    """

    deliver(user.email, "We blocked a spam email", html_body, text_body)
  end

  def deliver_domain_verified(custom_domain_id) do
    custom_domain = Repo.get(CustomDomain, custom_domain_id) |> Repo.preload(:user)
    user = custom_domain.user
    domain_url = Routes.custom_domain_show_path(Endpoint, :show, custom_domain.domain)

    html_body =
      EmailTemplate.DomainVerified.render(
        user_email: user.email,
        domain: custom_domain.domain,
        domain_url: domain_url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    Good news! Your domain #{custom_domain.domain} has been verified on Shroud.email.
    You can now use it to create aliases.

    You can configure your domain, including catch-all, on the following URL:
    #{domain_url}

    ==============================
    """

    deliver(user.email, "Your domain has been verified", html_body, text_body)
  end

  def deliver_domain_no_longer_verified(custom_domain_id) do
    custom_domain = Repo.get(CustomDomain, custom_domain_id) |> Repo.preload(:user)
    user = custom_domain.user
    domain_url = Routes.custom_domain_show_path(Endpoint, :show, custom_domain.domain)

    html_body =
      EmailTemplate.DomainNoLongerVerified.render(
        user_email: user.email,
        domain: custom_domain.domain,
        domain_url: domain_url,
        current_year: DateTime.utc_now().year
      )

    text_body = """
    ==============================

    Hi #{user.email},

    Your custom domain on Shroud.email, #{custom_domain.domain}, is no longer
    verified as it no longer has the correct DNS records.

    Please log in to our web app to verify it again or delete it. Until you do,
    aliases on this domain will not work.

    #{domain_url}

    ==============================
    """

    deliver(user.email, "#{custom_domain.domain} is no longer verified", html_body, text_body)
  end
end

defmodule Shroud.Accounts.UserNotifier do
  import Swoosh.Email

  alias Shroud.Mailer
  alias Shroud.EmailTemplate

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, html_body, text_body) do
    email =
      new()
      |> to(recipient)
      |> from({"Shroud", "noreply@app.shroud.email"})
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
end

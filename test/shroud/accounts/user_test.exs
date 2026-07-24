defmodule Shroud.Accounts.UserTest do
  use Shroud.DataCase, async: true

  alias Shroud.Accounts.User

  describe "registration_changeset/2 email validation" do
    # These are the addresses :mimemail.encode (gen_smtp's RFC 5322 parser) raises
    # on — a MatchError, not an {:error, _} tuple — which previously crashed the
    # confirmation-email delivery path and 500'd POST /users/register
    # (SHROUDEMAIL-5Q). They must be rejected at the changeset so they never
    # reach the SMTP adapter.

    @invalid_dot_addresses [
      {"consecutive dots in local part", "a..b@example.com"},
      {"three consecutive dots in local part", "a...b@example.com"},
      {"leading dot in local part", ".foo@example.com"},
      {"trailing dot in local part", "foo.@example.com"},
      {"consecutive dots in domain", "foo@ex..ample.com"},
      {"leading dot in domain", "foo@.example.com"},
      {"trailing dot in domain", "foo@example.com."},
      {"the reported crash address", "c.la.r.i.n..p...v.il.lal.ong.o@gmail.com"}
    ]

    for {label, email} <- @invalid_dot_addresses do
      @tag label: label
      test "rejects #{label}: #{email}" do
        changeset =
          User.registration_changeset(%User{}, %{
            email: unquote(email),
            password: "hello world!"
          })

        refute changeset.valid?, "expected #{inspect(unquote(email))} to be rejected"
        assert Keyword.has_key?(changeset.errors, :email)
        {message, _} = Keyword.get(changeset.errors, :email)
        assert message =~ "is invalid"
      end
    end

    @valid_addresses [
      "first.last@gmail.com",
      "a.b@example.com",
      "foo@localhost",
      "foo+bar@gmail.com",
      "foo_bar@example.com",
      "foo-bar@example.com",
      "foo@ex-ample.com",
      "12345@example.com",
      "foo@a.b.example.com",
      "üñîçødé@example.com"
    ]

    for email <- @valid_addresses do
      @tag email: email
      test "accepts valid address: #{email}" do
        changeset =
          User.registration_changeset(%User{}, %{
            email: unquote(email),
            password: "hello world!"
          })

        # Only the email-specific validations should pass; ignore any
        # unsafe_validate_unique errors from a pre-existing row.
        email_errors =
          changeset.errors
          |> Keyword.get_values(:email)
          |> Enum.reject(fn {_msg, opts} ->
            opts[:validation] == :unsafe_unique
          end)

        assert email_errors == [],
               "expected #{inspect(unquote(email))} to pass validation, got errors: #{inspect(email_errors)}"
      end
    end
  end
end

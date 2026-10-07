defmodule Shroud.Accounts.UserTest do
  use Shroud.DataCase, async: true

  alias Shroud.Accounts.User
  alias Shroud.Domain
  import Shroud.{AccountsFixtures, AliasesFixtures, DomainFixtures}

  describe "registration_changeset/2 email validation" do
    # Email validity is checked with gen_smtp's own RFC 5322 parser
    # (:smtp_util.parse_rfc5322_addresses/1) — the same parser Swoosh invokes
    # via :mimemail.encode when sending mail. Addresses the parser rejects
    # previously crashed the SMTP encode path with a raised MatchError,
    # 500-ing POST /users/register after the user row was already saved.
    # Using the parser directly means validation can never drift from what the
    # mailer will actually accept.

    @invalid_dot_addresses [
      {"consecutive dots in local part", "a..b@example.com"},
      {"three consecutive dots in local part", "a...b@example.com"},
      {"leading dot in local part", ".foo@example.com"},
      {"trailing dot in local part", "foo.@example.com"},
      {"consecutive dots in domain", "foo@ex..ample.com"},
      {"leading dot in domain", "foo@.example.com"},
      {"trailing dot in domain", "foo@example.com."}
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
      "üñîçødé@example.com",
      # Quoted local parts are valid RFC 5322 and accepted by gen_smtp.
      "\"foo bar\"@example.com",
      # Domain-literal form (RFC 5322) — accepted by gen_smtp's parser. This
      # also discriminates parser-based validation from a hand-rolled regex,
      # which would reject the bracketed domain.
      "foo@[127.0.0.1]"
    ]

    # A signup form should accept a single bare address only — not a display
    # name form, not a comma-separated list. These parse as valid RFC 5322 but
    # are not a single plain address.
    @non_bare_forms [
      {"display name form", "Foo <foo@example.com>"},
      {"comma-separated list", "a@b.com, c@d.com"}
    ]

    for {label, email} <- @non_bare_forms do
      @tag label: label
      test "rejects non-bare address: #{label}" do
        changeset =
          User.registration_changeset(%User{}, %{
            email: unquote(email),
            password: "hello world!"
          })

        refute changeset.valid?, "expected #{inspect(unquote(email))} to be rejected"
        assert Keyword.has_key?(changeset.errors, :email)
      end
    end

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

  describe "hosted-domain email validation" do
    test "rejects primary-domain addresses without exposing alias existence or state" do
      owner = user_fixture()
      active = alias_fixture(%{user_id: owner.id})
      disabled = alias_fixture(%{user_id: owner.id, enabled: false})

      deleted =
        alias_fixture(%{
          user_id: owner.id,
          deleted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })

      for email <- [
            active.address,
            disabled.address,
            deleted.address,
            "unknown@email.shroud.test",
            "UPPER@EMAIL.SHROUD.TEST"
          ] do
        changeset = User.registration_changeset(%User{}, valid_user_attributes(%{email: email}))
        assert errors_on(changeset) == %{email: ["is invalid"]}
      end
    end

    test "rejects every address on an ownership-verified custom domain, even without catch-all or MX verification" do
      owner = user_fixture()

      domain =
        custom_domain_fixture(%{
          user_id: owner.id,
          domain: "Hosted.Example",
          catchall_enabled: false,
          mx_verified_at: nil
        })

      email_alias = alias_fixture(%{user_id: owner.id, address: "known@hosted.example"})

      for email <- [email_alias.address, "unknown@HOSTED.EXAMPLE"] do
        changeset = User.registration_changeset(%User{}, valid_user_attributes(%{email: email}))
        assert errors_on(changeset) == %{email: ["is invalid"]}
      end

      refute Domain.hosted_domain?("sub.hosted.example")
      assert Domain.hosted_domain?(domain.domain)
    end

    test "unverified and expired domain registrations cannot block an external inbox" do
      owner = user_fixture()

      fresh =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-23 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      expired =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-24 * 60 * 60)
        |> NaiveDateTime.truncate(:second)

      custom_domain_fixture(%{
        user_id: owner.id,
        domain: "fresh.example",
        ownership_verified_at: fresh
      })

      custom_domain_fixture(%{
        user_id: owner.id,
        domain: "expired.example",
        ownership_verified_at: expired
      })

      custom_domain_fixture(%{
        user_id: owner.id,
        domain: "unverified.example",
        ownership_verified_at: nil
      })

      assert Domain.hosted_domain?("fresh.example")

      for domain <- ["expired.example", "unverified.example", "external.example"] do
        refute Domain.hosted_domain?(domain)

        assert User.registration_changeset(
                 %User{},
                 valid_user_attributes(%{email: "inbox@#{domain}"})
               ).valid?
      end
    end

    test "does not add an account-existence error for an existing user on a hosted domain" do
      user = user_fixture(%{email: "existing@hosted.example"})
      custom_domain_fixture(%{domain: "hosted.example"})

      changeset =
        User.registration_changeset(%User{}, valid_user_attributes(%{email: user.email}))

      assert errors_on(changeset) == %{email: ["is invalid"]}
    end

    test "email changes use the same generic rejection" do
      user = user_fixture()
      custom_domain_fixture(%{user_id: user.id, domain: "hosted.example"})

      for email <- ["inbox@email.shroud.test", "inbox@hosted.example"] do
        assert errors_on(User.email_changeset(user, %{email: email})) == %{email: ["is invalid"]}
      end
    end
  end
end

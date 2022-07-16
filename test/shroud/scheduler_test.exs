defmodule Shroud.SchedulerTest do
  use Shroud.DataCase
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures

  alias Shroud.Scheduler
  alias Shroud.Email.TrackerListFetcher
  alias Shroud.Accounts.UserNotifierJob
  alias Shroud.Domain.DnsChecker

  describe "update_trackers/0" do
    test "enqueues the job" do
      Scheduler.update_trackers()

      assert_enqueued(worker: TrackerListFetcher)
    end
  end

  describe "email_expiring_trials" do
    test "emails expiring trial users" do
      now = NaiveDateTime.utc_now()
      two_days_from_now = NaiveDateTime.add(now, 2 * 24 * 60 * 60)
      user = user_fixture(%{status: :trial, trial_expires_at: two_days_from_now})
      Scheduler.email_expiring_trials()

      assert_enqueued(
        worker: UserNotifierJob,
        args: %{"email_function" => "deliver_trial_expiring_notice", "email_args" => [user.id]}
      )
    end

    test "does not email already-expired trial users" do
      now = NaiveDateTime.utc_now()
      yesterday = NaiveDateTime.add(now, -1 * 24 * 60 * 60)
      user_fixture(%{status: :trial, trial_expires_at: yesterday})
      Scheduler.email_expiring_trials()

      refute_enqueued(worker: UserNotifierJob)
    end

    test "does not email trial users expiring >72 hours" do
      now = NaiveDateTime.utc_now()
      four_days_from_now = NaiveDateTime.add(now, 4 * 24 * 60 * 60)
      user_fixture(%{status: :trial, trial_expires_at: four_days_from_now})
      Scheduler.email_expiring_trials()

      refute_enqueued(worker: UserNotifierJob)
    end

    test "does not email non-trial users" do
      now = NaiveDateTime.utc_now()
      two_days_from_now = NaiveDateTime.add(now, 2 * 24 * 60 * 60)
      user_fixture(%{status: :active, trial_expires_at: two_days_from_now})
      Scheduler.email_expiring_trials()

      refute_enqueued(worker: UserNotifierJob)
    end
  end

  describe "email_expired_trials" do
    test "emails recently expired trial users" do
      now = NaiveDateTime.utc_now()
      two_hours_ago = NaiveDateTime.add(now, -2 * 60 * 60)
      user = user_fixture(%{status: :trial, trial_expires_at: two_hours_ago})
      Scheduler.email_expired_trials()

      assert_enqueued(
        worker: UserNotifierJob,
        args: %{"email_function" => "deliver_trial_expired_notice", "email_args" => [user.id]}
      )
    end

    test "does not email expiring-soon trial users" do
      now = NaiveDateTime.utc_now()
      tomorrow = NaiveDateTime.add(now, 24 * 60 * 60)
      user_fixture(%{status: :trial, trial_expires_at: tomorrow})
      Scheduler.email_expired_trials()

      refute_enqueued(worker: UserNotifierJob)
    end

    test "does not email users whose trial expired >24 hours ago" do
      now = NaiveDateTime.utc_now()
      two_days_ago = NaiveDateTime.add(now, -2 * 24 * 60 * 60)
      user_fixture(%{status: :trial, trial_expires_at: two_days_ago})
      Scheduler.email_expired_trials()

      refute_enqueued(worker: UserNotifierJob)
    end

    test "does not email non-trial users" do
      now = NaiveDateTime.utc_now()
      two_hours_ago = NaiveDateTime.add(now, -2 * 60 * 60)
      user_fixture(%{status: :active, trial_expires_at: two_hours_ago})
      Scheduler.email_expired_trials()

      refute_enqueued(worker: UserNotifierJob)
    end
  end

  describe "verify_custom_domains/0" do
    test "enqueues a job for each custom domain" do
      domain_1 = custom_domain_fixture()
      domain_2 = custom_domain_fixture()

      Scheduler.verify_custom_domains()

      assert_enqueued(worker: DnsChecker, args: %{custom_domain_id: domain_1.id})
      assert_enqueued(worker: DnsChecker, args: %{custom_domain_id: domain_2.id})
    end

    test "schedules non-verified domains first" do
      domain_1 = custom_domain_fixture(%{ownership_verified_at: nil})
      domain_2 = custom_domain_fixture()

      Scheduler.verify_custom_domains()

      assert_enqueued(
        worker: DnsChecker,
        args: %{custom_domain_id: domain_1.id},
        scheduled_at: DateTime.utc_now()
      )

      refute_enqueued(
        worker: DnsChecker,
        args: %{custom_domain_id: domain_2.id},
        scheduled_at: DateTime.utc_now()
      )

      assert_enqueued(worker: DnsChecker, args: %{custom_domain_id: domain_2.id})
    end
  end
end

defmodule Shroud.SchedulerTest do
  use Shroud.DataCase
  use Oban.Testing, repo: Shroud.Repo

  import Shroud.AccountsFixtures
  import Shroud.DomainFixtures

  alias Shroud.Scheduler
  alias Shroud.Email.TrackerListFetcher
  alias Shroud.Domain.DnsChecker

  describe "update_trackers/0" do
    test "enqueues the job" do
      Scheduler.update_trackers()

      assert_enqueued(worker: TrackerListFetcher)
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

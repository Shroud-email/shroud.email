defmodule Shroud.Scheduler do
  use Quantum, otp_app: :shroud

  alias Shroud.Email.TrackerListFetcher

  def update_trackers() do
    %{}
    |> TrackerListFetcher.new()
    |> Oban.insert()
  end
end

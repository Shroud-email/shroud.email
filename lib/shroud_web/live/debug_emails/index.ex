defmodule ShroudWeb.DebugEmailsLive.Index do
  use ShroudWeb, :live_view

  alias Shroud.Repo
  import Canada, only: [can?: 2]
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Debug emails")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)
      |> fetch_failed_emails()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
      <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
        <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg">
          <table class="min-w-full divide-y divide-gray-300">
            <thead class="bg-gray-50">
              <tr>
                <th
                  scope="col"
                  class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6"
                >
                  From
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                  To
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                  Attempt
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                  Inserted at
                </th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                  Retry at
                </th>
                <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-6">
                  <span class="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white">
              <%= for job <- @failed_jobs do %>
                <tr>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <%= job.args["from"] %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <%= job.args["to"] %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <%= job.attempt %> / <%= job.max_attempts %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <%= Timex.format!(job.inserted_at, "{ISOdate} {h24}:{m}") %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <%= Timex.format!(job.scheduled_at, "{ISOdate} {h24}:{m}") %>
                  </td>
                  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6">
                    <a
                      href={~p"/debug_emails/#{job.id}"}
                      class="text-indigo-600 hover:text-indigo-900"
                    >
                      Details
                    </a>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp fetch_failed_emails(socket) do
    user = socket.assigns.current_user

    if can?(user, debug(Oban.Job)) do
      query =
        from j in Oban.Job,
          where: j.worker == ^"Shroud.Email.EmailHandler" and fragment("? != '{}'", j.errors)

      failed_jobs = Repo.all(query)

      assign(socket, :failed_jobs, failed_jobs)
    else
      assign(socket, :failed_jobs, [])
    end
  end
end

defmodule ShroudWeb.DebugEmailsLive.Show do
  use ShroudWeb, :live_view

  alias Shroud.Repo
  import Canada, only: [can?: 2]

  @impl true
  def handle_params(%{"id" => job_id}, _uri, socket) do
    socket =
      socket
      |> assign(:page_title, "Debug emails")
      |> assign(:page_title_url, ~p"/debug_emails")
      |> assign(:subpage_title, "Email")
      |> fetch_email(job_id)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h2 class="text-lg font-bold">Error</h2>
    <pre class="mt-4 bg-white p-4 rounded-md overflow-x-scroll">
      <%= List.last(@job.errors)["error"] %>
    </pre>

    <h2 class="text-lg font-bold mt-8">Email</h2>
    <p>To: <%= @job.args["to"] %></p>
    <p>From: <%= @job.args["from"] %></p>

    <pre class="mt-4 bg-white p-4 rounded-md overflow-x-scroll">
      <%= decode_email_data(@job.args["data"]) %>
    </pre>
    """
  end

  # Decode Base64 encoded email data for display.
  # Falls back to raw data for legacy jobs created before encoding was added.
  defp decode_email_data(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  defp fetch_email(socket, job_id) do
    user = socket.assigns.current_user

    if can?(user, debug(Oban.Job)) do
      job = Repo.get(Oban.Job, job_id)

      assign(socket, :job, job)
    else
      socket
    end
  end
end

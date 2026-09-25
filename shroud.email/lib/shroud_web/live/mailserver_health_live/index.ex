defmodule ShroudWeb.MailserverHealthLive.Index do
  use ShroudWeb, :live_view

  alias Shroud.Email.MailserverHealth

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Mailserver health")
      |> assign(:page_title_url, nil)
      |> assign(:subpage_title, nil)
      |> assign(:report, nil)
      |> assign(:checking, true)

    {:ok, if(connected?(socket), do: run_checks(socket), else: socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    if socket.assigns.checking do
      {:noreply, socket}
    else
      {:noreply, run_checks(socket)}
    end
  end

  @impl true
  def handle_async(:health, {:ok, report}, socket) do
    {:noreply, socket |> assign(:report, report) |> assign(:checking, false)}
  end

  def handle_async(:health, {:exit, _reason}, socket) do
    {:noreply,
     socket |> assign(:checking, false) |> put_flash(:error, "Health checks could not finish.")}
  end

  defp run_checks(socket) do
    socket
    |> assign(:checking, true)
    |> start_async(:health, fn ->
      Application.get_env(:shroud, :mailserver_health_checker, &MailserverHealth.run/0).()
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="mailserver-health" class="mx-auto max-w-4xl space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold text-gray-900 dark:text-gray-100">Mailserver health</h1>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-300">
            Read-only checks for {Application.fetch_env!(:shroud, :email_domain)}.
          </p>
        </div>
        <button
          id="mailserver-refresh"
          type="button"
          phx-click="refresh"
          disabled={@checking}
          class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-50"
        >
          {if @checking, do: "Checking…", else: "Refresh checks"}
        </button>
      </div>

      <p class="rounded-md border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 dark:border-amber-700 dark:bg-amber-950 dark:text-amber-100">
        These checks run from the app container. DNS policy checks validate basic record shape, not the actual sending IP or signatures. They cannot prove external firewall reachability, SMTP authentication, recipient acceptance, or successful delivery. No messages are sent.
      </p>

      <p
        :if={@checking}
        id="mailserver-progress"
        role="status"
        class="text-sm text-gray-600 dark:text-gray-300"
      >
        Checking DNS and SMTP endpoints…
      </p>

      <div :if={@report}>
        <p class="mb-3 text-sm text-gray-600 dark:text-gray-300">
          Checked {Calendar.strftime(@report.checked_at, "%Y-%m-%d %H:%M UTC")}
        </p>
        <ul
          id="mailserver-results"
          class="divide-y divide-gray-200 overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:divide-gray-700 dark:border-gray-700 dark:bg-gray-800"
        >
          <li
            :for={result <- @report.results}
            data-status={result.status}
            class="flex flex-col gap-1 px-4 py-4 sm:flex-row sm:items-start sm:gap-4"
          >
            <span class={[
              "inline-flex w-fit shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase",
              result.status == :pass &&
                "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-100",
              result.status == :fail && "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-100",
              result.status == :unknown &&
                "bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-100"
            ]}>
              {result.status}
            </span>
            <div class="min-w-0">
              <h2 class="text-sm font-medium text-gray-900 dark:text-gray-100">{result.name}</h2>
              <p class="break-words text-sm text-gray-600 dark:text-gray-300">{result.detail}</p>
            </div>
          </li>
        </ul>
      </div>
    </section>
    """
  end
end

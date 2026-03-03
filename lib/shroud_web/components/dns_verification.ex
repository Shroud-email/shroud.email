defmodule ShroudWeb.Components.DnsVerification do
  use ShroudWeb, :component
  alias Shroud.Domain

  attr(:domain, :any, required: true)
  attr(:verifying, :boolean, required: true)
  attr(:sections, :map, required: true)
  attr(:verify, :string, required: true)

  def dns_verification(assigns) do
    verified =
      Enum.reduce(assigns.sections, %{}, fn {_title, {field, _rows}}, acc ->
        Map.put(acc, field, Domain.dns_record_verified?(assigns.domain, field))
      end)

    assigns = assign(assigns, :all_verified, Domain.fully_verified?(assigns.domain))
    assigns = assign(assigns, :verified, verified)

    ~H"""
    <div>
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">DNS settings</h3>
          <%= if !@all_verified do %>
            <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
              Add the following DNS records to activate your domain.
            </p>
            <p class="text-sm text-gray-700 dark:text-gray-300">
              DNS propagation can take up to 24 hours. Once you've added these records, you can sit back and relax: we'll email you when your domain is verified.
            </p>
          <% end %>
        </div>
        <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
          <.button
            :if={not @all_verified}
            disabled={@verifying}
            click={@verify}
            text="Verify"
            icon={:arrow_path}
          />
        </div>
      </div>
      <div class="mt-4 flex flex-col">
        <div class="-my-2 -mx-4 overflow-x-auto sm:-mx-6 lg:-mx-8">
          <div class="inline-block min-w-full py-2 align-middle md:px-6 lg:px-8">
            <div class="overflow-hidden shadow dark:shadow-gray-900/50 ring-1 ring-black ring-opacity-5 dark:ring-gray-700 md:rounded-lg">
              <table class="min-w-full">
                <thead class="bg-white dark:bg-gray-800">
                  <tr>
                    <th
                      scope="col"
                      class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-gray-100 sm:pl-6"
                    >
                      Type
                    </th>
                    <th
                      scope="col"
                      class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-gray-100"
                    >
                      Domain
                    </th>
                    <th
                      scope="col"
                      class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-gray-100"
                    >
                      Value
                    </th>
                    <th
                      scope="col"
                      class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-gray-100"
                    >
                      Priority
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white dark:bg-gray-800">
                  <%= for {title, {field, rows}} <- @sections do %>
                    <tr class="border-t border-gray-200 dark:border-gray-700">
                      <th
                        colspan="5"
                        scope="colgroup"
                        class="bg-gray-50 dark:bg-gray-800 px-4 py-2 text-left text-sm font-semibold text-gray-900 dark:text-gray-100 sm:px-6"
                      >
                        <span class="inline-flex items-center">
                          {title}
                          <%= if Map.get(@verified, field) do %>
                            <div x-init x-tooltip.raw="Verified" class="ml-2">
                              <.icon name={:check_circle} solid class="h-5 w-5 text-green-400" />
                            </div>
                          <% else %>
                            <div x-init x-tooltip.raw="Waiting for DNS records" class="ml-2">
                              <.icon name={:ellipsis_horizontal} solid class="h-5 w-5 animate-pulse" />
                            </div>
                          <% end %>
                        </span>
                      </th>
                    </tr>
                    <tr
                      :for={record <- rows}
                      class={"border-t border-gray-300 dark:border-gray-600 " <> if Map.get(@verified, field, false), do: "bg-green-50 dark:bg-green-900/20", else: ""}
                    >
                      <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 dark:text-gray-100 sm:pl-6">
                        {record.type |> Atom.to_string() |> String.upcase()}
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                        {record.domain}
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400 flex items-center justify-start">
                        <pre class="bg-gray-100 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 font-mono p-1 shrink"><%= record.value %></pre>
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                        {record.priority}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

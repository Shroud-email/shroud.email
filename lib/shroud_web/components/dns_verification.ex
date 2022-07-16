defmodule ShroudWeb.Components.DnsVerification do
  use Surface.Component
  alias Shroud.Domain
  alias ShroudWeb.Components.Button

  prop domain, :any, required: true
  prop verifying, :boolean, required: true
  prop sections, :keyword, required: true
  prop verify, :event, required: true

  def render(assigns) do
    all_verified = Domain.fully_verified?(assigns.domain)

    verified =
      Enum.reduce(assigns.sections, %{}, fn {_title, {field, _rows}}, acc ->
        Map.put(acc, field, Domain.dns_record_verified?(assigns.domain, field))
      end)

    ~F"""
    <div>
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h3 class="text-lg font-semibold text-gray-900">DNS settings</h3>
          {#if !all_verified}
            <p class="mt-2 text-sm text-gray-700">
              Add the following DNS records to activate your domain.
            </p>
            <p class="text-sm text-gray-700">
              DNS propagation can take up to 24 hours. Once you've added these records, you can sit back and relax: we'll email you when your domain is verified.
            </p>
          {/if}
        </div>
        <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
          <Button
            :if={not all_verified}
            disabled={@verifying}
            click={@verify}
            text="Verify"
            icon={Heroicons.Outline.RefreshIcon}
          />
        </div>
      </div>
      <div class="mt-4 flex flex-col">
        <div class="-my-2 -mx-4 overflow-x-auto sm:-mx-6 lg:-mx-8">
          <div class="inline-block min-w-full py-2 align-middle md:px-6 lg:px-8">
            <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
              <table class="min-w-full">
                <thead class="bg-white">
                  <tr>
                    <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6">Type</th>
                    <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Domain</th>
                    <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Value</th>
                    <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Priority</th>
                  </tr>
                </thead>
                <tbody class="bg-white">
                  {#for {title, {field, rows}} <- @sections}
                    <tr class="border-t border-gray-200">
                      <th
                        colspan="5"
                        scope="colgroup"
                        class="bg-gray-50 px-4 py-2 text-left text-sm font-semibold text-gray-900 sm:px-6 flex items-center"
                      >
                        {title}
                        {#if Map.get(verified, field)}
                          <div x-init x-tooltip.raw="Verified" class="ml-2">
                            <Heroicons.Solid.CheckCircleIcon class="h-5 w-5 text-green-400" />
                          </div>
                        {#else}
                          <div x-init x-tooltip.raw="Waiting for DNS records" class="ml-2">
                            <Heroicons.Solid.DotsHorizontalIcon class="h-5 w-5 animate-pulse" />
                          </div>
                        {/if}
                      </th>
                    </tr>
                    <tr
                      :for={record <- rows}
                      class={"border-t border-gray-300 " <> if Map.get(verified, field, false), do: "bg-green-50", else: ""}
                    >
                      <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-6">{record.type |> Atom.to_string() |> String.upcase()}</td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">{record.domain}</td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 flex items-center justify-start">
                        <pre class="bg-gray-100 border border-gray-200 font-mono p-1 shrink">{record.value}</pre>
                      </td>
                      <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">{record.priority}</td>
                    </tr>
                  {/for}
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

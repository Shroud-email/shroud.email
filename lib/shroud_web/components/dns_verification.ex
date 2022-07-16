defmodule ShroudWeb.Components.DnsVerification do
  use Surface.Component
  alias Shroud.Domain
  alias ShroudWeb.Components.Button

  prop domain, :any, required: true
  prop verifying, :boolean, required: true
  prop field, :atom, required: true
  prop title, :string, required: true
  prop records, :list, required: true
  prop verify, :event, required: true

  def render(assigns) do
    verified = Domain.dns_record_verified?(assigns.domain, assigns.field)

    ~F"""
    <div class={"bg-white rounded " <> if verified, do: "opacity-50", else: ""}>
      <div class="border-b border-gray-200 px-4 py-2 sm:px-6">
        <h3 class="font-medium text-gray-900 flex items-center">
          {@title}
          {#if verified}
            <div x-init x-tooltip.raw="DNS records verified">
              <Heroicons.Solid.CheckCircleIcon class="h-4 w-4 text-green-500 ml-2" />
            </div>
          {#else}
            <div x-init x-tooltip.raw="Waiting for DNS records">
              <Heroicons.Solid.DotsHorizontalIcon class="h-4 w-4 text-gray-500 ml-2 animate-pulse" />
            </div>
          {/if}
        </h3>
      </div>
      <div class="px-4 py-2 pb-4 sm:px-6">
        <div class="-mx-4 flex flex-col sm:-mx-6 md:mx-0">
          <table class="min-w-full divide-y divide-gray-300">
            <thead>
              <tr>
                <th
                  scope="col"
                  class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6 md:pl-0 w-[20%]"
                >Record</th>
                <th
                  scope="col"
                  class="hidden py-3.5 px-3 text-right text-sm font-semibold text-gray-900 sm:table-cell w-[30%]"
                >Domain</th>
                <th
                  scope="col"
                  class="py-3.5 pl-3 pr-4 text-right text-sm font-semibold text-gray-900 sm:pr-6 md:pr-0"
                >Value</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={dns_record <- @records} class="border-b border-gray-200">
                <td class="py-4 pl-4 pr-3 text-sm sm:pl-6 md:pl-0">
                  <div class="font-medium text-gray-900">{dns_record.type |> Atom.to_string() |> String.upcase()}</div>
                  <div class="mt-0.5 text-gray-500 sm:hidden">{dns_record.domain}</div>
                </td>
                <td class="hidden py-4 px-3 text-right text-sm text-gray-900 sm:table-cell">{dns_record.domain}</td>
                <td class="py-4 pl-3 pr-4 text-right text-sm text-gray-800 sm:pr-6 md:pr-0">
                  <pre class="ml-auto w-min font-mono px-3 py-1 bg-gray-50 border border-gray-100 rounded-sm">{dns_record.value}</pre>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="flex justify-between items-center mt-6">
          <p class="text-gray-700 mr-3">
            {#if verified}
              Your DNS records have been verified!
            {#else}
              Please add the above DNS records to your domain.
            {/if}
          </p>
          <Button
            :if={!verified}
            disabled={@verifying}
            click={@verify}
            text="Verify"
            icon={Heroicons.Outline.RefreshIcon}
          />
        </div>
      </div>
    </div>
    """
  end
end

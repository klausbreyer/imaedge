defmodule ImaedgeWeb.AdminHTML do
  @moduledoc """
  This module contains the admin usage page rendered by AdminController.
  """
  use ImaedgeWeb, :html

  alias Imaedge.Media.Collection

  embed_templates "admin_html/*"

  def display_collection_name(collection) do
    Collection.display_name(collection)
  end

  def format_bytes(nil), do: "0 B"
  def format_bytes(%Decimal{} = bytes), do: bytes |> Decimal.to_integer() |> format_bytes()
  def format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"

  def format_bytes(bytes) when bytes < 1_048_576 do
    "#{format_number(bytes / 1_024)} KiB"
  end

  def format_bytes(bytes) when bytes < 1_073_741_824 do
    "#{format_number(bytes / 1_048_576)} MiB"
  end

  def format_bytes(bytes) do
    "#{format_number(bytes / 1_073_741_824)} GiB"
  end

  def format_number(number) when is_float(number) do
    :erlang.float_to_binary(number, decimals: 1)
  end

  def format_number(number) when is_integer(number), do: Integer.to_string(number)

  def format_percent(value) when is_float(value) do
    "#{round(value * 100)}%"
  end

  def format_percent(_value), do: "0%"

  def format_date(nil), do: "never"

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  def format_datetime(nil), do: "never"

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  def days_label(:all), do: "all time"
  def days_label(days), do: "last #{days} days"

  def filter_link_class(current, target) do
    base =
      "inline-flex h-8 items-center justify-center rounded-[3px] border px-3 font-brand-sans text-[12px] font-medium leading-none transition-colors"

    if current == target do
      base <> " border-ink bg-ink text-paper"
    else
      base <> " border-black/[0.12] bg-white text-ink hover:border-ink"
    end
  end

  def truncate_text(nil), do: ""

  def truncate_text(text) when is_binary(text) do
    if String.length(text) > 140 do
      String.slice(text, 0, 140) <> "..."
    else
      text
    end
  end

  attr :rows, :list, required: true
  attr :label_key, :atom, required: true
  attr :value_label, :string, required: true
  attr :byte_label, :string, required: true

  def status_table(assigns) do
    ~H"""
    <div class="overflow-x-auto border-y border-black/[0.08]">
      <table class="min-w-[420px] w-full border-collapse font-brand-sans text-[13px] whitespace-nowrap">
        <thead>
          <tr class="border-b border-black/[0.08] text-left font-brand-mono text-[11px] uppercase tracking-[0.08em] text-mid">
            <th class="py-2.5 pr-4 font-medium">type</th>
            <th class="py-2.5 px-4 text-right font-medium">{@value_label}</th>
            <th class="py-2.5 pl-4 text-right font-medium">{@byte_label}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-black/[0.06]">
          <tr :for={row <- @rows}>
            <td class="py-2.5 pr-4">{Map.get(row, @label_key) || "unknown"}</td>
            <td class="py-2.5 px-4 text-right">{Map.get(row, :images) || Map.get(row, :count)}</td>
            <td class="py-2.5 pl-4 text-right font-brand-mono text-[12px]">
              {format_bytes(row.bytes)}
            </td>
          </tr>
          <tr :if={@rows == []}>
            <td colspan="3" class="py-5 text-mid">No rows.</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :compact?, :boolean, default: false

  def collection_table(assigns) do
    ~H"""
    <div class="overflow-x-auto border-y border-black/[0.08]">
      <table class="min-w-[1120px] w-full border-collapse font-brand-sans text-[13px] whitespace-nowrap">
        <thead>
          <tr class="border-b border-black/[0.08] text-left font-brand-mono text-[11px] uppercase tracking-[0.08em] text-mid">
            <th class="py-2.5 pr-4 font-medium">collection</th>
            <th class="py-2.5 px-4 text-right font-medium">storage</th>
            <th class="py-2.5 px-4 text-right font-medium">images</th>
            <th class="py-2.5 px-4 text-right font-medium">uploads</th>
            <th class="py-2.5 px-4 text-right font-medium">contributors</th>
            <th class="py-2.5 px-4 text-right font-medium">top share</th>
            <th class="py-2.5 px-4 text-right font-medium">failed</th>
            <th class="py-2.5 px-4 text-right font-medium">active</th>
            <th class="py-2.5 px-4 text-right font-medium">first</th>
            <th class="py-2.5 pl-4 text-right font-medium">last</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-black/[0.06]">
          <tr :for={row <- @rows}>
            <td class="py-2.5 pr-4">
              <.link
                class="font-medium text-ink underline decoration-black/20 underline-offset-2 hover:decoration-black"
                href={~p"/i/#{row.collection.public_id}"}
              >
                {display_collection_name(row.collection)}
              </.link>
              <div class="mt-0.5 font-brand-mono text-[11px] text-mid">
                {row.collection.public_id}
              </div>
            </td>
            <td class="py-2.5 px-4 text-right font-brand-mono text-[12px]">
              {format_bytes(row.accepted_bytes)}
            </td>
            <td class="py-2.5 px-4 text-right">{row.complete_images}/{row.image_count}</td>
            <td class="py-2.5 px-4 text-right">{row.upload_count}</td>
            <td class="py-2.5 px-4 text-right">{row.contributor_count}</td>
            <td class="py-2.5 px-4 text-right">{format_percent(row.top_contributor_share)}</td>
            <td class="py-2.5 px-4 text-right">{row.failed_uploads}</td>
            <td class="py-2.5 px-4 text-right">{row.active_uploads + row.processing_images}</td>
            <td class="py-2.5 px-4 text-right font-brand-mono text-[12px]">
              {format_datetime(row.first_activity_at)}
            </td>
            <td class="py-2.5 pl-4 text-right font-brand-mono text-[12px]">
              {format_datetime(row.last_activity_at)}
            </td>
          </tr>
          <tr :if={@rows == []}>
            <td colspan="10" class="py-5 text-mid">No collections.</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end

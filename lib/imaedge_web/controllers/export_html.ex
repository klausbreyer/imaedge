defmodule ImaedgeWeb.ExportHTML do
  use ImaedgeWeb, :html
  alias Imaedge.Media.Collection

  embed_templates "export_html/*"

  def download_name(image, index) do
    number = String.pad_leading(to_string(index), 4, "0")
    time = Calendar.strftime(image.effective_taken_at, "%Y%m%d-%H%M%S")
    name = Imaedge.Media.sanitize_filename(image.original_filename)
    "#{number}-#{time}-#{name}"
  end

  def format_absolute(nil), do: ""

  def format_absolute(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  def format_relative(nil), do: "-"

  def format_relative(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 5 -> "just now"
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds < 2_592_000 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end
end

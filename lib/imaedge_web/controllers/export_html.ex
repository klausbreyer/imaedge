defmodule ImaedgeWeb.ExportHTML do
  use ImaedgeWeb, :html

  embed_templates "export_html/*"

  def download_name(image, index) do
    number = String.pad_leading(to_string(index), 4, "0")
    time = Calendar.strftime(image.effective_taken_at, "%Y%m%d-%H%M%S")
    name = Imaedge.Media.sanitize_filename(image.original_filename)
    "#{number}-#{time}-#{name}"
  end
end

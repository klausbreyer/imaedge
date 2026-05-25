defmodule Imaedge.Media.ImageTest do
  use ExUnit.Case, async: true

  alias Imaedge.Media.Image

  test "public URL helpers prefer object keys over stored URLs" do
    image = %Image{
      original_key: "collections/abc/original.jpg",
      preview_small_key: "collections/abc/preview-small.webp",
      preview_large_key: "collections/abc/preview-large.webp",
      original_url: "https://old.example/original.jpg",
      preview_small_url: "https://old.example/preview-small.webp",
      preview_large_url: "https://old.example/preview-large.webp"
    }

    assert Image.public_original_url(image) == "/objects/collections/abc/original.jpg"
    assert Image.public_preview_small_url(image) == "/objects/collections/abc/preview-small.webp"
    assert Image.public_preview_large_url(image) == "/objects/collections/abc/preview-large.webp"
  end

  test "public URL helpers fall back to stored URLs when keys are missing" do
    image = %Image{
      original_url: "https://old.example/original.jpg",
      preview_small_url: "https://old.example/preview-small.webp",
      preview_large_url: "https://old.example/preview-large.webp"
    }

    assert Image.public_original_url(image) == "https://old.example/original.jpg"
    assert Image.public_preview_small_url(image) == "https://old.example/preview-small.webp"
    assert Image.public_preview_large_url(image) == "https://old.example/preview-large.webp"
  end
end

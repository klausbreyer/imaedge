defmodule Imaedge.Repo do
  use Ecto.Repo,
    otp_app: :imaedge,
    adapter: Ecto.Adapters.Postgres
end

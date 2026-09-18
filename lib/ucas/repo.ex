defmodule Ucas.Repo do
  use Ecto.Repo,
    otp_app: :ucas,
    adapter: Ecto.Adapters.Postgres
end

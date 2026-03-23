defmodule Flagex.TestRepo do
  use Ecto.Repo,
    otp_app: :flagex,
    adapter: Ecto.Adapters.Postgres
end

import Config

config :flagex,
  otp_app: :flagex,
  repo: Flagex.TestRepo

config :flagex, ecto_repos: [Flagex.TestRepo]

config :flagex, Flagex.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "flagex_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

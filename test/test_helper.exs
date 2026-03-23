ExUnit.start()

{:ok, _} = Flagex.TestRepo.start_link()

migrations_path = :code.priv_dir(:flagex) |> Path.join("migrations")
Ecto.Migrator.run(Flagex.TestRepo, migrations_path, :up, all: true)

Ecto.Adapters.SQL.Sandbox.mode(Flagex.TestRepo, :manual)

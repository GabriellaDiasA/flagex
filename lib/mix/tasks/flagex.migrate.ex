defmodule Mix.Tasks.Flagex.Migrate do
  use Mix.Task

  @shortdoc "Runs Flagex migrations against the configured repo"

  @moduledoc """
  Runs Flagex database migrations.

  This creates the `flagex_variables` and `flagex_variable_events` tables,
  along with the PostgreSQL trigger and notify function.

  ## Usage

      mix flagex.migrate

  ## Options

      --repo    The repo module to migrate (overrides config)

  The repo is read from your application config:

      config :flagex, repo: MyApp.Repo

  """

  @migrations_path :code.priv_dir(:flagex) |> Path.join("migrations")

  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [repo: :string])

    repo = resolve_repo(opts)

    Mix.Task.run("app.config")

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    repo_started? = repo in Ecto.Repo.all_running()

    unless repo_started? do
      {:ok, _} = repo.start_link(pool_size: 2)
    end

    case Ecto.Migrator.run(repo, @migrations_path, :up, all: true) do
      [] ->
        Mix.shell().info("Flagex migrations already up to date.")

      migrations ->
        for {version, name} <- migrations do
          Mix.shell().info("Ran migration #{version} (#{name})")
        end
    end
  end

  defp resolve_repo(opts) do
    cond do
      repo = opts[:repo] ->
        Module.concat([repo])

      repo = Application.get_env(:flagex, :repo) ->
        repo

      true ->
        Mix.raise("""
        No repo configured for Flagex. Either pass --repo or set:

            config :flagex, repo: MyApp.Repo
        """)
    end
  end
end

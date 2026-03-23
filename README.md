# Flagex

Runtime variable management.

## Usage

### Via Endpoint
- `GET    /                → list all enabled variables`
- `GET    /:name           → get a variable by name`
- `PATCH  /:name           → update a variable's value and/or description`
- `DELETE /:name           → disable a variable (soft delete)`
- `PATCH  /:name/reenable  → re-enable a disabled variable`
  
### Registering and accessing the Variables in code

Create the following module to register your Variables. This module will be referenced in `config.exs`, explained later
```elixir
defmodule MyApp.Variables do
  use Flagex.Variables

  variable :max_retries, default: "3", description: "Maximum retry attempts"
  variable :feature_x,   default: "enabled"
  variable :api_timeout, description: "External API timeout in ms"
end
```

Access them through the Flagex public API
```elixir
Flagex.get(:my_variable)
```

## Setup

### Dependency

If [available in Hex](https://hex.pm/docs/publish) (not yet!), the package can be installed
by adding `flagex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flagex, "~> 0.1.0"}
  ]
end
```

### Configuration

Add the following to your `config.exs`
```elixir
config :flagex,
  repo: MyApp.Repo,
  otp_app: :my_app,
  variables_module: MyApp.Variables,
  cache: true
```

### Routing

Add the following to your router module
```elixir
forward "/your-flagex-scope", Flagex.Router
```

### Migrations

Create a migration that calls `Flagex.Migrations.up/0` and `Flagex.Migrations.down/0`
```elixir
defmodule MyApp.Repo.Migrations.AddFlagex do
  use Ecto.Migration

  def up, do: Flagex.Migrations.up()

  def down, do: Flagex.Migrations.down()
end
```

The `flagex` application will wait for migrations to be up before synchronizing variables

### Thanks!

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/flagex>.

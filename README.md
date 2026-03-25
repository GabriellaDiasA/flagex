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

Add `flagex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flagex, github: "GabriellaDiasA/flagex"}
  ]
end
```

### Configuration

Add the following to your `config.exs`:
```elixir
# Required
config :flagex,
  repo: MyApp.Repo,
  otp_app: :my_app,
  variables_module: MyApp.Variables

# Optional: enable distributed cache (requires nebulex deps)
config :flagex, cache: true

# Optional: identity written to audit log when no actor is extracted from the request
config :flagex, default_actor: "my_app"

# Optional: extract actor identity from requests for the audit log
# Using internal JWT decoding:
config :flagex, actor_extraction: [header: "authorization", claim: "sub"]
# Or using a custom callback:
config :flagex, actor_extraction: {MyApp.Auth, :extract_actor, []}
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

The `flagex` application will wait for migrations to be up before synchronizing variables.

Alternatively, use the provided Mix task:

```bash
mix flagex.migrate
```

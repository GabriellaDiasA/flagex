defmodule Flagex do
  @moduledoc """
  Public API for interacting with Flagex variables at runtime.

  ## Reading variables

  Reads are served from the local ETS store (or Nebulex when clustering is
  enabled) and do not touch the database.

      Flagex.get(:my_var)         # → "some_value" | nil
      Flagex.fetch(:my_var)       # → {:ok, "some_value"} | {:error, :not_found}

  ## Writing variables

  Writes go to the database and propagate to all nodes via PostgreSQL NOTIFY.

      Flagex.put(:my_var, "new_value")
      Flagex.disable(:my_var)
      Flagex.reenable(:my_var)

  ## Listing variables

  `all/0` queries the database directly and returns full `%Flagex.Variable{}`
  structs, unlike the store which only holds name/value pairs.

  ## Atom vs string keys

  Variables declared via `use Flagex.Variables` register their atoms at compile
  time, making `Flagex.get(:atom)` safe. Variables created at runtime through
  the management API are only accessible via string keys (`Flagex.get("name")`)
  until a redeploy that includes their declaration.
  """

  alias Flagex.{Variable, VariableEvent}

  @type name :: atom() | String.t()

  @doc "Returns a child spec so Flagex can be added to a supervision tree as `{Flagex, []}`."
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(_opts \\ []) do
    Flagex.Application.start(:normal, [])
  end

  # ---------------------------------------------------------------------------
  # Reads — served from local store, no DB hit
  # ---------------------------------------------------------------------------

  @doc "Returns the value for a variable, or nil if absent or disabled."
  @spec get(name()) :: String.t() | nil
  def get(name) when is_atom(name), do: Flagex.Store.get(Atom.to_string(name))
  def get(name) when is_binary(name), do: Flagex.Store.get(name)

  @doc """
  Returns `{:ok, value}` or `{:error, :not_found}` for a variable.

  Unlike `get/1`, correctly distinguishes a variable with `value: nil` from one
  that is absent or disabled.
  """
  @spec fetch(name()) :: {:ok, String.t() | nil} | {:error, :not_found}
  def fetch(name) when is_atom(name), do: fetch(Atom.to_string(name))
  def fetch(name) when is_binary(name), do: Flagex.Store.fetch(name)

  # ---------------------------------------------------------------------------
  # Reads — full structs from DB
  # ---------------------------------------------------------------------------

  @doc "Returns all enabled variables from the database."
  @spec all() :: [Variable.t()]
  def all do
    import Ecto.Query, only: [from: 2]
    repo().all(from(v in Variable, where: v.enabled == true))
  end

  # ---------------------------------------------------------------------------
  # Writes — persist to DB, propagate via NOTIFY
  # ---------------------------------------------------------------------------

  @doc """
  Updates one or both of a variable's `value` and `description` in a single
  operation.

  Returns `{:error, :not_found}` if the variable does not exist.
  Returns `{:error, changeset}` if the variable is disabled.
  """
  @spec update(name(), %{
          optional(:value) => String.t() | nil,
          optional(:description) => String.t() | nil
        }) ::
          {:ok, Variable.t()} | {:error, :not_found | :variable_disabled | Ecto.Changeset.t()}
  def update(name, attrs) when is_atom(name), do: update(Atom.to_string(name), attrs)

  def update(name, attrs) when is_binary(name) do
    with {:ok, %{enabled: true} = variable} <- fetch_variable(name) do
      changeset = Variable.update_changeset(variable, attrs)

      if changeset.changes == %{} do
        {:ok, variable}
      else
        run_operation(changeset, :update)
      end
    else
      {:ok, %{enabled: false}} -> {:error, :variable_disabled}
      err -> err
    end
  end

  @doc "Convenience wrapper around `update/2` for changing only the value."
  @spec put(name(), String.t() | nil) ::
          {:ok, Variable.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def put(name, value), do: update(name, %{value: value})

  @doc """
  Disables a variable (soft delete). The variable will be evicted from all
  node stores and `get/1` will return nil until it is re-enabled.
  """
  @spec disable(name()) ::
          {:ok, Variable.t() | :already_disabled} | {:error, :not_found | Ecto.Changeset.t()}
  def disable(name) when is_atom(name), do: disable(Atom.to_string(name))

  def disable(name) when is_binary(name) do
    with {:ok, %{enabled: true} = variable} <- fetch_variable(name) do
      changeset = Variable.disable_changeset(variable)
      run_operation(changeset, :disable)
    else
      {:ok, %{enabled: false}} -> {:ok, :already_disabled}
      err -> err
    end
  end

  @doc "Re-enables a previously disabled variable."
  @spec reenable(name()) ::
          {:ok, Variable.t() | :already_enabled} | {:error, :not_found | Ecto.Changeset.t()}
  def reenable(name) when is_atom(name), do: reenable(Atom.to_string(name))

  def reenable(name) when is_binary(name) do
    with {:ok, %{enabled: false} = variable} <- fetch_variable(name) do
      changeset = Variable.reenable_changeset(variable)
      run_operation(changeset, :reenable)
    else
      {:ok, %{enabled: true}} -> {:ok, :already_enabled}
      err -> err
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_variable(name) do
    case repo().get_by(Variable, name: name) do
      nil -> {:error, :not_found}
      variable -> {:ok, variable}
    end
  end

  # Shared Ecto.Multi pipeline for all write operations.
  # The event captures the variable's value *after* the update, so:
  #   - :update   → records the new value
  #   - :disable  → records the preserved value (disable_changeset only touches enabled)
  #   - :reenable → records the preserved value (reenable_changeset only touches enabled)
  defp run_operation(changeset, operation) do
    now = DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:variable, changeset)
    |> Ecto.Multi.insert(:event, fn %{variable: updated} ->
      VariableEvent.changeset(%VariableEvent{}, %{
        variable_id: updated.id,
        variable_name: updated.name,
        operation: operation,
        value: updated.value,
        changed_by: Process.get(:flagex_actor) || Application.get_env(:flagex, :default_actor, "client_application"),
        changed_at: now
      })
    end)
    |> repo().transaction()
    |> case do
      {:ok, %{variable: variable}} -> {:ok, variable}
      {:error, :variable, changeset, _} -> {:error, changeset}
      {:error, :event, changeset, _} -> {:error, {:event_failed, changeset}}
    end
  end

  defp repo, do: Flagex.Application.config!(:repo)
end

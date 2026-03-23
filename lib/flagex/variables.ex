defmodule Flagex.Variables do
  @moduledoc """
  Provides the `variable/2` macro for declaring Flagex variables in a client module.

  Declared variables are registered as atoms at compile time and upserted into
  the database when the global listener node starts. Existing values are never
  overwritten — the `default` option only applies on first insert.

  ## Usage

      defmodule MyApp.Variables do
        use Flagex.Variables

        variable :max_retries, default: "3", description: "Maximum retry attempts"
        variable :feature_x,   default: "enabled"
        variable :api_timeout, description: "External API timeout in ms"
      end

  Then in your config:

      config :flagex,
        otp_app: :my_app,
        repo: MyApp.Repo,
        variables_module: MyApp.Variables

  """

  defmacro __using__(_opts) do
    quote do
      import Flagex.Variables, only: [variable: 1, variable: 2]

      Module.register_attribute(__MODULE__, :flagex_variables, accumulate: true)

      @before_compile Flagex.Variables
    end
  end

  @doc """
  Declares a Flagex variable.

  ## Options

    * `:default`     - initial value inserted on first boot, ignored on subsequent starts
    * `:description` - human-readable description of the variable

  """
  defmacro variable(name, opts \\ []) when is_atom(name) do
    quote do
      # Referencing the atom as a literal ensures it is registered in the
      # atom table at compile time, making String.to_existing_atom/1 safe
      # at runtime for any code path that receives the name as a string.
      _ = unquote(name)

      @flagex_variables {unquote(name), unquote(opts)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc "Returns the list of variables declared in this module."
      def __flagex_variables__ do
        @flagex_variables |> Enum.reverse()
      end
    end
  end

  @doc """
  Upserts all variables declared in `module` into the database via `repo`.

  Called by `Flagex.Listener` only on the node that wins global listener
  registration. All inserts run inside a single transaction — if any variable
  or its corresponding CREATE event fails to insert, the entire sync rolls back.

  Existing rows are left untouched so runtime changes survive redeploys.
  """
  def sync(module, repo) do
    module.__flagex_variables__()
    |> register_variables()
    |> repo.transaction()
    |> case do
      {:ok, _results} ->
        :ok

      {:error, {step, name}, reason, _changes} ->
        {:error,
         "Flagex sync failed at step #{inspect(step)} for variable #{inspect(name)}: #{inspect(reason)}"}
    end
  end

  defp register_variables(variables) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:variables, variables)
    |> Ecto.Multi.merge(&register_variable/1)
  end

  defp register_variable(%{variables: variables}) do
    Enum.reduce(variables, Ecto.Multi.new(), fn {name, opts}, multi ->
      name_str = Atom.to_string(name)

      multi
      |> Ecto.Multi.run({:get, name_str}, fn repo, _changes ->
        {:ok, repo.get_by(Flagex.Variable, name: name_str)}
      end)
      |> Ecto.Multi.run({:create, name_str}, fn
        repo, %{{:get, ^name_str} => nil} ->
          %Flagex.Variable{}
          |> Flagex.Variable.changeset(%{
            name: name_str,
            value: opts[:default],
            description: opts[:description]
          })
          |> repo.insert()

        _repo, %{{:get, ^name_str} => _variable} ->
          {:ok, :skipped}
      end)
      |> Ecto.Multi.run({:event, name_str}, fn
        _repo, %{{:create, ^name_str} => :skipped} ->
          {:ok, :skipped}

        repo, %{{:create, ^name_str} => variable} ->
          %Flagex.VariableEvent{}
          |> Flagex.VariableEvent.changeset(%{
            variable_id: variable.id,
            variable_name: name_str,
            operation: :create,
            value: variable.value,
            changed_at: DateTime.utc_now()
          })
          |> repo.insert()
      end)
    end)
  end
end

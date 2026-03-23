defmodule Flagex.Store do
  use GenServer

  @table :flagex_store
  @pt_key {__MODULE__, :nebulex_enabled}

  # ---------------------------------------------------------------------------
  # Client API — reads hit ETS directly, writes go through the GenServer.
  # When Nebulex is enabled, all operations delegate to Flagex.Cache instead,
  # and the ETS GenServer idles unused.
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the value for a variable by name, or nil if absent or disabled."
  def get(name) when is_binary(name) do
    if nebulex_enabled?() do
      apply(Flagex.Cache, :get, [name])
    else
      case :ets.lookup(@table, name) do
        [{^name, value}] -> value
        [] -> nil
      end
    end
  end

  @doc """
  Returns `{:ok, value}` if the variable is present in the store (value may be
  nil), or `{:error, :not_found}` if it is absent or disabled.
  """
  def fetch(name) when is_binary(name) do
    if nebulex_enabled?() do
      if apply(Flagex.Cache, :has_key?, [name]) do
        {:ok, apply(Flagex.Cache, :get, [name])}
      else
        {:error, :not_found}
      end
    else
      case :ets.lookup(@table, name) do
        [{^name, value}] -> {:ok, value}
        [] -> {:error, :not_found}
      end
    end
  end

  @doc "Inserts or updates a variable in the store."
  def put(name, value) when is_binary(name) do
    if nebulex_enabled?() do
      apply(Flagex.Cache, :put, [name, value])
    else
      GenServer.call(__MODULE__, {:put, name, value})
    end
  end

  @doc "Removes a variable from the store (called on disable)."
  def delete(name) when is_binary(name) do
    if nebulex_enabled?() do
      apply(Flagex.Cache, :delete, [name])
    else
      GenServer.call(__MODULE__, {:delete, name})
    end
  end

  @doc """
  Bulk-loads a list of `{name, value}` pairs into the store.
  Called on warm — replaces any existing entries with the same name.
  """
  def load(entries) when is_list(entries) do
    if nebulex_enabled?() do
      apply(Flagex.Cache, :put_all, [entries])
    else
      GenServer.call(__MODULE__, {:load, entries})
    end
  end

  @doc "Returns all `{name, value}` pairs currently in the store. Only available in ETS mode."
  def all do
    if nebulex_enabled?() do
      raise "Flagex.Store.all/0 is not supported in Nebulex mode"
    else
      :ets.tab2list(@table)
    end
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:put, name, value}, _from, state) do
    :ets.insert(@table, {name, value})
    {:reply, :ok, state}
  end

  def handle_call({:delete, name}, _from, state) do
    :ets.delete(@table, name)
    {:reply, :ok, state}
  end

  def handle_call({:load, entries}, _from, state) do
    :ets.insert(@table, entries)
    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Result is written once at application start via Flagex.Application and
  # stored in persistent_term, making this check O(1) on every store operation.
  defp nebulex_enabled? do
    :persistent_term.get(@pt_key, false)
  end
end

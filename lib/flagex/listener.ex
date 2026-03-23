defmodule Flagex.Listener do
  use GenServer
  require Logger

  import Ecto.Query, only: [from: 2]

  @global_name :flagex_listener
  @channel "flagex"

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    repo = Flagex.Application.config!(:repo)
    {:ok, %{repo: repo}, {:continue, :await_migrations}}
  end

  @impl GenServer
  def handle_continue(:await_migrations, %{repo: repo} = state) do
    case Ecto.Adapters.SQL.query(repo, "SELECT 1 FROM flagex_variables LIMIT 0", []) do
      {:ok, _} ->
        elect_and_start(repo, state)

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        Logger.warning("[Flagex] Waiting for migrations to run...")
        Process.send_after(self(), :await_migrations, 2_000)
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  # Received from Postgrex.Notifications on every NOTIFY on the flagex channel
  @impl GenServer
  def handle_info({:notification, _conn, _ref, @channel, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"name" => name, "value" => value, "enabled" => true}} ->
        Flagex.Store.put(name, value)

      {:ok, %{"name" => name, "enabled" => false}} ->
        Flagex.Store.delete(name)

      {:error, reason} ->
        Logger.warning("[Flagex.Listener] Malformed notification payload: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info(:await_migrations, %{repo: repo} = state) do
    case Ecto.Adapters.SQL.query(repo, "SELECT 1 FROM flagex_variables LIMIT 0", []) do
      {:ok, _} ->
        elect_and_start(repo, state)

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        Process.send_after(self(), :await_migrations, 2_000)
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  # Primary died — race to take over
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %{role: :replica} = state) do
    repo = state.repo

    case :global.register_name(@global_name, self()) do
      :yes ->
        case promote_to_primary(repo) do
          {:ok, pid} ->
            {:noreply, %{state | role: :primary, notification_pid: pid}}

          {:error, reason} ->
            Logger.error("[Flagex.Listener] Promotion to primary failed: #{inspect(reason)}")
            {:stop, reason, state}
        end

      :no ->
        # Another node won the race; monitor the new primary
        monitor_global()
        {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Init helpers
  # ---------------------------------------------------------------------------

  defp init_primary(repo) do
    with :ok <- maybe_sync(repo),
         {:ok, pid} <- start_notifications(repo),
         {:ok, _ref} <- Postgrex.Notifications.listen(pid, @channel),
         :ok <- warm_store(repo) do
      {:ok, %{role: :primary, notification_pid: pid, repo: repo}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp init_replica(repo) do
    monitor_global()
    :ok = warm_store(repo)
    {:ok, %{role: :replica, notification_pid: nil, repo: repo}}
  end

  defp promote_to_primary(repo) do
    with :ok <- maybe_sync(repo),
         {:ok, pid} <- start_notifications(repo),
         {:ok, _ref} <- Postgrex.Notifications.listen(pid, @channel),
         :ok <- warm_store(repo) do
      {:ok, pid}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp elect_and_start(repo, state) do
    case :global.register_name(@global_name, self()) do
      :yes ->
        case init_primary(repo) do
          {:ok, new_state} -> {:noreply, new_state}
          {:stop, reason} -> {:stop, reason, state}
        end

      :no ->
        {:ok, new_state} = init_replica(repo)
        {:noreply, new_state}
    end
  end

  defp maybe_sync(repo) do
    case Application.get_env(:flagex, :variables_module) do
      nil -> :ok
      module -> Flagex.Variables.sync(module, repo)
    end
  end

  defp warm_store(repo) do
    entries =
      repo.all(
        from(v in Flagex.Variable,
          where: v.enabled == true,
          select: {v.name, v.value}
        )
      )

    Flagex.Store.load(entries)
  end

  defp start_notifications(repo) do
    otp_app = Flagex.Application.config!(:otp_app)
    config = Application.get_env(otp_app, repo, [])
    Postgrex.Notifications.start_link(config)
  end

  # Monitors the current global primary. If the primary is already gone by
  # the time we look it up (race between :no and monitoring), we send a
  # synthetic :DOWN to ourselves to immediately re-trigger the election.
  defp monitor_global do
    case :global.whereis_name(@global_name) do
      :undefined ->
        send(self(), {:DOWN, nil, :process, nil, :primary_not_found})

      pid ->
        Process.monitor(pid)
    end
  end
end

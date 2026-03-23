defmodule Flagex.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    config!(:repo)
    config!(:otp_app)

    nebulex_on = Code.ensure_loaded?(Nebulex) && Application.get_env(:flagex, :cache)

    :persistent_term.put({Flagex.Store, :nebulex_enabled}, nebulex_on)

    children = [Flagex.Store] ++ cache_children(nebulex_on) ++ [Flagex.Listener]

    Supervisor.start_link(children, strategy: :one_for_one, name: Flagex.Supervisor)
  end

  @doc false
  def config!(key) do
    case Application.get_env(:flagex, key) do
      nil ->
        raise ArgumentError, """
        Missing required Flagex configuration: #{inspect(key)}

        Add the following to your config:

            config :flagex, #{key}: <value>
        """

      value ->
        value
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp cache_children(true), do: [Flagex.Cache]
  defp cache_children(_), do: []
end

defmodule Flagex.Plug.ExtractActor do
  @moduledoc """
  Extracts an actor identity from the request and stores it in `conn.private[:flagex_actor]`.

  Activated by the `:actor_extraction` config key. When absent, this plug is a no-op.

  ## Configuration

      # Internal JWT decoding:
      config :flagex,
        actor_extraction: [header: "authorization", claim: "sub"]

      # Custom callback (receives conn, returns {:ok, actor} | {:error, reason}):
      config :flagex,
        actor_extraction: {MyApp.Auth, :extract_actor, []}

  Responds with 401 JSON if extraction fails.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:flagex, :actor_extraction) do
      nil -> conn
      _config -> conn  # internal/callback paths added in next tasks
    end
  end
end

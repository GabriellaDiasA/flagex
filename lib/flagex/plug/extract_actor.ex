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
      _config when conn.method in ["GET", "HEAD"] -> conn
      config when is_list(config) -> extract_from_jwt(conn, config)
      {mod, fun, args} -> extract_from_callback(conn, mod, fun, args)
    end
  end

  defp extract_from_jwt(conn, config) do
    header = Keyword.get(config, :header, "authorization")
    claim = Keyword.fetch!(config, :claim)

    with [raw] <- get_req_header(conn, header),
         token = String.replace_prefix(raw, "Bearer ", ""),
         [_header_seg, payload_seg, _sig] <- String.split(token, "."),
         {:ok, decoded} <- Base.url_decode64(payload_seg, padding: false),
         {:ok, claims} <- Jason.decode(decoded),
         actor when not is_nil(actor) <- Map.get(claims, claim) do
      put_private(conn, :flagex_actor, actor)
    else
      _ -> halt_unauthorized(conn)
    end
  end

  defp extract_from_callback(conn, mod, fun, args) do
    case apply(mod, fun, [conn | args]) do
      {:ok, actor} -> put_private(conn, :flagex_actor, actor)
      {:error, _} -> halt_unauthorized(conn)
    end
  end

  defp halt_unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end

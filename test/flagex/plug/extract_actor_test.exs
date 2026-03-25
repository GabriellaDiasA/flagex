defmodule Flagex.Plug.ExtractActorTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Flagex.Plug.ExtractActor

  @opts ExtractActor.init([])

  # Helper to build a minimal conn
  defp call(conn), do: ExtractActor.call(conn, @opts)

  # Helper to build a JWT with given payload claims (base64url, no sig verification)
  defp make_jwt(claims) do
    header = Base.url_encode64("{}", padding: false)
    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    "#{header}.#{payload}.fakesig"
  end

  describe "no-op when actor_extraction not configured" do
    setup do
      Application.delete_env(:flagex, :actor_extraction)
      :ok
    end

    test "passes conn through unchanged" do
      input = conn(:get, "/")
      result = call(input)
      assert result.status == nil
      assert result.halted == false
      assert result.private[:flagex_actor] == nil
    end
  end
end

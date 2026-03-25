defmodule Flagex.Plug.ExtractActorTest do
  use ExUnit.Case, async: false

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

  describe "internal JWT path" do
    setup do
      Application.put_env(:flagex, :actor_extraction, header: "authorization", claim: "sub")
      on_exit(fn -> Application.delete_env(:flagex, :actor_extraction) end)
      :ok
    end

    test "extracts claim from valid JWT and stores in conn.private" do
      token = make_jwt(%{"sub" => "alice@example.com"})
      result = conn(:patch, "/my_var") |> put_req_header("authorization", "Bearer #{token}") |> call()
      assert result.halted == false
      assert result.private[:flagex_actor] == "alice@example.com"
    end

    test "works without Bearer prefix" do
      token = make_jwt(%{"sub" => "alice@example.com"})
      result = conn(:patch, "/my_var") |> put_req_header("authorization", token) |> call()
      assert result.halted == false
      assert result.private[:flagex_actor] == "alice@example.com"
    end

    test "halts with 401 when header is missing" do
      result = conn(:patch, "/my_var") |> call()
      assert result.halted == true
      assert result.status == 401
      assert Jason.decode!(result.resp_body) == %{"error" => "unauthorized"}
    end

    test "halts with 401 when JWT has wrong number of segments" do
      result = conn(:patch, "/my_var") |> put_req_header("authorization", "notajwt") |> call()
      assert result.halted == true
      assert result.status == 401
    end

    test "halts with 401 when payload is invalid base64" do
      result =
        conn(:patch, "/my_var")
        |> put_req_header("authorization", "header.!!!invalid!!!.sig")
        |> call()

      assert result.halted == true
      assert result.status == 401
    end

    test "halts with 401 when payload is not valid JSON" do
      bad_payload = Base.url_encode64("not json", padding: false)
      result =
        conn(:patch, "/my_var")
        |> put_req_header("authorization", "header.#{bad_payload}.sig")
        |> call()

      assert result.halted == true
      assert result.status == 401
    end

    test "halts with 401 when configured claim is absent from payload" do
      token = make_jwt(%{"email" => "alice@example.com"})
      result = conn(:patch, "/my_var") |> put_req_header("authorization", "Bearer #{token}") |> call()
      assert result.halted == true
      assert result.status == 401
    end

    test "uses configured header name" do
      Application.put_env(:flagex, :actor_extraction, header: "x-api-token", claim: "sub")
      token = make_jwt(%{"sub" => "alice@example.com"})
      result = conn(:patch, "/my_var") |> put_req_header("x-api-token", token) |> call()
      assert result.private[:flagex_actor] == "alice@example.com"
    end
  end

  describe "callback path" do
    setup do
      on_exit(fn -> Application.delete_env(:flagex, :actor_extraction) end)
      :ok
    end

    test "stores actor when callback returns {:ok, actor}" do
      Application.put_env(:flagex, :actor_extraction, {__MODULE__, :ok_callback, []})
      result = conn(:patch, "/my_var") |> call()
      assert result.halted == false
      assert result.private[:flagex_actor] == "callback_user"
    end

    test "halts with 401 when callback returns {:error, reason}" do
      Application.put_env(:flagex, :actor_extraction, {__MODULE__, :error_callback, []})
      result = conn(:patch, "/my_var") |> call()
      assert result.halted == true
      assert result.status == 401
    end

    # Callback stubs used above
    def ok_callback(_conn), do: {:ok, "callback_user"}
    def error_callback(_conn), do: {:error, :unauthorized}
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

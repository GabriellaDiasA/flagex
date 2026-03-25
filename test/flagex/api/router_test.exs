defmodule Flagex.API.RouterTest do
  use Flagex.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias Flagex.Variable

  @opts Flagex.Router.init([])

  defp call(method, path, body \\ nil) do
    conn =
      conn(method, path, body && Jason.encode!(body))
      |> put_req_header("content-type", "application/json")

    Flagex.Router.call(conn, @opts)
  end

  defp response_body(conn), do: Jason.decode!(conn.resp_body)

  defp insert_variable(attrs \\ %{}) do
    defaults = %{name: "my_var", value: "on"}

    %Variable{}
    |> Variable.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp make_jwt(claims) do
    header = Base.url_encode64("{}", padding: false)
    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    "#{header}.#{payload}.fakesig"
  end

  defp call_with_jwt(method, path, body \\ nil) do
    token = make_jwt(%{"sub" => "jwt_user@example.com"})

    conn =
      conn(method, path, body && Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    Flagex.Router.call(conn, @opts)
  end

  describe "GET /" do
    test "returns 200 with list of enabled variables" do
      insert_variable(%{name: "enabled_var"})
      insert_variable(%{name: "disabled_var"})
      Flagex.disable("disabled_var")

      conn = call(:get, "/")

      assert conn.status == 200
      names = response_body(conn) |> Enum.map(& &1["name"])
      assert "enabled_var" in names
      refute "disabled_var" in names
    end

    test "returns empty list when no enabled variables" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert response_body(conn) == []
    end
  end

  describe "GET /:name" do
    test "returns 200 with variable" do
      insert_variable()
      conn = call(:get, "/my_var")
      assert conn.status == 200
      assert response_body(conn)["name"] == "my_var"
      assert response_body(conn)["value"] == "on"
    end

    test "returns 404 for unknown variable" do
      conn = call(:get, "/unknown")
      assert conn.status == 404
    end

    test "returns disabled variable when fetched by name" do
      insert_variable()
      Flagex.disable("my_var")
      conn = call(:get, "/my_var")
      assert conn.status == 200
      refute response_body(conn)["enabled"]
    end
  end

  describe "PATCH /:name" do
    test "returns 200 with updated variable" do
      insert_variable()
      conn = call(:patch, "/my_var", %{value: "off"})
      assert conn.status == 200
      assert response_body(conn)["value"] == "off"
    end

    test "updates both value and description in one request" do
      insert_variable()
      conn = call(:patch, "/my_var", %{value: "off", description: "updated"})
      assert conn.status == 200
      body = response_body(conn)
      assert body["value"] == "off"
      assert body["description"] == "updated"
    end

    test "returns 404 for unknown variable" do
      conn = call(:patch, "/unknown", %{value: "x"})
      assert conn.status == 404
    end

    test "returns 422 when updating a disabled variable" do
      insert_variable()
      Flagex.disable("my_var")
      conn = call(:patch, "/my_var", %{value: "new"})
      assert conn.status == 422
      assert response_body(conn)["error"] == "variable is disabled"
    end
  end

  describe "DELETE /:name" do
    test "returns 200 and disables the variable" do
      insert_variable()
      conn = call(:delete, "/my_var")
      assert conn.status == 200
      refute response_body(conn)["enabled"]
      refute Repo.get_by!(Variable, name: "my_var").enabled
    end

    test "returns 404 for unknown variable" do
      conn = call(:delete, "/unknown")
      assert conn.status == 404
    end

    test "returns 200 when variable is already disabled" do
      insert_variable()
      Flagex.disable("my_var")
      conn = call(:delete, "/my_var")
      assert conn.status == 200
      assert response_body(conn)["message"] == "variable is already disabled"
    end
  end

  describe "PATCH /:name/reenable" do
    test "returns 200 and re-enables the variable" do
      insert_variable()
      Flagex.disable("my_var")
      conn = call(:patch, "/my_var/reenable")
      assert conn.status == 200
      assert response_body(conn)["enabled"]
    end

    test "returns 200 when variable is already enabled" do
      insert_variable()
      conn = call(:patch, "/my_var/reenable")
      assert conn.status == 200
      assert response_body(conn)["message"] == "variable is already enabled"
    end

    test "returns 404 for unknown variable" do
      conn = call(:patch, "/unknown/reenable")
      assert conn.status == 404
    end
  end

  describe "changed_by via controller bridge" do
    setup do
      on_exit(fn -> Process.delete(:flagex_actor) end)
      :ok
    end

    test "PATCH /:name records changed_by from conn.private" do
      insert_variable()

      conn =
        conn(:patch, "/my_var", Jason.encode!(%{value: "off"}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Conn.put_private(:flagex_actor, "test_user")

      Flagex.Router.call(conn, @opts)

      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :update)
      assert event.changed_by == "test_user"
    end

    test "DELETE /:name records changed_by from conn.private" do
      insert_variable()

      conn =
        conn(:delete, "/my_var")
        |> Plug.Conn.put_private(:flagex_actor, "test_user")

      Flagex.Router.call(conn, @opts)

      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :disable)
      assert event.changed_by == "test_user"
    end

    test "PATCH /:name/reenable records changed_by from conn.private" do
      insert_variable()
      Flagex.disable("my_var")

      conn =
        conn(:patch, "/my_var/reenable")
        |> Plug.Conn.put_private(:flagex_actor, "test_user")

      Flagex.Router.call(conn, @opts)

      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :reenable)
      assert event.changed_by == "test_user"
    end
  end

  describe "unknown routes" do
    test "returns 404 for unmatched path" do
      conn = call(:get, "/a/b/c")
      assert conn.status == 404
      assert response_body(conn)["error"] == "not found"
    end

    test "returns 404 for unmatched method" do
      conn = call(:post, "/my_var")
      assert conn.status == 404
    end
  end

  describe "actor extraction via router (integration)" do
    setup do
      Application.put_env(:flagex, :actor_extraction, header: "authorization", claim: "sub")
      on_exit(fn -> Application.delete_env(:flagex, :actor_extraction) end)
      :ok
    end

    test "PATCH /:name records JWT claim as changed_by" do
      insert_variable()
      conn = call_with_jwt(:patch, "/my_var", %{value: "off"})
      assert conn.status == 200
      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :update)
      assert event.changed_by == "jwt_user@example.com"
    end

    test "DELETE /:name records JWT claim as changed_by" do
      insert_variable()
      conn = call_with_jwt(:delete, "/my_var")
      assert conn.status == 200
      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :disable)
      assert event.changed_by == "jwt_user@example.com"
    end

    test "PATCH /:name/reenable records JWT claim as changed_by" do
      insert_variable()
      Flagex.disable("my_var")
      conn = call_with_jwt(:patch, "/my_var/reenable")
      assert conn.status == 200
      event = Repo.get_by!(Flagex.VariableEvent, variable_name: "my_var", operation: :reenable)
      assert event.changed_by == "jwt_user@example.com"
    end

    test "returns 401 for write request without authorization header" do
      insert_variable()
      conn = call(:patch, "/my_var", %{value: "off"})
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "returns 401 for delete request without authorization header" do
      insert_variable()
      conn = call(:delete, "/my_var")
      assert conn.status == 401
    end

    test "GET requests pass through without authorization header" do
      insert_variable()
      conn = call(:get, "/my_var")
      assert conn.status == 200
    end
  end
end

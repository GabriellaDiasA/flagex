defmodule Flagex.API.Controller do
  @moduledoc false

  import Plug.Conn

  alias Flagex.Variable

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, _params) do
    json(conn, 200, Enum.map(Flagex.all(), &serialize/1))
  end

  def show(conn, %{"name" => name}) do
    case Flagex.find(name) do
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:ok, variable} -> json(conn, 200, serialize(variable))
    end
  end

  def update(conn, %{"name" => name} = params) do
    Process.put(:flagex_actor, conn.private[:flagex_actor])
    attrs = Map.take(params, ["value", "description"])

    case Flagex.update(name, attrs) do
      {:ok, variable} -> json(conn, 200, serialize(variable))
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:error, :variable_disabled} -> json(conn, 422, %{error: "variable is disabled"})
      {:error, changeset} -> json(conn, 400, %{errors: format_errors(changeset)})
    end
  end

  def disable(conn, %{"name" => name}) do
    Process.put(:flagex_actor, conn.private[:flagex_actor])

    case Flagex.disable(name) do
      {:ok, :already_disabled} -> json(conn, 200, %{message: "variable is already disabled"})
      {:ok, variable} -> json(conn, 200, serialize(variable))
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:error, changeset} -> json(conn, 400, %{errors: format_errors(changeset)})
    end
  end

  def reenable(conn, %{"name" => name}) do
    Process.put(:flagex_actor, conn.private[:flagex_actor])

    case Flagex.reenable(name) do
      {:ok, :already_enabled} -> json(conn, 200, %{message: "variable is already enabled"})
      {:ok, variable} -> json(conn, 200, serialize(variable))
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:error, changeset} -> json(conn, 400, %{errors: format_errors(changeset)})
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp serialize(%Variable{} = v) do
    %{
      id: v.id,
      name: v.name,
      value: v.value,
      description: v.description,
      enabled: v.enabled,
      inserted_at: v.inserted_at,
      updated_at: v.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

defmodule Flagex.API.Controller do
  @moduledoc false

  import Plug.Conn

  alias Flagex.Variable

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, _params) do
    import Ecto.Query, only: [from: 2]
    variables = repo().all(from(v in Variable, where: v.enabled == true))
    json(conn, 200, Enum.map(variables, &serialize/1))
  end

  def show(conn, %{"name" => name}) do
    case repo().get_by(Variable, name: name) do
      nil -> json(conn, 404, %{error: "variable not found"})
      variable -> json(conn, 200, serialize(variable))
    end
  end

  def update(conn, %{"name" => name} = params) do
    attrs = Map.take(params, ["value", "description"])

    case Flagex.update(name, attrs) do
      {:ok, variable} -> json(conn, 200, serialize(variable))
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:error, :variable_disabled} -> json(conn, 422, %{error: "variable is disabled"})
      {:error, changeset} -> json(conn, 400, %{errors: format_errors(changeset)})
    end
  end

  def disable(conn, %{"name" => name}) do
    case Flagex.disable(name) do
      {:ok, :already_disabled} -> json(conn, 200, %{message: "variable is already disabled"})
      {:ok, variable} -> json(conn, 200, serialize(variable))
      {:error, :not_found} -> json(conn, 404, %{error: "variable not found"})
      {:error, changeset} -> json(conn, 400, %{errors: format_errors(changeset)})
    end
  end

  def reenable(conn, %{"name" => name}) do
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

  defp repo, do: Flagex.Application.config!(:repo)
end

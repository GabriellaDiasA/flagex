defmodule Flagex.Router do
  @moduledoc """
  Plug router exposing the Flagex variable management API.

  Mount this in your Phoenix router using `forward`:

      forward "/flagex", Flagex.Router

  All routes return JSON. Actor identity extraction can be configured directly
  via `:actor_extraction` — see `Flagex.Plug.ExtractActor`. Other authentication
  and authorization concerns are handled by the client application's pipeline
  before forwarding to this router.

  ## Endpoints

      GET    /                → list all variables
      GET    /:name           → get a variable by name
      PATCH  /:name           → update a variable's value and/or description
      DELETE /:name           → disable a variable (soft delete)
      PATCH  /:name/reenable  → re-enable a disabled variable

  """

  use Plug.Router

  alias Flagex.API.Controller

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug Flagex.Plug.ExtractActor
  plug :dispatch

  get "/", do: Controller.index(conn, conn.params)

  get "/:name", do: Controller.show(conn, conn.params)
  patch "/:name/reenable", do: Controller.reenable(conn, conn.params)
  patch "/:name", do: Controller.update(conn, conn.params)
  delete "/:name", do: Controller.disable(conn, conn.params)

  match _ do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not found"}))
  end
end

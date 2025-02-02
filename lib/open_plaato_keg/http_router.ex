defmodule OpenPlaatoKeg.HttpRouter do
  use Plug.Router
  alias OpenPlaatoKeg.Models.KegData

  plug(Plug.Static,
    at: "/",
    from: :open_plaato_keg
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json"],
    json_decoder: Poison
  )

  plug(:match)
  plug(:dispatch)

  get "api/kegs/devices" do
    data = KegData.devices()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/kegs" do
    data = KegData.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/kegs/:id" do
    case KegData.get(conn.params["id"]) do
      %{} = data when map_size(data) > 0 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(data))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Poison.encode!(%{error: "not_found"}))
    end
  end

  get "/api/metrics" do
    conn
    |> put_resp_content_type(:prometheus_text_format.content_type())
    |> send_resp(200, OpenPlaatoKeg.Metrics.scrape_data())
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(OpenPlaatoKeg.WebSocketHandler, [], timeout: :infinity)
    |> halt()
  end

  get "/api/alive" do
    send_resp(conn, 200, "1")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end

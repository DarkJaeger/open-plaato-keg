defmodule OpenPlaatoKeg.KegConnectionHandler do
  use ThousandIsland.Handler
  require Logger
  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  def handle_connection(_socket, _state) do
    {:ok, pid} = GenServer.start_link(OpenPlaatoKeg.KegDataProcessor, %{})
    Process.link(pid)

    state = %{keg_data_processor: pid, keg_id: nil}
    {:continue, state}
  end

  def handle_data(data, socket, state) do
    ThousandIsland.Socket.send(socket, BlynkProtocol.response_success())
    GenServer.cast(state.keg_data_processor, {:keg_data, data})

    # Extract keg ID from the data and register socket
    state = maybe_register_socket(data, socket, state)

    {:continue, state}
  end

  def handle_close(_socket, state) do
    if state.keg_id do
      Logger.info("Keg #{state.keg_id} disconnected")
      Registry.unregister(OpenPlaatoKeg.KegSocketRegistry, state.keg_id)
    end

    :ok
  end

  defp maybe_register_socket(data, socket, %{keg_id: nil} = state) do
    case extract_keg_id(data) do
      nil ->
        state

      keg_id ->
        Logger.info("Registering socket for keg #{keg_id}")
        Registry.register(OpenPlaatoKeg.KegSocketRegistry, keg_id, socket)

        %{state | keg_id: keg_id}
    end
  end

  defp maybe_register_socket(_data, _socket, state), do: state

  defp extract_keg_id(data) do
    decoded =
      data
      |> BlynkProtocol.decode()
      |> PlaatoProtocol.decode()
      |> PlaatoData.decode()

    case Keyword.get(decoded, :id) do
      nil -> nil
      id -> id
    end
  rescue
    _ -> nil
  end
end

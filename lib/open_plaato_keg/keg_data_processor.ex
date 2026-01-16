defmodule OpenPlaatoKeg.KegDataProcessor do
  use GenServer
  require Logger

  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.Models.KegData
  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  # IMPORTANT:
  # This GenServer must be per-connection, NOT globally named.
  # Otherwise the 2nd keg connection will fail with {:already_started, pid}.
  def start_link(init_arg \\ %{}) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:keg_data, data}, state) do
    data
    |> decode()
    |> process(state)
  end

  defp process([], state) do
    {:noreply, state}
  end

  # First payload may only include the id
  defp process([id: id] = data, _state) do
    OpenPlaatoKeg.Models.KegData.publish(id, data)
    {:noreply, data}
  end

  defp process(data, state) do
    Logger.debug("Decoded keg data", data: inspect(data, limit: :infinity))

    amount_left_changed? =
      Enum.any?(data, fn {key, _value} -> key == :amount_left end)

    publish(state[:id], data, [
      {&KegData.publish/2, fn -> true end},
      {&OpenPlaatoKeg.Metrics.publish/2, fn -> true end},
      {&OpenPlaatoKeg.WebSocketHandler.publish/2, fn -> true end},
      {&OpenPlaatoKeg.MqttHandler.publish/2, fn -> OpenPlaatoKeg.mqtt_config()[:enabled] end},
      {&OpenPlaatoKeg.BarHelper.publish/2,
       fn -> amount_left_changed? and OpenPlaatoKeg.barhelper_config()[:enabled] end}
    ])

    {:noreply, state}
  end

  defp decode(data) do
    data
    |> BlynkProtocol.decode()
    |> PlaatoProtocol.decode()
    |> PlaatoData.decode()
  end

  defp publish(nil = _id, data, _publishers) do
    Logger.warning("No id found for decoded data", data: inspect(data))
    :skip
  end

  defp publish(id, data, publishers) do
    Enum.each(publishers, fn {publish_func, condition} ->
      if condition.() do
        publish_func.(id, data)
      end
    end)
  end
end

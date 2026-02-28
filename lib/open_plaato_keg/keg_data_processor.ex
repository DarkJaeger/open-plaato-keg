defmodule OpenPlaatoKeg.KegDataProcessor do
  use GenServer
  require Logger

  alias OpenPlaatoKeg.Models.AirlockData
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

  defp process([], state), do: {:noreply, state}

  defp process(data, state) do
    # The login packet (get_shared_dash) may arrive in the same TCP frame as
    # other commands, so we always extract the id from any decoded list rather
    # than relying on a single-element [id: id] pattern.
    state =
      case Keyword.fetch(data, :id) do
        {:ok, id} -> Map.put(state, :id, id)
        :error -> state
      end

    # Detect device type from pin keys once and cache it in state.
    state =
      cond do
        state[:device_type] != nil -> state
        airlock_data?(data) -> Map.put(state, :device_type, :airlock)
        keg_data?(data) -> Map.put(state, :device_type, :keg)
        true -> state
      end

    # Strip the id before routing — it is already in state.
    payload = Keyword.delete(data, :id)

    cond do
      payload == [] ->
        {:noreply, state}

      state[:device_type] == :airlock ->
        Logger.debug("Decoded airlock data", data: inspect(payload, limit: :infinity))
        # Drop internal metadata — not stored for airlocks.
        process_airlock(Keyword.delete(payload, :internal), state)

      true ->
        Logger.debug("Decoded keg data", data: inspect(payload, limit: :infinity))
        process_keg(payload, state)
    end
  end

  # A packet contains airlock data if it has any of the three airlock pins.
  defp airlock_data?(data) do
    Keyword.has_key?(data, :airlock_bubble_count) or
      Keyword.has_key?(data, :airlock_temperature) or
      Keyword.has_key?(data, :airlock_error)
  end

  # A packet contains keg data if it has any well-known keg-only pins.
  defp keg_data?(data) do
    Keyword.has_key?(data, :amount_left) or
      Keyword.has_key?(data, :keg_temperature) or
      Keyword.has_key?(data, :percent_of_beer_left) or
      Keyword.has_key?(data, :is_pouring) or
      Keyword.has_key?(data, :firmware_version)
  end

  defp process_keg(data, state) do
    id = state[:id]

    # Only register the device in KegData (via the :id key) once we have
    # confirmed it is a keg, so airlock devices never appear in the keg list.
    data_with_id =
      if id && state[:device_type] == :keg,
        do: Keyword.put_new(data, :id, id),
        else: data

    amount_left_changed? =
      Enum.any?(data, fn {key, _value} -> key == :amount_left end)

    publish(id, data_with_id, [
      {&KegData.publish/2, fn -> true end},
      {&OpenPlaatoKeg.Metrics.publish/2, fn -> true end},
      {&OpenPlaatoKeg.WebSocketHandler.publish/2, fn -> true end},
      {&OpenPlaatoKeg.MqttHandler.publish/2, fn -> OpenPlaatoKeg.mqtt_config()[:enabled] end},
      {&OpenPlaatoKeg.BarHelper.publish/2,
       fn -> amount_left_changed? and OpenPlaatoKeg.barhelper_config()[:enabled] end}
    ])

    {:noreply, state}
  end

  defp process_airlock(data, state) do
    id = state[:id]

    # V100 sends cumulative count since power-on. BPM = delta / elapsed_minutes.
    {bpm, new_state} =
      maybe_compute_bpm(Keyword.get(data, :airlock_bubble_count), state)

    airlock_fields =
      []
      |> append_field(:temperature, Keyword.get(data, :airlock_temperature))
      |> append_field(:bubbles_per_min, bpm && to_string(bpm))
      |> append_field(:error, Keyword.get(data, :airlock_error))

    if id && airlock_fields != [] do
      AirlockData.publish(id, airlock_fields)
      OpenPlaatoKeg.WebSocketHandler.publish_airlock(id, airlock_fields)
    end

    {:noreply, new_state}
  end

  defp maybe_compute_bpm(nil, state), do: {nil, state}

  defp maybe_compute_bpm(count_str, state) do
    case Integer.parse(to_string(count_str)) do
      {new_count, _} ->
        now = System.system_time(:millisecond)
        prev_count = state[:airlock_last_count]
        prev_time = state[:airlock_last_count_time]

        bpm =
          if prev_count != nil and prev_time != nil and new_count >= prev_count do
            elapsed_min = (now - prev_time) / 60_000.0
            if elapsed_min > 0, do: Float.round((new_count - prev_count) / elapsed_min, 1)
          end

        new_state =
          state
          |> Map.put(:airlock_last_count, new_count)
          |> Map.put(:airlock_last_count_time, now)

        {bpm, new_state}

      :error ->
        {nil, state}
    end
  end

  defp append_field(list, _key, nil), do: list
  defp append_field(list, key, value), do: [{key, value} | list]

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

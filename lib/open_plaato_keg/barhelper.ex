defmodule OpenPlaatoKeg.BarHelper do
  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def publish(id, data) do
    GenServer.cast(__MODULE__, {:keg_data, id, data})
  end

  def handle_cast({:keg_data, id, data}, state) do
    keg_monitor_id = state.config[:configuration][id]
    raw_volume = data[:amount_left]

    if keg_monitor_id != nil && raw_volume do
      case parse_volume(raw_volume) do
        {:ok, volume} ->
          send_data_to_barhelper(volume, keg_monitor_id, state.config)

        :error ->
          Logger.warning(
            "Skipped sending data to BarHelper. Monitor: #{keg_monitor_id}. amount_left is not numeric: #{inspect(raw_volume)}"
          )
      end
    end

    {:noreply, state}
  end

  @doc false
  # Pin 51 (:amount_left) arrives off the wire as a binary and is stored as one.
  # BarHelper answers a stringified volume with a 500, so coerce to a float before
  # building the payload. Mirrors parse_float/2 in OpenPlaatoKeg.Brewfather.
  def parse_volume(nil), do: :error

  def parse_volume(value) when is_binary(value) do
    case Float.parse(value) do
      {volume, _rest} -> {:ok, volume}
      :error -> :error
    end
  end

  def parse_volume(value) when is_number(value), do: {:ok, value * 1.0}
  def parse_volume(_value), do: :error

  @doc false
  # Kept separate from logging so both can be tested without stubbing HTTP.
  # `body` is usually a binary, but Req decodes JSON responses into a map, so
  # never assume a binary here.
  def classify_response(status, body) do
    cond do
      auth_error?(body) -> :auth_error
      status == 429 -> :rate_limited
      status in 200..299 and success?(body) -> :success
      status in 200..299 -> :no_success_flag
      true -> :unexpected
    end
  end

  defp send_data_to_barhelper(volume, keg_monitor_id, config) do
    # https://docs.barhelper.app/english/settings/custom-keg-monitor

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "#{config[:api_key]}"}
    ]

    body = %{
      name: keg_monitor_id,
      volume: volume,
      type: config[:unit]
    }

    case Req.post(config[:host], json: body, headers: headers) do
      {:ok, %{status: status, body: response_body}} ->
        status
        |> classify_response(response_body)
        |> log_response(status, response_body, volume, keg_monitor_id)

      {:error, reason} ->
        Logger.error(
          "Failed to send data to BarHelper. Monitor: #{keg_monitor_id}. Reason: #{inspect(reason)}"
        )
    end
  end

  defp log_response(:success, status, response_body, volume, keg_monitor_id) do
    Logger.info(
      "Successfully sent data to BarHelper. Monitor: #{keg_monitor_id}. Sent #{describe_volume(volume)}. Status: #{status}. Response: #{inspect(response_body)}"
    )
  end

  defp log_response(:auth_error, status, response_body, _volume, keg_monitor_id) do
    Logger.error(
      "Error when sending data to BarHelper. Monitor: #{keg_monitor_id}. Status: #{status}. Response: #{inspect(response_body)}"
    )
  end

  defp log_response(:rate_limited, status, response_body, _volume, keg_monitor_id) do
    Logger.warning(
      "BarHelper rate limited this update, it was dropped. Monitor: #{keg_monitor_id}. Status: #{status}. Response: #{inspect(response_body)}"
    )
  end

  defp log_response(:no_success_flag, status, response_body, volume, keg_monitor_id) do
    Logger.warning(
      "BarHelper accepted the request but did not report success. Monitor: #{keg_monitor_id}. Sent #{describe_volume(volume)}. Status: #{status}. Response: #{inspect(response_body)}"
    )
  end

  defp log_response(:unexpected, status, response_body, volume, keg_monitor_id) do
    Logger.error(
      "Unexpected response from BarHelper. Monitor: #{keg_monitor_id}. Sent #{describe_volume(volume)}. Status: #{status}. Response: #{inspect(response_body)}"
    )
  end

  # The value and its type are logged on every failure path: sending the wrong
  # type is what silently broke this integration once already.
  defp describe_volume(volume), do: "volume=#{inspect(volume)} (#{type_of(volume)})"

  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(_value), do: "other"

  defp success?(body) when is_binary(body), do: Regex.match?(~r/"success"\s*:\s*true/, body)
  defp success?(body) when is_map(body), do: Map.get(body, "success") == true
  defp success?(_body), do: false

  defp auth_error?(body) when is_binary(body), do: String.starts_with?(body, "Wrong auth")
  defp auth_error?(_body), do: false
end

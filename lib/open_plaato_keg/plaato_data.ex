defmodule OpenPlaatoKeg.PlaatoData do
  require Logger

  # most of it taken from https://intercom.help/plaato/en/articles/5004722-pins-plaato-keg

  @plaato_data %{
    {:hardware, "vw", "47"} => :last_pour_string,
    {:hardware, "vw", "48"} => :percent_of_beer_left,
    {:hardware, "vw", "49"} => :is_pouring,
    {:hardware, "vw", "51"} => :amount_left,
    {:hardware, "vw", "52"} => :temperature_offset,
    {:hardware, "vw", "56"} => :keg_temperature,
    {:hardware, "vw", "59"} => :last_pour,
    {:hardware, "vw", "60"} => :tare,
    {:hardware, "vw", "61"} => :known_weight_calibrate,
    {:hardware, "vw", "62"} => :empty_keg_weight,
    {:hardware, "vw", "64"} => :beer_style,
    {:hardware, "vw", "65"} => :og,
    {:hardware, "vw", "66"} => :fg,
    {:hardware, "vw", "67"} => :date,
    {:hardware, "vw", "68"} => :calculated_abv,
    {:hardware, "vw", "69"} => :keg_temperature_string,
    {:hardware, "vw", "70"} => :calculated_alcohol_string,
    {:hardware, "vw", "71"} => :unit,
    {:hardware, "vw", "72"} => :calculate,
    {:hardware, "vw", "74"} => :beer_left_unit,
    {:hardware, "vw", "75"} => :measure_unit,
    {:hardware, "vw", "76"} => :max_keg_volume,
    {:hardware, "vw", "80"} => :temperature_unit,
    {:hardware, "vw", "81"} => :wifi_signal_strength,
    {:hardware, "vw", "82"} => :volume_unit,
    {:hardware, "vw", "83"} => :leak_detection,
    {:hardware, "vw", "86"} => :min_temperature,
    {:hardware, "vw", "87"} => :max_temperature,
    {:hardware, "vw", "88"} => :keg_mode_c02_beer,
    {:hardware, "vw", "89"} => :sensitivity,
    {:hardware, "vw", "92"} => :chip_temperature_string,
    {:hardware, "vw", "93"} => :firmware_version,
    {:property, "51", "max"} => :max_keg_volume,

    # Plaato Airlock pins
    {:hardware, "vw", "99"} => :airlock_error,
    {:hardware, "vw", "100"} => :airlock_bubble_count,
    {:hardware, "vw", "101"} => :airlock_temperature
  }

  def decode(commands) when is_list(commands) do
    commands
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  def decode({:get_shared_dash, _, _, dash}) do
    {:id, dash}
  end

  def decode({:internal, _, _, hardware_data}) do
    {:internal, hardware_data}
  end

  def decode({type, kind, id, data} = message) do
    case Map.get(@plaato_data, {type, kind, id}) do
      nil ->
        Logger.debug("Unknown data type", data: inspect(message))

        if Application.get_env(:open_plaato_keg, :include_unknown_data),
          do: {"_#{type}_#{kind}_#{id}", data},
          else: nil

      name ->
        {name, data}
    end
  end

  def decode(message) do
    Logger.debug("Unknown data kind", data: inspect(message))
    nil
  end
end

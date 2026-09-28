defmodule OpenPlaatoKeg.SettingsRestore do
  @moduledoc """
  Answers a keg's settings sync so its configuration survives a reconnect.

  When a Plaato Keg connects, its firmware asks the server for its settings pins with
  a Blynk hardware sync (`vr\\0<pin>\\0<pin>...`; seen from firmware 2.0.10a as
  `vr 88 65 66 68 71 72 75 76 84 85 86 87 89 95`) and applies whatever the server
  writes back. That is how the Plaato cloud kept a keg's settings. The keg does not
  keep its unit system or weight/volume mode itself, so while the request goes
  unanswered, a keg that reboots or rejoins Wi-Fi comes back metric and by weight
  (issue #14).

  This replies to that request with the settings the operator chose through the API
  or setup page, or with the `DEFAULT_UNIT`, `DEFAULT_MEASURE_UNIT` and
  `DEFAULT_KEG_MODE` defaults. It never echoes what the keg itself last reported,
  which after a reboot is the metric/weight default. Pins with no chosen value are
  left unanswered, as before.
  """
  require Logger

  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.Models.KegData

  # pin => {field, KegData key holding the operator's choice}
  @restorable %{
    "71" => {:unit, :desired_unit},
    "75" => {:measure_unit, :desired_measure_unit},
    "88" => {:keg_mode, :desired_keg_mode_c02_beer}
  }

  @fields %{
    unit: :desired_unit,
    measure_unit: :desired_measure_unit,
    keg_mode: :desired_keg_mode_c02_beer
  }

  @doc """
  The hardware writes answering any settings sync the keg sent in `data`.
  """
  def replies(nil, _data), do: []

  def replies(keg_id, data) do
    data
    |> requested_pins()
    |> Enum.flat_map(&reply(keg_id, &1))
  end

  @doc """
  The virtual pins a keg asked for in `data`, in order.
  """
  def requested_pins(data) do
    data
    |> BlynkProtocol.decode()
    |> Enum.flat_map(fn
      {:hardware_sync, _msg_id, _length, body} ->
        case String.split(body, "\0", trim: true) do
          ["vr" | pins] -> pins
          _ -> []
        end

      _ ->
        []
    end)
  rescue
    # A partial or unrecognised frame asks for nothing.
    _ -> []
  end

  @doc """
  Remember the operator's choice for `field` (`:unit`, `:measure_unit` or
  `:keg_mode`), so the next reconnect restores it.
  """
  def remember(keg_id, field, value) when is_map_key(@fields, field) do
    KegData.publish(keg_id, [{Map.fetch!(@fields, field), to_string(value)}])
  end

  @doc """
  The value that will be restored for `field`, or nil.
  """
  def desired(keg_id, field) when is_map_key(@fields, field) do
    case KegData.get(keg_id)[Map.fetch!(@fields, field)] do
      value when value in [nil, ""] -> default(field)
      value -> to_string(value)
    end
  end

  defp reply(keg_id, pin) do
    with {field, _key} <- Map.get(@restorable, pin),
         value when value not in [nil, ""] <- desired(keg_id, field) do
      Logger.info("Restoring V#{pin}=#{value} for keg #{keg_id} on its settings sync")
      [BlynkProtocol.encode_command(:hardware, :rand.uniform(65_535), "vw\0#{pin}\0#{value}")]
    else
      _ -> []
    end
  end

  defp default(field) do
    :open_plaato_keg
    |> Application.get_env(:settings_defaults, [])
    |> Keyword.get(field)
    |> case do
      value when value in [nil, ""] -> nil
      value -> to_string(value)
    end
  end
end

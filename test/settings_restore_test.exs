defmodule OpenPlaatoKeg.SettingsRestoreTest do
  # Not async: it replaces the shared :keg_data table and application config.
  use ExUnit.Case

  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.Models.KegData
  alias OpenPlaatoKeg.SettingsRestore

  # The settings sync a Plaato Keg (firmware 2.0.10a) sends when it connects.
  @sync_pins ~w(88 65 66 68 71 72 75 76 84 85 86 87 89 95)
  @sync BlynkProtocol.encode_command(:hardware_sync, 7, Enum.join(["vr" | @sync_pins], "\0"))

  setup do
    :dets.close(:keg_data)
    :dets.close(:airlock_data)
    dir = Path.join(System.tmp_dir!(), "settings_restore_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {:ok, _} = :dets.open_file(:keg_data, file: String.to_charlist(Path.join(dir, "kegs.dets")))

    {:ok, _} =
      :dets.open_file(:airlock_data, file: String.to_charlist(Path.join(dir, "airlocks.dets")))

    previous = Application.get_env(:open_plaato_keg, :settings_defaults)
    Application.put_env(:open_plaato_keg, :settings_defaults, [])

    on_exit(fn ->
      :dets.close(:keg_data)
      :dets.close(:airlock_data)
      File.rm_rf(dir)
      Application.put_env(:open_plaato_keg, :settings_defaults, previous || [])
    end)

    :ok
  end

  defp writes(frames) do
    frames
    |> Enum.flat_map(&BlynkProtocol.decode/1)
    |> Enum.map(fn {:hardware, _msg_id, _length, body} -> String.split(body, "\0") end)
  end

  test "reads the pins a keg asks for" do
    assert SettingsRestore.requested_pins(@sync) == @sync_pins
    # Other traffic, a partial frame or garbage asks for nothing.
    assert SettingsRestore.requested_pins(
             BlynkProtocol.encode_command(:hardware, 1, "vw\0" <> "51\0" <> "5.1")
           ) == []

    assert SettingsRestore.requested_pins(<<16, 0, 7, 0, 90, "vr">>) == []
    assert SettingsRestore.requested_pins("nonsense") == []
  end

  test "answers with the operator's chosen unit, mode and keg mode" do
    SettingsRestore.remember("keg-1", :unit, "2")
    SettingsRestore.remember("keg-1", :measure_unit, "2")
    SettingsRestore.remember("keg-1", :keg_mode, "1")
    # What the keg itself reported after a reboot must never be echoed back.
    KegData.publish("keg-1", unit: "1", measure_unit: "1")

    assert writes(SettingsRestore.replies("keg-1", @sync)) == [
             ["vw", "88", "1"],
             ["vw", "71", "2"],
             ["vw", "75", "2"]
           ]
  end

  test "falls back to the configured defaults, and answers nothing without either" do
    assert SettingsRestore.replies("keg-2", @sync) == []

    Application.put_env(:open_plaato_keg, :settings_defaults, unit: "2", measure_unit: "2")

    assert writes(SettingsRestore.replies("keg-2", @sync)) == [
             ["vw", "71", "2"],
             ["vw", "75", "2"]
           ]

    SettingsRestore.remember("keg-2", :unit, "1")

    assert writes(SettingsRestore.replies("keg-2", @sync)) == [
             ["vw", "71", "1"],
             ["vw", "75", "2"]
           ]
  end

  test "an unregistered connection answers nothing" do
    SettingsRestore.remember("keg-3", :unit, "2")
    assert SettingsRestore.replies(nil, @sync) == []
  end
end

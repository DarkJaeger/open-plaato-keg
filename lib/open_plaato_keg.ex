defmodule OpenPlaatoKeg do
  use Application

  def start(_type, _args) do
    OpenPlaatoKeg.Metrics.init()
    bootstrap()
    OpenPlaatoKeg.Supervisor.start_link()
  end

  def bootstrap do
    db_file_path =
      Application.get_env(:open_plaato_keg, :db)[:file_path]

    # create folder if doesn't exist
    db_folder = Path.dirname(db_file_path)
    File.mkdir_p!(db_folder)

    {:ok, _keg_table} =
      :dets.open_file(:keg_data, [
        {:file, String.to_charlist(db_file_path)}
      ])

    # Airlocks are separate from kegs; own DETS file
    airlock_path = Path.join(db_folder, "airlock_data.bin")
    {:ok, _airlock_table} =
      :dets.open_file(:airlock_data, [
        {:file, String.to_charlist(airlock_path)}
      ])
  end

  def tcp_listener_config do
    Application.get_env(:open_plaato_keg, :tcp_listener)
  end

  def http_listener_config do
    Application.get_env(:open_plaato_keg, :http_listener)
  end

  def mqtt_config do
    Application.get_env(:open_plaato_keg, :mqtt)
  end

  def barhelper_config do
    Application.get_env(:open_plaato_keg, :barhelper)
  end
end

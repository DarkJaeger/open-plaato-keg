defmodule OpenPlaatoKeg.Models.KegData do
  require Logger

  def all do
    Enum.map(devices(), &get/1)
  end

  def get(id) do
    query = {{id, :"$1"}, :"$2"}

    data =
      :keg_data
      |> :dets.match(query)
      |> Enum.map(fn [key, value] -> {key, value} end)
      |> Enum.reject(fn {key, _value} -> key == :calibration end)
      |> Map.new()
      |> Map.put(:id, id)

    # Always derive beer_left_unit from unit + measure_unit whenever unit is known.
    # This ensures the displayed unit label is always consistent with the configured
    # mode, regardless of what the hardware sends on V74.
    unit = to_string(data[:unit] || "")

    if unit in ["1", "2"] do
      measure = to_string(data[:measure_unit] || "")
      Map.put(data, :beer_left_unit, derive_beer_left_unit(unit, measure))
    else
      data
    end
  end

  def devices do
    query = {{:_, :id}, :"$1"}

    :keg_data
    |> :dets.match(query)
    |> List.flatten()
  end

  def publish(id, data) do
    Enum.each(data, fn {key, value} ->
      :dets.insert(:keg_data, {{id, key}, value})
    end)
  end

  def delete(id) do
    # Find all keys stored for this id, then delete each record individually.
    :keg_data
    |> :dets.match({{id, :"$1"}, :_})
    |> List.flatten()
    |> Enum.each(fn key -> :dets.delete(:keg_data, {id, key}) end)
  end

  # unit "1" = metric, "2" = US; measure_unit "1" = weight, "2" = volume
  defp derive_beer_left_unit("1", "1"), do: "kg"
  defp derive_beer_left_unit("1", _),   do: "litre"
  defp derive_beer_left_unit("2", "1"), do: "lbs"
  defp derive_beer_left_unit("2", _),   do: "gal"
  defp derive_beer_left_unit(_, _),     do: "litre"
end

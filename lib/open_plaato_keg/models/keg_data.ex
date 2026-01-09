defmodule OpenPlaatoKeg.Models.KegData do
  require Logger

  def all do
    Enum.map(devices(), &get/1)
  end

  def get(id) do
    query = {{id, :"$1"}, :"$2"}

    :keg_data
    |> :dets.match(query)
    |> Enum.map(fn [key, value] -> {key, value} end)
    |> Enum.reject(fn {key, _value} -> key == :calibration end)
    |> Map.new()
    |> Map.put(:id, id)
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
end

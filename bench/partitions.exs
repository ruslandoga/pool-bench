schedulers = :erlang.system_info(:schedulers)
parallel = IO.gets("How parallel: ") |> String.trim() |> String.to_integer()

:ets.new(:default, [:public, :named_table])
:ets.new(:read_concurrency, [:public, :named_table, read_concurrency: true])

Enum.each(0..schedulers, fn n ->
  :ets.new(:"partitioned#{n}", [:public, :named_table])
end)

keys = Enum.to_list(1..100)
Enum.each(keys, fn key -> :ets.insert(:default, {key, key}) end)
Enum.each(keys, fn key -> :ets.insert(:read_concurrency, {key, key}) end)

Enum.each(keys, fn key ->
  partition = :erlang.phash2(key, schedulers)
  :ets.insert(:"partitioned#{partition}", {key, key})
end)

defmodule Partitions do
  def default_lookup(key), do: :ets.lookup(:default, key)
  def read_concurrency_lookup(key), do: :ets.lookup(:read_concurrency, key)

  def partitioned_lookup(key) do
    partition = :erlang.phash2(key, unquote(schedulers))

    tab =
      case partition do
        0 -> :partitioned0
        1 -> :partitioned1
        2 -> :partitioned2
        3 -> :partitioned3
        4 -> :partitioned4
        5 -> :partitioned5
        6 -> :partitioned6
        7 -> :partitioned7
        8 -> :partitioned8
        n -> :"partitioned#{n}"
      end

    :ets.lookup(tab, key)
  end
end

Benchee.run(
  %{
    "default" => fn keys ->
      Enum.each(keys, &Partitions.default_lookup/1)
    end,
    "read_concurrency" => fn keys ->
      Enum.each(keys, &Partitions.read_concurrency_lookup/1)
    end,
    "partitioned" => fn keys ->
      Enum.each(keys, &Partitions.partitioned_lookup/1)
    end
  },
  inputs: %{"#{length(keys)} keys" => keys},
  parallel: parallel,
  time: 2
)

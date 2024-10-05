schedulers = IO.inspect(:erlang.system_info(:schedulers), label: "Schedulers")

{:ok, naive} =
  GenServer.start_link(
    Naive,
    Enum.map(1..schedulers, fn _ ->
      XQLite.open(":memory:", [:readonly, :nomutex])
    end),
    name: Naive
  )

:eprof.start_profiling([naive])

sql = """
with recursive cte(i) as (
  values(0)
  union all
  select i + 1 from cte where i < ?
)
select i, 'hello' || i, null from cte
"""

Benchee.run(
  %{
    "Naive.query/3" => fn rows -> Naive.query(Naive, sql, [rows]) end
  },
  inputs: %{
    "100 rows" => 100
  },
  time: 2,
  parallel: 100
)

:eprof.stop_profiling()
:eprof.analyze()

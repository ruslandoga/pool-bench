dirty_io_schedulers =
  IO.inspect(:erlang.system_info(:dirty_io_schedulers), label: "Dirty IO Schedulers")

{:ok, _naive} =
  GenServer.start_link(
    Naive,
    Enum.map(1..dirty_io_schedulers, fn _ ->
      XQLite.open(":memory:", [:readonly, :nomutex])
    end),
    name: Naive
  )

# :eprof.start_profiling([naive])

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
    "Naive.query/3" => fn rows -> Naive.query(Naive, sql, [rows]) end,
    "db per benchee runner" =>
      {fn %{db: db, stmt: stmt, rows: rows} ->
         # XQLite.bind_integer(db, stmt, 1, rows)
         # XQLite.fetch_all(db, stmt)
         XQLite.unsafe_step(db, stmt, rows + 1)
       end,
       before_scenario: fn rows ->
         db = XQLite.open(":memory:", [:readonly, :nomutex])
         stmt = XQLite.prepare(db, sql, [:persistent])
         XQLite.bind_integer(db, stmt, 1, rows)
         %{db: db, stmt: stmt, rows: rows}
       end,
       after_scenario: fn %{db: db, stmt: stmt} ->
         XQLite.finalize(stmt)
         XQLite.close(db)
       end}
  },
  inputs: %{
    "10 rows" => 10
    # "100 rows" => 100,
    # "1000 rows" => 1000
  },
  time: 5,
  parallel: 10
  # profile_after: true
)

# :eprof.stop_profiling()
# :eprof.analyze()

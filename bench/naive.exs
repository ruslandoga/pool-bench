dirty_io_schedulers =
  IO.inspect(:erlang.system_info(:dirty_io_schedulers), label: "Dirty IO Schedulers")

{:ok, naive} =
  GenServer.start_link(
    Naive,
    Enum.map(1..dirty_io_schedulers, fn _ ->
      XQLite.open("w2.db", [:readonly, :nomutex])
    end),
    name: Naive
  )

Naive.query(naive, "select count(*) from heartbeats", []) |> IO.inspect(label: "Count")

# :eprof.start_profiling([naive])

sql = "select * from heartbeats where time < ? limit ?"

Benchee.run(
  %{
    "Naive.query/3" => fn rows ->
      before_time = Enum.random(1_653_738_977..1_727_597_475)
      Naive.query(Naive, sql, [before_time, rows])
    end,
    "db per benchee runner" =>
      {fn %{db: db, stmt: stmt, rows: rows} ->
         before_time = Enum.random(1_653_738_977..1_727_597_475)
         XQLite.bind_integer(db, stmt, 1, before_time)
         XQLite.bind_integer(db, stmt, 2, rows)
         XQLite.fetch_all(db, stmt)
       end,
       before_scenario: fn rows ->
         db = XQLite.open("w2.db", [:readonly, :nomutex])
         stmt = XQLite.prepare(db, sql, [:persistent])
         %{db: db, stmt: stmt, rows: rows}
       end,
       after_scenario: fn %{db: db, stmt: stmt} ->
         XQLite.finalize(stmt)
         XQLite.close(db)
       end}
  },
  inputs: %{
    # "10 rows" => 10
    "100 rows" => 100
    # "1000 rows" => 1000
  },
  time: 5,
  parallel: 4
)

# :eprof.stop_profiling()
# :eprof.analyze()

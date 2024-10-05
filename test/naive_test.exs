defmodule NaiveTest do
  use ExUnit.Case, async: true

  @cte """
  with recursive cte(i) as (
    values(0)
    union all
    select i + 1 from cte where i < ?
  )
  select i, 'hello' || i, null from cte
  """

  describe "naive" do
    test "it works" do
      dbs =
        Enum.map(1..3, fn _ ->
          XQLite.open(":memory:", [:readonly, :nomutex, :exrescode])
        end)

      {:ok, naive} = GenServer.start_link(Naive, dbs)
      assert %{monitors: %{}, queue: {[], []}, resources: [_, _, _]} = :sys.get_state(naive)

      task = Task.async(fn -> Naive.query(naive, @cte, [10000]) end)

      # assert %{monitors: monitors, queue: {[], []}, resources: [_, _]} = :sys.get_state(naive)
      # assert map_size(monitors) == 1

      assert length(Task.await(task)) == 10001

      # assert :sys.get_state(naive) == %{monitors: %{}, queue: {[], []}, resources: [1, 2, 3]}

      # spawn(fn -> Naive.checkout(naive, _ms = 50) end)
      # spawn(fn -> Naive.checkout(naive, _ms = 50) end)
      # spawn(fn -> Naive.checkout(naive, _ms = 50) end)

      # :timer.sleep(5)

      # spawn(fn ->
      #   Naive.checkout(naive, _ms = 50)
      #   send(test, :done)
      # end)

      # :timer.sleep(5)

      # assert %{monitors: monitors, queue: queue, resources: []} = :sys.get_state(naive)

      # assert [1, 2, 3, queued] = Map.values(monitors)
      # assert [{^queued, _monitor}] = :queue.to_list(queue)

      # assert_receive :done, 1000

      # assert %{monitors: monitors, queue: {[], []}, resources: resources} = :sys.get_state(naive)
      # assert monitors == %{}
      # assert Enum.sort(resources) == [1, 2, 3]
    end
  end
end

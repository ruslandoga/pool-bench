defmodule Naive do
  use GenServer

  @spec query(GenServer.name(), String.t(), [XQLite.value()], timeout) :: [XQLite.row()]
  def query(pool, sql, params, timeout \\ :timer.seconds(15)) do
    {{db, stmts}, monitor} = GenServer.call(pool, :out, timeout)

    try do
      stmt =
        case :ets.lookup(stmts, sql) do
          [{^sql, stmt}] ->
            stmt

          [] ->
            stmt = XQLite.prepare(db, sql, [:persistent])
            :ets.insert(stmts, {sql, stmt})
            stmt
        end

      # TODO reset after error?
      bind_all(params, 1, db, stmt)

      # TODO interrupt after timeout?
      XQLite.fetch_all(db, stmt)
    after
      GenServer.cast(pool, {:in, monitor})
    end
  end

  defp bind_all([param | params], idx, db, stmt) do
    case param do
      i when is_integer(i) -> XQLite.bind_integer(db, stmt, idx, i)
      f when is_float(f) -> XQLite.bind_float(db, stmt, idx, f)
      t when is_binary(t) -> XQLite.bind_text(db, stmt, idx, t)
      nil -> XQLite.bind_null(db, stmt, idx)
    end

    bind_all(params, idx + 1, db, stmt)
  end

  defp bind_all([], _idx, _db, _stmt), do: :ok

  @impl true
  def init(dbs) when is_list(dbs) do
    resources = Enum.map(dbs, fn db -> {db, :ets.new(:stmts, [:public])} end)
    {:ok, %{queue: :queue.new(), monitors: %{}, resources: resources}}
  end

  @impl true
  def handle_call(:out, {caller, _tag} = from, state) do
    %{queue: queue, monitors: monitors, resources: resources} = state

    monitor = Process.monitor(caller)

    case resources do
      [resource | resources] ->
        monitors = Map.put(monitors, monitor, resource)
        {:reply, {resource, monitor}, %{state | monitors: monitors, resources: resources}}

      [] ->
        # TODO drop from queue if gets big?
        queue = :queue.in({from, monitor}, queue)
        monitors = Map.put(monitors, monitor, from)
        {:noreply, %{state | queue: queue, monitors: monitors}}
    end
  end

  @impl true
  def handle_cast({:in, monitor}, state) do
    %{queue: queue, monitors: monitors, resources: resources} = state
    {resource, monitors} = Map.pop!(monitors, monitor)
    Process.demonitor(monitor, [:flush])

    case :queue.out(queue) do
      {{:value, {from, monitor}}, queue} ->
        GenServer.reply(from, {resource, monitor})
        monitors = Map.replace!(monitors, monitor, resource)
        {:noreply, %{state | queue: queue, monitors: monitors}}

      {:empty, _queue} ->
        {:noreply, %{state | monitors: monitors, resources: [resource | resources]}}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, pid, _reason}, state) do
    %{queue: queue, monitors: monitors, resources: resources} = state
    {monitored, monitors} = Map.pop!(monitors, monitor)
    Process.demonitor(monitor, [:flush])

    state =
      case monitored do
        {^pid, _tag} = from ->
          queue = :queue.delete({from, monitor}, queue)
          %{state | queue: queue, monitors: monitors}

        resource ->
          case :queue.out(queue) do
            {{:value, {from, monitor}}, queue} ->
              GenServer.reply(from, {resource, monitor})
              monitors = Map.replace!(monitors, monitor, resource)
              %{state | queue: queue, monitors: monitors}

            {:empty, _queue} ->
              %{state | monitors: monitors, resources: [resource | resources]}
          end
      end

    {:noreply, state}
  end
end

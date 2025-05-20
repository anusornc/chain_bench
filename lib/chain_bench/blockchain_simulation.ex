defmodule ChainBench.BlockchainSimulations do
  @moduledoc """
  Contains the core simulation logic for different blockchain consensus mechanisms.
  These functions are designed to be benchmarked by Benchee and are part of the ChainBench application.
  """
  require Logger

  # --- Simulated Consensus Implementations ---
  # Each function takes tx_count, node_count, and the PID of a Task.Supervisor

  def simulate_poa(tx_count, node_count, task_supervisor_pid) do
    # Ensure nodes are started for this specific simulation run
    nodes =
      Enum.map(1..node_count, fn i ->
        # Ensure the generic_node function is called with its full module path
        # if it were in a different module. Here, it's in the same module.
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoA_Node_#{i}") end)

        pid
      end)

    # Perform the simulation
    if node_count > 0 do
      validator_node = hd(nodes) # Simplified: first node is the validator
      Enum.each(1..tx_count, fn tx_num ->
        send(validator_node, {:validate, tx_num})
        # The Process.sleep here simulates work/network latency.
        # For more realistic benchmarks, replace sleeps with actual computational work
        # or more complex interaction patterns.
        Process.sleep(1) # Simulate block creation time
      end)
    end

    # Ensure nodes are stopped after this specific simulation run
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  def simulate_pbft(tx_count, node_count, task_supervisor_pid) do
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PBFT_Node_#{i}") end)

        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        # Simulate broadcasting to all nodes and waiting for consensus
        Enum.each(nodes, &send(&1, {:vote, tx_num}))
        # Simplified sleep to model PBFT's multi-round communication overhead
        Process.sleep(1 + div(node_count, 5)) # Scaled delay; adjust as needed
      end)
    end

    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  def simulate_pow(tx_count, node_count, task_supervisor_pid) do
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoW_Node_#{i}") end)

        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        miner = Enum.random(nodes) # Randomly select a miner
        send(miner, {:mine, tx_num})
        # Simulate PoW mining time; this should ideally be a computational task
        Process.sleep(5 + Enum.random(1..5)) # Variable delay for mining
      end)
    end

    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  def simulate_pos(tx_count, node_count, task_supervisor_pid) do
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoS_Node_#{i}") end)

        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        validator = Enum.random(nodes) # Randomly select a validator based on stake (simplified)
        send(validator, {:validate, tx_num})
        # Simulate PoS validation time
        Process.sleep(2 + Enum.random(0..2)) # Variable delay for validation
      end)
    end
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  def simulate_dpos(tx_count, node_count, task_supervisor_pid) do
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("DPoS_Node_#{i}") end)

        pid
      end)

    if node_count > 0 do
      # Using the application name from the project for config
      delegate_count = min(node_count, Application.get_env(:chain_bench, :dpos_delegates, 5))
      delegates = Enum.take_random(nodes, delegate_count)

      if Enum.empty?(delegates) do
        Logger.warning("DPoS simulation: No delegates available for node_count: #{node_count}")
      else
        Enum.each(1..tx_count, fn tx_idx ->
          delegate_index = rem(tx_idx - 1, length(delegates))
          delegate = Enum.at(delegates, delegate_index)
          send(delegate, {:validate, tx_idx})
          Process.sleep(Application.get_env(:chain_bench, :dpos_block_time_ms, 3))
        end)
      end
    end
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  def simulate_hybrid_poa(tx_count, node_count, task_supervisor_pid) do
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn ->
            generic_node("HybridPoA_Node_#{i}")
          end)

        pid
      end)

    if node_count > 0 do
      initial_block_counts = Enum.into(nodes, %{}, fn pid -> {pid, 0} end)

      Enum.reduce(1..tx_count, {initial_block_counts, -1}, fn tx_num,
                                                               {current_block_counts,
                                                                current_rr_idx} ->
        new_rr_idx = rem(current_rr_idx + 1, node_count)
        candidate_validator_pid = Enum.at(nodes, new_rr_idx)

        min_blocks_validated =
          if Map.values(current_block_counts) |> Enum.empty?(),
            do: 0,
            else: Enum.min(Map.values(current_block_counts))

        final_validator_pid =
          if current_block_counts[candidate_validator_pid] > min_blocks_validated + 1 do
            Enum.min_by(current_block_counts, fn {_pid, count} -> count end, fn ->
              {candidate_validator_pid, 0}
            end)
            |> elem(0)
          else
            candidate_validator_pid
          end

        send(final_validator_pid, {:validate, tx_num})
        Process.sleep(1 + Enum.random(0..1))

        updated_block_counts = Map.update!(current_block_counts, final_validator_pid, &(&1 + 1))
        {updated_block_counts, new_rr_idx}
      end)
    end

    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  # --- Generic Simulated Node ---
  def generic_node(node_name) do
    receive do
      {:validate, _tx_num} ->
        :crypto.hash(:sha256, :rand.bytes(32))
        generic_node(node_name)

      {:vote, _tx_num} ->
        :crypto.hash(:sha256, :rand.bytes(16))
        generic_node(node_name)

      {:mine, _tx_num} ->
        :crypto.hash(:sha256, :rand.bytes(64))
        generic_node(node_name)

      unexpected_msg ->
        Logger.warning("[#{node_name}] received unexpected message: #{inspect(unexpected_msg)}")
        generic_node(node_name)
    after
      # Using the application name from the project for config
      Application.get_env(:chain_bench, :node_receive_timeout, 30_000) ->
        :ok
    end
  end
end

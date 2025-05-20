defmodule ChainBench.BenchmarkRunner do
  @moduledoc """
  Orchestrates blockchain consensus benchmarks using the Benchee library,
  as part of the ChainBench application.
  """
  require Logger

  @doc """
  Runs the Benchee benchmark suite with options provided in a map.

  Args:
    - `opts`: A map containing benchmark options:
      - `transactions`: Number of transactions (integer).
      - `nodes`: A list of node counts (e.g., `[1, 5, 10]`).
      - `consensus`: A list of consensus algorithm atoms (e.g., `[:poa, :pbft]`).
      - `warmup`: Warmup time in seconds for Benchee.
      - `time`: Measurement time in seconds for Benchee.
      - `output_path`: Path to store benchmark reports.
  """
  def run_suite(opts) do
    # Ensure `opts` is a map, which it should be from the Mix task.
    tx_count = Map.fetch!(opts, :transactions)
    node_counts_list = Map.fetch!(opts, :nodes) # Expects a list
    consensus_types_list = Map.fetch!(opts, :consensus)

    # Use Map.get/3 for maps, providing default values.
    # The third argument to Map.get is the default value.
    # For warmup and time, we check opts, then app config, then a hardcoded default.
    warmup_time =
      Map.get(opts, :warmup, Application.get_env(:chain_bench, :benchee_warmup, 2))

    measure_time =
      Map.get(opts, :time, Application.get_env(:chain_bench, :benchee_time, 5))

    output_path =
      Map.get(opts, :output_path, "benchmark_results") # Default to "benchmark_results" if not in opts

    # Ensure the output directory exists
    File.mkdir_p(output_path)

    # Start a single Task.Supervisor for all benchmark jobs in this suite.
    supervisor_name = :"node_supervisor_#{System.unique_integer([:positive])}"

    case Task.Supervisor.start_link(name: supervisor_name) do
      {:ok, supervisor_pid} ->
        Logger.info("Task.Supervisor for nodes started: #{inspect(supervisor_pid)}")

        benchmark_jobs =
          for consensus_type <- consensus_types_list,
              node_count <- node_counts_list,
              into: %{} do
            job_name =
              "#{to_string(consensus_type) |> String.upcase()} / #{node_count} nodes / #{tx_count} tx"

            simulation_fn_wrapper = fn ->
              # Calls the appropriate simulation function from ChainBench.BlockchainSimulations.
              get_simulation_function(consensus_type).(tx_count, node_count, supervisor_pid)
            end

            {job_name, simulation_fn_wrapper}
          end

        if Enum.empty?(benchmark_jobs) do
          Logger.warning("No benchmark jobs generated. Check input parameters.")
          stop_supervisor(supervisor_pid)
          %{suite: %{jobs: %{}, configuration: %{}}} # Return an empty-like Benchee result
        else
          Logger.info(
            "Configuring Benchee suite with #{Enum.count(benchmark_jobs)} jobs. " <>
              "Warmup: #{warmup_time}s, Time: #{measure_time}s."
          )

          benchee_config = [
            warmup: warmup_time,
            time: measure_time,
            formatters: [
              Benchee.Formatters.Console,
              {Benchee.Formatters.HTML, file: Path.join(output_path, generate_filename_part(opts) <> ".html")},
              {Benchee.Formatters.JSON, file: Path.join(output_path, generate_filename_part(opts) <> ".json"), extended_json: true}
            ]
          ]

          suite_results = Benchee.run(benchmark_jobs, benchee_config)
          stop_supervisor(supervisor_pid)
          Logger.info("Benchmark suite finished. Reports saved to #{output_path}")
          suite_results
        end

      {:error, reason} ->
        Logger.error("Failed to start Task.Supervisor for nodes: #{inspect(reason)}")
        {:error, {:supervisor_start_failed, reason}}
    end
  end

  defp stop_supervisor(pid) do
    if Process.alive?(pid) do
      Logger.info("Attempting to stop Task.Supervisor: #{inspect(pid)}")
      Process.exit(pid, :shutdown)
      Process.sleep(100) # Give it a moment

      unless Process.alive?(pid) do
        Logger.info("Task.Supervisor for nodes stopped: #{inspect(pid)}")
      else
        Logger.warning("Task.Supervisor #{inspect(pid)} might still be alive after :shutdown. Forcing exit with :kill.")
        Process.exit(pid, :kill)
      end
    else
      Logger.warning("Task.Supervisor #{inspect(pid)} was not alive when attempting to stop.")
    end
  end

  defp get_simulation_function(consensus_type) do
    case consensus_type do
      :poa -> &ChainBench.BlockchainSimulations.simulate_poa/3
      :pbft -> &ChainBench.BlockchainSimulations.simulate_pbft/3
      :pow -> &ChainBench.BlockchainSimulations.simulate_pow/3
      :pos -> &ChainBench.BlockchainSimulations.simulate_pos/3
      :dpos -> &ChainBench.BlockchainSimulations.simulate_dpos/3
      :hybrid_poa -> &ChainBench.BlockchainSimulations.simulate_hybrid_poa/3
      _ ->
        Logger.error("Unknown consensus type: #{consensus_type}")
        fn _tx_count, _node_count, _supervisor_pid ->
          Logger.error("Attempted to run benchmark for unknown consensus type: #{consensus_type}")
          :error_unknown_consensus_type_in_benchmark_job
        end
    end
  end

  defp generate_filename_part(opts) do
    datetime_str =
      DateTime.utc_now()
      |> DateTime.to_string()
      |> String.replace(~r/[:\.]/, "-")
      |> String.replace("T", "_")
      |> String.replace("Z", "")

    # opts is a map here
    tx_str = "tx_#{Map.get(opts, :transactions)}" # Use Map.get for safety, though fetch! was used above
    nodes_val = Map.get(opts, :nodes, []) # Default to empty list if not found
    nodes_str = "nodes_#{Enum.join(nodes_val, "-")}"
    consensus_val = Map.get(opts, :consensus, []) # Default to empty list
    consensus_str = "consensus_#{consensus_val |> Enum.map(&to_string/1) |> Enum.join("-")}"

    "report_#{tx_str}_#{nodes_str}_#{consensus_str}_#{datetime_str}"
  end
end

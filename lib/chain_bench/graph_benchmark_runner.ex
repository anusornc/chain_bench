defmodule ChainBench.GraphBenchmarkRunner do
  @moduledoc """
  Orchestrates graph creation and benchmarking of query operations using Benchee.
  Implements targeted queries and optional deterministic graph generation.
  """
  require Logger

  alias ChainBench.GraphOperations # Alias for convenience

  @doc """
  Runs the full graph benchmark suite with enhanced query targeting.

  `opts` is a map containing:
    - `:sizes`: List of total transactions for graphs.
    - `:dag_avg_parents`: Integer for DAG graph.
    - `:blockdag_params`: Map with `:tx_per_block`, `:k_internal`, `:k_external`.
    - `:benchee_warmup`, `:benchee_time`, `:benchee_memory_time`: Benchee settings.
    - `:output_dir`, `:output_basename`: For report filenames.
    - `:random_seed_graph`: Optional integer seed for graph generation.
    - `:random_seed_query`: Optional integer seed for selecting random query targets.
  """
  def run_suite(opts) do
    # Extract options
    sizes = Map.fetch!(opts, :sizes)
    dag_avg_parents = Map.fetch!(opts, :dag_avg_parents)
    blockdag_params = Map.fetch!(opts, :blockdag_params)
    benchee_warmup = Map.fetch!(opts, :benchee_warmup)
    benchee_time = Map.fetch!(opts, :benchee_time)
    benchee_memory_time = Map.fetch!(opts, :benchee_memory_time)
    output_dir = Map.fetch!(opts, :output_dir)
    output_basename_opt = Map.get(opts, :output_basename) # Optional
    random_seed_graph = Map.get(opts, :random_seed_graph) # Optional seed for graph generation
    random_seed_query = Map.get(opts, :random_seed_query) # Optional seed for query target selection

    # --- Filename and Directory Setup ---
    base_filename_path =
      Path.join(
        output_dir,
        if is_nil(output_basename_opt) or String.trim(output_basename_opt) == "" do
          timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
          seed_suffix = if random_seed_graph, do: "_seed#{random_seed_graph}", else: ""
          "graph_bench_results_#{timestamp}#{seed_suffix}"
        else
          output_basename_opt
        end
      )
    File.mkdir_p(output_dir)
    benchee_html_output_file = base_filename_path <> "_benchee.html"
    vega_spec_with_data_file = base_filename_path <> "_vega_spec.json"

    Logger.info("Setting up graphs for benchmarking...")
    if random_seed_graph, do: Logger.info("Using random seed for graph generation: #{random_seed_graph}")
    setup_start_time = System.monotonic_time(:millisecond)

    # --- Graph Setup ---
    graph_creation_opts = %{random_seed: random_seed_graph}

    graphs_with_targets_by_size =
      Enum.map(sizes, fn size ->
        Logger.info("Creating graphs of size #{size} transactions...")
        num_blocks = ceil(size / blockdag_params.tx_per_block) |> trunc

        graph_map_for_size = %{
          :blockchain => GraphOperations.create_blockchain_graph(size, graph_creation_opts),
          :dag => GraphOperations.create_dag_graph(size, dag_avg_parents, graph_creation_opts),
          :blockdag =>
            GraphOperations.create_blockdag_internal_tx_dag(
              num_blocks,
              blockdag_params.tx_per_block,
              blockdag_params.k_internal,
              blockdag_params.k_external,
              graph_creation_opts
            )
        }
        query_target_opts = %{random_seed_for_query: random_seed_query}
        targets = %{
          latest: GraphOperations.get_latest_tx_vertex(size),
          middle: GraphOperations.get_middle_tx_vertex(size),
          near_genesis: GraphOperations.get_near_genesis_tx_vertex(size),
          random: GraphOperations.get_random_tx_vertex(size, query_target_opts)
        }
        {size, graph_map_for_size, targets}
      end)
      |> Map.new(fn {s, gm, t} -> {s, {gm, t}} end)


    setup_duration_ms = System.monotonic_time(:millisecond) - setup_start_time
    Logger.info("Graph setup finished in #{setup_duration_ms / 1000} seconds.")

    # --- Prepare Benchee Inputs ---
    benchee_inputs =
      Enum.map(graphs_with_targets_by_size, fn {size, {graph_map, targets}} ->
        {"Size #{size} Tx", {graph_map, targets}}
      end)
      |> Map.new()

    # --- Define Benchmark Jobs ---
    graph_types = [:blockchain, :dag, :blockdag]
    query_types = [
      {:latest, "Latest Tx to Genesis"},
      {:middle, "Middle Tx to Genesis"},
      {:near_genesis, "Near Genesis Tx to Genesis"},
      {:random, "Random Tx to Genesis"}
    ]

    benchmark_jobs =
      for graph_key <- graph_types, {target_key, target_desc} <- query_types, into: %{} do
        job_name = "#{Atom.to_string(graph_key) |> String.capitalize()} - #{target_desc}"
        job_function = fn {graph_map, targets_map} ->
          specific_graph = Map.get(graph_map, graph_key)
          target_node = Map.get(targets_map, target_key)
          GraphOperations.query_path_to_genesis?(specific_graph, target_node)
        end
        {job_name, job_function}
      end

    # Start a Task.Supervisor for Benchee jobs (though Benchee manages its own processes)
    # This supervisor isn't strictly necessary for Benchee itself but good practice if we had other tasks.
    # For this specific use case, Benchee's `run` is blocking, so supervisor management is simpler.
    # The primary supervisor need was for the node simulations in the *other* benchmark.
    # Here, the critical part is ensuring consistent return types.

    # Check if there are any jobs to run before proceeding
    if Enum.empty?(benchmark_jobs) do
      Logger.warning("No benchmark jobs generated. Check input parameters (e.g., graph types, query types).")
      {:error, :no_benchmark_jobs_generated} # Consistent error return
    else
      Logger.info("Starting graph query benchmarks with #{map_size(benchmark_jobs)} distinct jobs...")
      if random_seed_query, do: Logger.info("Using random seed for query target selection: #{random_seed_query}")

      # --- Run Benchee ---
      suite_struct =
        Benchee.run(
          benchmark_jobs,
          inputs: benchee_inputs,
          time: benchee_time,
          memory_time: benchee_memory_time,
          warmup: benchee_warmup,
          formatters: [
            Benchee.Formatters.Console,
            {Benchee.Formatters.HTML, file: benchee_html_output_file}
          ]
        )

      Logger.info("Benchmark finished. Benchee HTML report saved to #{benchee_html_output_file}")

      # --- Vega-Lite Data Extraction and File Generation ---
      if suite_struct && Map.has_key?(suite_struct, :scenarios) && !Enum.empty?(suite_struct.scenarios) do
        try do
          vega_data_list =
            Enum.map(suite_struct.scenarios, fn scenario ->
              [graph_type_str, query_target_str] = String.split(scenario.job_name, " - ", parts: 2)
              tx_size =
                case Regex.run(~r/Size (\d+) Tx/, scenario.input_name) do
                  [_, size_str] -> String.to_integer(size_str)
                  _ -> Logger.warning("Could not parse size from: #{scenario.input_name}"); 0
                end
              ips = scenario |> Map.get(:run_time_data) |> Map.get(:statistics) |> Map.get(:ips, 0.0)

              %{
                "GraphType" => graph_type_str,
                "QueryTarget" => query_target_str,
                "TxCount" => tx_size,
                "IPS" => ips
              }
            end)

          full_vega_spec_map = create_vega_spec_map_enhanced(vega_data_list)
          json_vega_spec = Jason.encode!(full_vega_spec_map, pretty: true)
          File.write!(vega_spec_with_data_file, json_vega_spec)
          Logger.info("Full Vega spec with embedded data saved to #{vega_spec_with_data_file}")
          # Success path returns :ok tuple
          {:ok, %{html_report: benchee_html_output_file, vega_spec: vega_spec_with_data_file}}
        rescue
          e ->
            Logger.error("Error during Vega spec creation: #{inspect(e)}")
            {:error, {:vega_spec_generation_failed, inspect(e)}} # Consistent error return
        catch
          type, reason ->
            Logger.error("Catch during Vega spec: #{type} - #{inspect(reason)}")
            {:error, {:vega_spec_generation_catch, {type, inspect(reason)}}} # Consistent error return
        end
      else
        Logger.error("No scenarios found in Benchee results for Vega spec generation or scenarios list is empty.")
        # If Benchee ran but produced no scenarios (e.g., all jobs errored internally in Benchee)
        # Still return the HTML report path if available.
        {:error, :no_scenarios_for_vega_spec}
      end
    end
    # Note: The Task.Supervisor.start_link and its associated error handling for supervisor start failure
    # was removed as it's not strictly necessary for this Benchee setup, unlike the consensus benchmark
    # which managed many concurrent node processes. Benchee.run is blocking.
    # If a supervisor were critical, its start_link would wrap more of this function.
  end


  # Enhanced Vega Spec to handle new QueryTarget dimension
  defp create_vega_spec_map_enhanced(data_list) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "title" => "Graph Query Performance: Path to Genesis",
      "data" => %{"values" => data_list},
      "facet" => %{
        "column" => %{"field" => "QueryTarget", "type" => "nominal", "title" => "Query Target"}
      },
      "spec" => %{
        "width" => 250,
        "height" => 300,
        "mark" => %{"type" => "line", "point" => true},
        "encoding" => %{
          "x" => %{
            "field" => "TxCount",
            "type" => "quantitative",
            "title" => "Total Transactions",
            "sort" => "ascending"
          },
          "y" => %{
            "field" => "IPS",
            "type" => "quantitative",
            "title" => "Query IPS",
            "axis" => %{"format" => ",.0f"}
          },
          "color" => %{
            "field" => "GraphType",
            "type" => "nominal",
            "title" => "Graph Type"
          },
          "tooltip" => [
            %{"field" => "GraphType", "title" => "Graph"},
            %{"field" => "QueryTarget", "title" => "Target"},
            %{"field" => "TxCount", "title" => "Tx Count"},
            %{"field" => "IPS", "title" => "IPS", "format" => ",.2f"}
          ]
        }
      },
      "resolve" => %{"scale" => %{"y" => "independent"}}
    }
  end
end
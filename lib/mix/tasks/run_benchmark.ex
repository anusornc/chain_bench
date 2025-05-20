defmodule Mix.Tasks.RunBenchmark do
  use Mix.Task
  require Logger

  @shortdoc "Runs the blockchain consensus benchmark using Benchee with configurable options."
  @moduledoc """
  Runs the blockchain consensus benchmark using Benchee.
  Output filenames for Benchee reports (HTML, JSON) will be generated dynamically.

  ## Command-line options

    * `-t N`, `--transactions N`: Sets the number of transactions to N (e.g., 500). Default: 100.
    * `-n LIST`, `--nodes LIST`: Sets the node counts as a comma-separated list (e.g., "1,5,10"). Default: "1,3,5".
    * `-c LIST`, `--consensus LIST`: Sets a comma-separated list of consensus
      algorithms to test (e.g., "poa,pbft,hybrid_poa"). Default: "poa,pbft".
    * `--warmup S`: Benchee warmup time in seconds. Default: 2.
    * `--time S`: Benchee measurement time in seconds. Default: 5.
    * `--output PATH`: Directory for Benchee reports. Default: "benchmark_results".

  ## Examples

      mix run.benchmark
      mix run.benchmark --transactions 1000 --nodes 1,5,10,20
      mix run.benchmark -t 200 -n 1,3,5 -c poa,hybrid_poa --warmup 1 --time 3
      mix run.benchmark --output custom_reports
  """

  # Default values
  @default_tx_count 100
  @default_node_counts_str "1,3,5" # Default as string for parsing
  @default_consensus_types_str "poa,pbft,pow,pos,dpos,hybrid_poa"
  @default_warmup 2
  @default_time 5
  @default_output_path "benchmark_results"

  def run(args) do
    # Ensure the application is started, especially for config values from config.exs
    # Use the correct application name for your project (e.g., :chain_bench)
    Application.ensure_all_started(:chain_bench)
    # Configure Logger level if desired, e.g., Application.put_env(:logger, :level, :info)

    switches = [
      transactions: :integer,
      nodes: :string,
      consensus: :string,
      warmup: :integer,
      time: :integer,
      output: :string
    ]
    aliases = [t: :transactions, n: :nodes, c: :consensus]

    case OptionParser.parse(args, switches: switches, aliases: aliases) do
      {parsed_opts, _parsed_args, []} ->
        tx_count = Keyword.get(parsed_opts, :transactions, @default_tx_count)
        node_counts_str = Keyword.get(parsed_opts, :nodes, @default_node_counts_str)
        consensus_str = Keyword.get(parsed_opts, :consensus, @default_consensus_types_str)
        warmup_s = Keyword.get(parsed_opts, :warmup, @default_warmup)
        time_s = Keyword.get(parsed_opts, :time, @default_time)
        output_p = Keyword.get(parsed_opts, :output, @default_output_path)


        node_counts_to_run = parse_node_argument(node_counts_str)
        consensus_to_run = parse_consensus_argument(consensus_str)

        cond do
          node_counts_to_run == :error_parsing ->
            Mix.shell().error(
              "Invalid format for --nodes. Please use comma-separated positive numbers (e.g., '1,5,10')."
            )
            exit({:shutdown, 1})

          Enum.empty?(node_counts_to_run) and node_counts_str != "" -> # Error if not empty string but parsed to empty
             Mix.shell().error(
              "Node list cannot be empty or contained only invalid values. Please provide valid positive numbers for --nodes (e.g., '1,5,10')."
            )
            exit({:shutdown, 1})

          consensus_to_run == :error_parsing ->
            Mix.shell().error(
              "Invalid format for --consensus. Please use comma-separated algorithm names (e.g., 'poa,pbft')."
            )
            exit({:shutdown, 1})

          Enum.empty?(consensus_to_run) and consensus_str != "" -> # Error if not empty string but parsed to empty
            Mix.shell().error(
              "Consensus list cannot be empty or contained only invalid values. Please provide valid algorithm names for --consensus (e.g., 'poa,pbft')."
            )
            exit({:shutdown, 1})

          true ->
            run_opts = %{
              transactions: tx_count,
              nodes: node_counts_to_run, # This is now a list of integers
              consensus: consensus_to_run, # This is a list of atoms
              warmup: warmup_s,
              time: time_s,
              output_path: output_p
            }

            Logger.info("Starting Benchee benchmark suite with options: #{inspect(run_opts)}")
            Mix.shell().info("Benchee running... This may take some time depending on configuration.")

            # Corrected call to the namespaced BenchmarkRunner module
            case ChainBench.BenchmarkRunner.run_suite(run_opts) do
              %{suite: %{jobs: jobs}} when is_map(jobs) -> # Basic check for Benchee result structure
                Mix.shell().info(
                  "Benchmark suite completed. Reports saved in '#{output_p}'. Check console for Benchee summary."
                )
              {:error, reason} ->
                Mix.shell().error("Benchmark suite failed: #{inspect(reason)}")
                exit({:shutdown, 1})
              # Corrected variable name: removed leading underscore as it's used.
              other_error ->
                 Mix.shell().error("Benchmark suite encountered an unexpected error: #{inspect(other_error)}")
                exit({:shutdown, 1})
            end
        end

      {_parsed_opts, _parsed_args, invalid_opts} ->
        Mix.shell().error("Invalid option(s): #{inspect(invalid_opts)}")
        Mix.shell().error("Use 'mix help #{__MODULE__}' for usage instructions.")
        exit({:shutdown, 1})
    end
  end

  # Parses "1,2,3" into [1,2,3]
  defp parse_node_argument(arg_string) when is_binary(arg_string) do
    try do
      arg_string
      |> String.split(",", trim: true)
      |> Enum.reject(&(&1 == "")) # Remove empty strings if user types "1,,2"
      |> Enum.map(&String.to_integer/1)
      |> Enum.filter(&(&1 > 0)) # Ensure positive node counts
      |> case do
          # If the original string was not empty but parsing resulted in an empty list, it's an error.
          [] -> if String.trim(arg_string) != "", do: :error_parsing, else: []
          valid_list -> Enum.uniq(valid_list) |> Enum.sort() # Unique and sorted
         end
    rescue
      ArgumentError ->
        Logger.error("Error parsing node list: '#{arg_string}'. Contains non-integer or invalid values.")
        :error_parsing
    end
  end
  defp parse_node_argument(_), do: :error_parsing # Catch-all for invalid types

  # Parses "poa,pbft" into [:poa, :pbft]
  defp parse_consensus_argument(arg_string) when is_binary(arg_string) do
    try do
      arg_string
      |> String.split(",", trim: true)
      |> Enum.reject(&(&1 == "")) # Remove empty strings
      |> Enum.map(&String.to_atom/1)
      |> case do
          # If the original string was not empty but parsing resulted in an empty list, it's an error.
          [] -> if String.trim(arg_string) != "", do: :error_parsing, else: []
          valid_list -> Enum.uniq(valid_list)
         end
    rescue
      ArgumentError -> # Catches errors from String.to_atom if format is invalid
        Logger.error("Error parsing consensus list: '#{arg_string}'. Contains invalid atom format (e.g., starts with uppercase, contains spaces).")
        :error_parsing
    end
  end
  defp parse_consensus_argument(_), do: :error_parsing # Catch-all for invalid types
end

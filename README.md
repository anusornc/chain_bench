# ChainBench: Blockchain Benchmarking Suite

ChainBench is an Elixir project designed to run various benchmarks related to blockchain technologies. It currently includes suites for:

1.  **Consensus Algorithm Simulations**: Benchmarks the throughput of simulated consensus algorithms (PoA, PBFT, PoW, PoS, DPoS, HybridPoA) based on transaction count and node count.
2.  **Graph Query Performance**: Benchmarks the performance of querying paths to genesis in different graph structures (Blockchain-like, DAG, BlockDAG) of varying sizes.

## Prerequisites

* Elixir (>= 1.12 recommended, check `.tool-versions` or `mix.exs` for specific version)
* Erlang/OTP (compatible with your Elixir version)
* Mix (Elixir's build tool)

## Setup

1.  **Clone the Repository (if applicable)**:
    ```bash
    git clone <your-repository-url>
    cd chain_bench
    ```

2.  **Install Dependencies**:
    Navigate to the project's root directory (`chain_bench/`) and run:
    ```bash
    mix deps.get
    ```

3.  **Compile the Project**:
    ```bash
    mix compile
    ```

## Running Benchmarks

All benchmarks are run using Mix tasks from the project's root directory.

### 1. Consensus Algorithm Benchmarks

This suite simulates different consensus mechanisms and measures their performance.

* **Task**: `mix run_benchmark` (Note: Ensure your task module is named `Mix.Tasks.Run_Benchmark` or similar for this command)
* **Output**:
    * Console summary from Benchee.
    * HTML report (e.g., `benchmark_results/report_tx_100_nodes_1-3-5_consensus_poa-pbft-pow-pos-dpos-hybrid_poa_DATETIME.html`)
    * JSON data file (e.g., `benchmark_results/report_tx_100_nodes_1-3-5_consensus_poa-pbft-pow-pos-dpos-hybrid_poa_DATETIME.json`)

**How to Run:**

* **With default settings**:
    ```bash
    mix run_benchmark
    ```
    *Default consensus benchmark settings include:*
    * Transactions: 100
    * Node counts: 1, 3, 5
    * Consensus algorithms: poa, pbft, pow, pos, dpos, hybrid_poa
    * Benchee warmup: 2 seconds
    * Benchee measurement time: 5 seconds
    * Output directory: `benchmark_results/`

* **With custom options**:
    ```bash
    mix run_benchmark --transactions 500 --nodes 1,5,10,15 --consensus pow,pos --warmup 1 --time 3 --output my_consensus_reports
    ```

* **View all available options and their defaults**:
    ```bash
    mix help run_benchmark
    ```

### 2. Graph Query Benchmarks

This suite creates different graph structures (Blockchain, DAG, BlockDAG) and benchmarks the performance of querying paths to their genesis transaction/vertex.

* **Task**: `mix run.graph_benchmark`
* **Output**:
    * Console summary from Benchee.
    * HTML report (e.g., `benchmark_graph_results_enhanced/graph_bench_results_DATETIME_benchee.html`)
    * Vega-Lite JSON specification with embedded data (e.g., `benchmark_graph_results_enhanced/graph_bench_results_DATETIME_vega_spec.json`) for visualization.

**How to Run:**

* **With default settings**:
    ```bash
    mix run.graph_benchmark
    ```
    *Default graph benchmark settings include:*
    * Graph sizes (total transactions): 500, 1000, 1500
    * DAG average parents: 3
    * BlockDAG transactions per block: 10
    * BlockDAG k_internal: 2
    * BlockDAG k_external: 1
    * Benchee warmup: 1 second
    * Benchee measurement time: 2 seconds
    * Benchee memory measurement time: 0 seconds (disabled)
    * Output directory: `benchmark_graph_results_enhanced/`

* **With custom options (e.g., specific sizes, DAG parameters, and a seed for graph generation)**:
    ```bash
    mix run_graph_benchmark --sizes 200,400 --dag-parents 2 --tx-per-block 5 --seed-graph 12345 --output-dir custom_graph_reports
    ```

* **View all available options and their defaults**:
    ```bash
    mix help run_graph_benchmark
    ```

## Viewing Reports

* **HTML Reports**: Open the `.html` files generated in the respective output directories (e.g., `benchmark_results/` or `benchmark_graph_results_enhanced/`) in a web browser.
* **Vega-Lite JSON (for Graph Benchmarks)**: The `_vega_spec.json` file can be opened with a Vega-Lite viewer or used with tools that support Vega-Lite specifications (e.g., [Vega Editor](https://vega.github.io/editor/)).

## Project Structure

* `lib/chain_bench/`: Contains the core application logic.
    * `blockchain_simulations.ex`: Logic for simulating consensus algorithms.
    * `benchmark_runner.ex`: Orchestrates consensus benchmarks using Benchee.
    * `graph_operations.ex`: Logic for creating and querying graph structures.
    * `graph_benchmark_runner.ex`: Orchestrates graph benchmarks using Benchee.
* `lib/mix/tasks/`: Contains custom Mix tasks.
    * `run_benchmark.ex` (or `run_benchmark.ex` if you renamed it): CLI for consensus benchmarks. Module inside should be `Mix.Tasks.Run_Benchmark` for `mix run_benchmark` command.
    * `run_graph_benchmark.ex`: CLI for graph benchmarks. Module inside is `Mix.Tasks.RunGraphBenchmark` for `mix run.graph_benchmark` command.
* `config/`: Application configuration.
* `benchmark_results/`: Default output directory for consensus benchmarks.
* `benchmark_graph_results_enhanced/`: Default output directory for graph benchmarks.

## Contributing

(Add guidelines for contributing if this is an open project).

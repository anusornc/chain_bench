defmodule Mix.Tasks.RunGraphBenchmark do
  use Mix.Task
  require Logger

  # --- ค่า Default สำหรับ options ต่างๆ ที่กำหนดเป็น module attributes ---
  @default_sizes_str "500,1000,1500" # รายการขนาดกราฟ (จำนวนธุรกรรมทั้งหมด) เริ่มต้น สำหรับการสร้างกราฟ
  @default_dag_parents 3             # จำนวนเฉลี่ยของ parent transactions เริ่มต้น สำหรับแต่ละ transaction ใหม่ใน DAG บริสุทธิ์
  @default_tx_per_block 10           # จำนวนธุรกรรมเริ่มต้นต่อหนึ่ง block สำหรับโครงสร้าง BlockDAG
  @default_k_internal 2              # จำนวน internal parent candidates เริ่มต้น (ภายใน block เดียวกัน) สำหรับ transaction ใน BlockDAG
  @default_k_external 1              # จำนวน external parent candidates เริ่มต้น (จาก block ก่อนหน้า) สำหรับ transaction ใน BlockDAG
  @default_warmup 1                  # เวลา warmup เริ่มต้นของ Benchee (วินาที)
  @default_time 2                    # เวลาที่ใช้ในการวัดผลเริ่มต้นของ Benchee (วินาที)
  @default_memory_time 0             # เวลาที่ใช้ในการวัดหน่วยความจำเริ่มต้นของ Benchee (วินาที, 0 หมายถึงปิดใช้งาน)
  @default_output_dir "benchmark_graph_results_enhanced" # ไดเรกทอรีเริ่มต้นสำหรับบันทึกรายงานผล benchmark

  @shortdoc "Runs graph structure query benchmarks with enhanced options."
  # คำอธิบายสั้นๆ ของ Mix task นี้
  @moduledoc """
  Runs benchmarks for querying paths to genesis in different graph structures.
  Allows specifying random seeds for deterministic graph generation and query target selection.

  Outputs a Benchee HTML report and a Vega-Lite JSON specification.
  รัน benchmark สำหรับการ query เส้นทางไปยัง genesis ในโครงสร้างกราฟแบบต่างๆ
  สามารถกำหนด random seed เพื่อให้การสร้างกราฟและการเลือก target ของ query เป็นแบบ deterministic ได้

  สร้างรายงานผลลัพธ์เป็น HTML ของ Benchee และ JSON ในรูปแบบ Vega-Lite

  ## Command-line options (ตัวเลือกบรรทัดคำสั่ง)

    * `--sizes LIST`: Comma-separated list of total transaction counts for graphs (e.g., "500,1000,2000").
      Default: "#{@default_sizes_str}". (ค่าเริ่มต้น: "#{@default_sizes_str}")
    * `--dag-parents N`: Average number of parents for nodes in the pure DAG graph. Default: #{@default_dag_parents}.
      (ค่าเริ่มต้น: #{@default_dag_parents})
    * `--tx-per-block N`: Number of transactions per block for BlockDAG. Default: #{@default_tx_per_block}.
      (ค่าเริ่มต้น: #{@default_tx_per_block})
    * `--k-internal N`: Number of internal parent candidates for BlockDAG. Default: #{@default_k_internal}.
      (ค่าเริ่มต้น: #{@default_k_internal})
    * `--k-external N`: Number of external parent candidates for BlockDAG. Default: #{@default_k_external}.
      (ค่าเริ่มต้น: #{@default_k_external})
    * `--warmup S`: Benchee warmup time in seconds. Default: #{@default_warmup}.
      (ค่าเริ่มต้น: #{@default_warmup})
    * `--time S`: Benchee measurement time in seconds. Default: #{@default_time}.
      (ค่าเริ่มต้น: #{@default_time})
    * `--memory-time S`: Benchee memory measurement time in seconds. Default: #{@default_memory_time}.
      (ค่าเริ่มต้น: #{@default_memory_time})
    * `--output-dir PATH`: Directory for reports. Default: "#{@default_output_dir}".
      (ค่าเริ่มต้น: "#{@default_output_dir}")
    * `--output-basename NAME`: Base name for output files (timestamped if not provided).
      (ชื่อไฟล์พื้นฐานสำหรับผลลัพธ์ ถ้าไม่ระบุจะใช้ timestamp)
    * `--seed-graph INT`: Optional integer seed for deterministic graph generation.
      (seed (integer) ที่เป็น optional สำหรับการสร้างกราฟแบบ deterministic)
    * `--seed-query INT`: Optional integer seed for deterministic random query target selection.
      (seed (integer) ที่เป็น optional สำหรับการเลือก target ของ query แบบสุ่มที่ deterministic)

  ## Examples (ตัวอย่างการใช้งาน)

      mix run.graph_benchmark
      mix run.graph_benchmark --sizes 100,200 --dag-parents 2 --seed-graph 12345
  """

  # ฟังก์ชันหลักที่ Mix จะเรียกเมื่อรัน task นี้
  def run(args) do
    Application.ensure_all_started(:chain_bench)
    switches = [
      sizes: :string,
      dag_parents: :integer,
      tx_per_block: :integer,
      k_internal: :integer,
      k_external: :integer,
      warmup: :integer,
      time: :integer,
      memory_time: :integer,
      output_dir: :string,
      output_basename: :string,
      seed_graph: :integer,
      seed_query: :integer
    ]
    case OptionParser.parse(args, switches: switches) do
      {parsed_opts, _remaining_args, []} ->
        sizes_str = Keyword.get(parsed_opts, :sizes, @default_sizes_str)
        dag_parents = Keyword.get(parsed_opts, :dag_parents, @default_dag_parents)
        tx_per_block = Keyword.get(parsed_opts, :tx_per_block, @default_tx_per_block)
        k_internal = Keyword.get(parsed_opts, :k_internal, @default_k_internal)
        k_external = Keyword.get(parsed_opts, :k_external, @default_k_external)
        warmup_s = Keyword.get(parsed_opts, :warmup, @default_warmup)
        time_s = Keyword.get(parsed_opts, :time, @default_time)
        memory_s = Keyword.get(parsed_opts, :memory_time, @default_memory_time)
        output_dir_path = Keyword.get(parsed_opts, :output_dir, @default_output_dir)
        output_basename = Keyword.get(parsed_opts, :output_basename)
        seed_graph_opt = Keyword.get(parsed_opts, :seed_graph)
        seed_query_opt = Keyword.get(parsed_opts, :seed_query)

        # Use shared helpers
        sizes_list = ChainBench.BenchmarkCliHelpers.parse_positive_int_list(sizes_str)

        cond do
          sizes_list == :error_parsing or (Enum.empty?(sizes_list) and sizes_str != "") ->
            error_exit("Invalid format for --sizes. Use comma-separated positive numbers.")
          dag_parents <= 0 -> error_exit("--dag-parents must be a positive integer.")
          tx_per_block <= 0 -> error_exit("--tx-per-block must be a positive integer.")
          k_internal < 0 -> error_exit("--k-internal must be a non-negative integer.")
          k_external <= 0 -> error_exit("--k-external must be a positive integer.")
          true ->
            run_opts = %{
              sizes: sizes_list,
              dag_avg_parents: dag_parents,
              blockdag_params: %{
                tx_per_block: tx_per_block,
                k_internal: k_internal,
                k_external: k_external
              },
              benchee_warmup: warmup_s,
              benchee_time: time_s,
              benchee_memory_time: memory_s,
              output_dir: output_dir_path,
              output_basename: output_basename,
              random_seed_graph: seed_graph_opt,
              random_seed_query: seed_query_opt
            }
            Logger.info("Starting Enhanced Graph Benchmark suite with options: #{inspect(run_opts)}")
            Mix.shell().info("Benchee running for graph benchmarks... This may take some time.")
            case ChainBench.GraphBenchmarkRunner.run_suite(run_opts) do
              {:ok, report_paths} ->
                Mix.shell().info("Graph Benchmark suite completed.")
                Mix.shell().info("Benchee HTML report: #{report_paths.html_report}")
                Mix.shell().info("Vega-Lite JSON spec: #{report_paths.vega_spec}")
              {:error, reason} ->
                Mix.shell().error("Graph Benchmark suite failed: #{inspect(reason)}")
                exit({:shutdown, 1})
            end
        end
      {_parsed_opts, _remaining_args, invalid_opts} ->
        error_exit("Invalid option(s) for graph benchmark: #{inspect(invalid_opts)}\nUse 'mix help #{__MODULE__}' for usage instructions.")
    end
  end

  # ฟังก์ชันช่วยสำหรับแสดง error message และออกจากโปรแกรม
  defp error_exit(message) do
    Mix.shell().error(message) # แสดง error message
    exit({:shutdown, 1})       # ออกจากโปรแกรมด้วย status code 1
  end
end

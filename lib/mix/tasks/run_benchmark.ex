defmodule Mix.Tasks.RunBenchmark do # หรือ Mix.Tasks.Run_Benchmark ขึ้นอยู่กับการตั้งชื่อโมดูลของคุณ
  use Mix.Task
  require Logger

  # --- ค่า Default สำหรับ options ต่างๆ ---
  @default_tx_count 100                             # จำนวนธุรกรรมเริ่มต้น
  @default_node_counts_str "1,3,5"                  # รายการจำนวนโหนดเริ่มต้น (เป็น string)
  @default_consensus_types_str "poa,pbft,pow,pos,dpos,hybrid_poa" # รายการ consensus algorithms เริ่มต้น (เป็น string)
  @default_warmup 2                                 # เวลา warmup เริ่มต้น (วินาที)
  @default_time 5                                   # เวลาที่ใช้ในการวัดผลเริ่มต้น (วินาที)
  @default_output_path "benchmark_results"          # ไดเรกทอรีสำหรับเก็บผลลัพธ์เริ่มต้น

  @shortdoc "Runs the blockchain consensus benchmark using Benchee."
  # คำอธิบายสั้นๆ ของ Mix task นี้
  @moduledoc """
  Runs the blockchain consensus benchmark using Benchee.
  Outputs Benchee HTML report and a Vega-Lite JSON specification.
  รัน benchmark สำหรับ consensus ของ blockchain โดยใช้ Benchee
  สร้างรายงานผลลัพธ์เป็น HTML และ JSON ในรูปแบบ Vega-Lite

  ## Command-line options (ตัวเลือกบรรทัดคำสั่ง)

    * `-t N`, `--transactions N`: Sets the number of transactions to N. Default: #{@default_tx_count}.
      (กำหนดจำนวนธุรกรรมเป็น N. ค่าเริ่มต้น: #{@default_tx_count})
    * `-n LIST`, `--nodes LIST`: Sets node counts as a comma-separated list. Default: "#{@default_node_counts_str}".
      (กำหนดจำนวนโหนดเป็นรายการคั่นด้วยจุลภาค. ค่าเริ่มต้น: "#{@default_node_counts_str}")
    * `-c LIST`, `--consensus LIST`: Sets consensus algorithms. Default: "#{@default_consensus_types_str}".
      (กำหนด consensus algorithms เป็นรายการคั่นด้วยจุลภาค. ค่าเริ่มต้น: "#{@default_consensus_types_str}")
    * `--warmup S`: Benchee warmup time in seconds. Default: #{@default_warmup}.
      (กำหนดเวลา warmup ของ Benchee เป็นวินาที. ค่าเริ่มต้น: #{@default_warmup})
    * `--time S`: Benchee measurement time in seconds. Default: #{@default_time}.
      (กำหนดเวลาที่ใช้ในการวัดผลของ Benchee เป็นวินาที. ค่าเริ่มต้น: #{@default_time})
    * `--output PATH`: Directory for reports. Default: "#{@default_output_path}".
      (กำหนดไดเรกทอรีสำหรับเก็บรายงาน. ค่าเริ่มต้น: "#{@default_output_path}")

  ## Examples (ตัวอย่างการใช้งาน)

      mix run_benchmark # หรือ mix run.benchmark ขึ้นอยู่กับการตั้งชื่อ task ของคุณ
      mix run_benchmark -t 500 -n 1,5,10 -c pow,pos
  """

  # ฟังก์ชันหลักที่ Mix จะเรียกเมื่อรัน task นี้
  def run(args) do
    # ตรวจสอบให้แน่ใจว่าแอปพลิเคชัน (:chain_bench) ได้เริ่มทำงานแล้ว (เพื่อให้ config ถูกโหลด)
    Application.ensure_all_started(:chain_bench)

    # กำหนด switches และ aliases สำหรับการ parse command-line arguments
    switches = [
      transactions: :integer,
      nodes: :string,
      consensus: :string,
      warmup: :integer,
      time: :integer,
      output: :string
    ]
    aliases = [t: :transactions, n: :nodes, c: :consensus] # ตัวย่อสำหรับ options

    # Parse command-line arguments
    case OptionParser.parse(args, switches: switches, aliases: aliases) do
      # กรณี parse สำเร็จและไม่มี options ที่ไม่ถูกต้อง
      {parsed_opts, _remaining_args, []} ->
        # ดึงค่า options ที่ parse ได้ หรือใช้ค่า default ถ้าไม่ได้ระบุ
        tx_count = Keyword.get(parsed_opts, :transactions, @default_tx_count)
        node_counts_str = Keyword.get(parsed_opts, :nodes, @default_node_counts_str)
        consensus_str = Keyword.get(parsed_opts, :consensus, @default_consensus_types_str)
        warmup_s = Keyword.get(parsed_opts, :warmup, @default_warmup)
        time_s = Keyword.get(parsed_opts, :time, @default_time)
        output_p = Keyword.get(parsed_opts, :output, @default_output_path)

        # Use shared helpers
        node_counts_to_run = ChainBench.BenchmarkCliHelpers.parse_positive_int_list(node_counts_str)
        consensus_to_run = ChainBench.BenchmarkCliHelpers.parse_atom_list(consensus_str)

        # ตรวจสอบความถูกต้องของ options ที่แปลงแล้ว
        cond do
          # กรณี node counts ไม่ถูกต้อง
          node_counts_to_run == :error_parsing or (Enum.empty?(node_counts_to_run) and node_counts_str != "") ->
            error_exit("Invalid format for --nodes. Use comma-separated positive numbers.")
          # กรณี consensus types ไม่ถูกต้อง
          consensus_to_run == :error_parsing or (Enum.empty?(consensus_to_run) and consensus_str != "") ->
            error_exit("Invalid format for --consensus. Use comma-separated algorithm names.")
          # กรณี options ถูกต้องทั้งหมด
          true ->
            # สร้าง map ของ options ที่จะส่งให้ BenchmarkRunner
            run_opts = %{
              transactions: tx_count,
              nodes: node_counts_to_run,
              consensus: consensus_to_run,
              warmup: warmup_s,
              time: time_s,
              output_path: output_p
            }

            Logger.info("Starting Consensus Benchmark suite with options: #{inspect(run_opts)}") # แจ้ง log ว่ากำลังเริ่ม benchmark
            Mix.shell().info("Benchee running for consensus benchmarks... This may take some time.") # แจ้งผู้ใช้

            # เรียก ChainBench.BenchmarkRunner.run_suite เพื่อเริ่มการ benchmark
            case ChainBench.BenchmarkRunner.run_suite(run_opts) do
              {:ok, report_paths} -> # กรณี benchmark สำเร็จ
                Mix.shell().info("Consensus Benchmark suite completed.")
                Mix.shell().info("Benchee HTML report: #{report_paths.html_report}")
                Mix.shell().info("Vega-Lite JSON spec: #{report_paths.vega_spec}")

              {:error, reason} -> # กรณี benchmark ล้มเหลว (error ที่คาดไว้)
                Mix.shell().error("Consensus Benchmark suite failed: #{inspect(reason)}")
                exit({:shutdown, 1}) # ออกจากโปรแกรมพร้อม error code
            end
        end
      # กรณีมี options ที่ไม่ถูกต้อง
      {_parsed_opts, _remaining_args, invalid_opts} ->
        error_exit("Invalid option(s): #{inspect(invalid_opts)}\nUse 'mix help #{__MODULE__}' for usage instructions.")
    end
  end

  # ฟังก์ชันช่วยสำหรับแสดง error message และออกจากโปรแกรม
  defp error_exit(message) do
    Mix.shell().error(message) # แสดง error message
    exit({:shutdown, 1})       # ออกจากโปรแกรมด้วย status code 1
  end
end

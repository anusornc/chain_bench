defmodule ChainBench.BenchmarkRunner do
  @moduledoc """
  Orchestrates blockchain consensus benchmarks using the Benchee library,
  as part of the ChainBench application. Now includes Vega-Lite JSON output.
  โมดูลนี้ทำหน้าที่จัดการและรัน benchmark สำหรับ consensus Pmechanism ต่างๆ โดยใช้ไลบรารี Benchee
  และสร้างผลลัพธ์เป็น JSON ในรูปแบบ Vega-Lite สำหรับการแสดงผลกราฟ
  """
  require Logger

  # Alias for the simulation functions if they are in a different module
  # For example, if simulations are in ChainBench.BlockchainSimulations
  # กำหนดชื่อย่อสำหรับโมดูลที่เก็บฟังก์ชันจำลองการทำงานของ consensus
  alias ChainBench.BlockchainSimulations

  @doc """
  Runs the Benchee benchmark suite with options provided in a map.
  รันชุด benchmark ด้วย Benchee โดยรับค่าพารามิเตอร์ต่างๆ ผ่าน map `opts`

  Args:
    - `opts`: A map containing benchmark options:
      - `transactions`: Number of transactions (integer). # จำนวนธุรกรรม
      - `nodes`: A list of node counts (e.g., `[1, 5, 10]`). # รายการของจำนวนโหนดที่จะทดสอบ
      - `consensus`: A list of consensus algorithm atoms (e.g., `[:poa, :pbft]`). # รายการของ consensus algorithm ที่จะทดสอบ
      - `warmup`: Warmup time in seconds for Benchee. # เวลา warmup (วินาที)
      - `time`: Measurement time in seconds for Benchee. # เวลาที่ใช้ในการวัดผล (วินาที)
      - `output_path`: Path to store benchmark reports. # ตำแหน่งที่เก็บไฟล์รายงานผล
  """
  def run_suite(opts) do
    # ดึงค่าพารามิเตอร์จาก opts หรือใช้ค่า default
    tx_count = Map.fetch!(opts, :transactions)
    node_counts_list = Map.fetch!(opts, :nodes)
    consensus_types_list = Map.fetch!(opts, :consensus)
    warmup_time = Map.get(opts, :warmup, Application.get_env(:chain_bench, :benchee_warmup, 2))
    measure_time = Map.get(opts, :time, Application.get_env(:chain_bench, :benchee_time, 5))
    output_path = Map.get(opts, :output_path, "benchmark_results")

    # สร้าง directory สำหรับเก็บผลลัพธ์ถ้ายังไม่มี
    File.mkdir_p(output_path)

    # สร้างชื่อไฟล์พื้นฐานสำหรับรายงานต่างๆ
    filename_base = generate_filename_base(opts)
    benchee_html_file = Path.join(output_path, filename_base <> "_benchee.html")
    vega_spec_file = Path.join(output_path, filename_base <> "_vega_spec.json") # สำหรับ Vega-Lite plot

    # สร้างชื่อที่ไม่ซ้ำกันสำหรับ Task.Supervisor
    supervisor_name = :"consensus_node_supervisor_#{System.unique_integer([:positive])}"

    # เริ่ม Task.Supervisor สำหรับจัดการ process ของโหนดจำลอง
    case Task.Supervisor.start_link(name: supervisor_name) do
      {:ok, supervisor_pid} ->
        Logger.info("Task.Supervisor for consensus nodes started: #{inspect(supervisor_pid)}") # Supervisor เริ่มทำงานแล้ว

        # สร้างรายการ benchmark jobs สำหรับ Benchee
        benchmark_jobs =
          for consensus_type <- consensus_types_list,
              node_count <- node_counts_list,
              into: %{} do
            job_name =
              "#{to_string(consensus_type) |> String.upcase()} / #{node_count} nodes / #{tx_count} tx"

            # ฟังก์ชัน wrapper ที่ Benchee จะเรียกเพื่อรันการจำลอง
            simulation_fn_wrapper = fn ->
              get_simulation_function(consensus_type).(tx_count, node_count, supervisor_pid)
            end

            {job_name, simulation_fn_wrapper}
          end

        if Enum.empty?(benchmark_jobs) do
          Logger.warning("No consensus benchmark jobs generated. Check input parameters.") # ไม่มี job ถูกสร้าง
          stop_supervisor(supervisor_pid) # สั่งหยุด Supervisor ถ้าไม่มี job
          {:error, :no_benchmark_jobs_generated}
        else
          Logger.info(
            "Configuring Benchee suite for consensus with #{Enum.count(benchmark_jobs)} jobs. " <>
              "Warmup: #{warmup_time}s, Time: #{measure_time}s."
          ) # กำลังตั้งค่า Benchee

          # ตั้งค่า Benchee
          benchee_config = [
            warmup: warmup_time,
            time: measure_time,
            formatters: [
              Benchee.Formatters.Console, # แสดงผลทาง console
              {Benchee.Formatters.HTML, file: benchee_html_file} # สร้างรายงาน HTML
            ]
          ]

          # รัน Benchee suite
          suite_results = Benchee.run(benchmark_jobs, benchee_config)
          # สั่งหยุด Supervisor หลังจาก Benchee รันเสร็จ
          stop_supervisor(supervisor_pid)
          Logger.info("Consensus benchmark suite finished. Reports saved to #{output_path}") # Benchmark เสร็จสิ้น


          # --- สร้างไฟล์ JSON ในรูปแบบ Vega-Lite ---
          generate_vega_lite_spec(suite_results, vega_spec_file, tx_count)

          # คืนค่า path ของไฟล์รายงานที่สร้างขึ้น
          {:ok, %{html_report: benchee_html_file, vega_spec: vega_spec_file}}
        end

      {:error, reason} ->
        Logger.error("Failed to start Task.Supervisor for consensus nodes: #{inspect(reason)}") # ไม่สามารถเริ่ม Supervisor ได้
        {:error, {:supervisor_start_failed, reason}}
    end
  end

  # ฟังก์ชันสำหรับหยุด Task.Supervisor
  defp stop_supervisor(pid) do
    if Process.alive?(pid) do
      Logger.info("Attempting to stop Task.Supervisor: #{inspect(pid)}") # พยายามหยุด Supervisor
      Process.unlink(pid) # ยกเลิกการ link process ปัจจุบันกับ Supervisor
      Process.exit(pid, :normal) # สั่งให้ Supervisor ออกแบบปกติ
      Process.sleep(100) # รอสักครู่ให้ process จัดการการออก

      unless Process.alive?(pid) do
        Logger.info("Task.Supervisor for consensus nodes stopped: #{inspect(pid)}") # Supervisor หยุดทำงานแล้ว
      else
        Logger.warning("Task.Supervisor #{inspect(pid)} still alive after :normal exit. Forcing with :kill.") # Supervisor ยังไม่หยุด, สั่ง kill
        Process.exit(pid, :kill)
      end
    else
      Logger.warning("Task.Supervisor #{inspect(pid)} was not alive when attempting to stop.") # Supervisor ไม่ได้ทำงานอยู่แล้ว
    end
  end

  # ฟังก์ชันสำหรับดึงฟังก์ชันจำลองการทำงานของ consensus ที่ต้องการ
  defp get_simulation_function(consensus_type) do
    case consensus_type do
      :poa -> &BlockchainSimulations.simulate_poa/3
      :pbft -> &BlockchainSimulations.simulate_pbft/3
      :pow -> &BlockchainSimulations.simulate_pow/3
      :pos -> &BlockchainSimulations.simulate_pos/3
      :dpos -> &BlockchainSimulations.simulate_dpos/3
      :hybrid_poa -> &BlockchainSimulations.simulate_hybrid_poa/3
      _ ->
        fn _, _, _ ->
          Logger.error("Attempted to run unknown consensus type: #{consensus_type}") # ไม่รู้จักประเภท consensus นี้
          :error_unknown_consensus
        end
    end
  end

  # ฟังก์ชันสำหรับสร้างส่วนหนึ่งของชื่อไฟล์ตามพารามิเตอร์ที่ใช้รัน
  defp generate_filename_base(opts) do
    datetime_str =
      DateTime.utc_now()
      |> DateTime.to_string()
      |> String.replace(~r/[:\.]/, "-")
      |> String.replace("T", "_")
      |> String.replace("Z", "")

    tx_str = "tx_#{Map.get(opts, :transactions)}"
    nodes_val = Map.get(opts, :nodes, [])
    nodes_str = "nodes_#{Enum.join(nodes_val, "-")}"
    consensus_val = Map.get(opts, :consensus, [])
    consensus_str = "consensus_#{Enum.map(consensus_val, &to_string/1) |> Enum.join("-")}"

    "report_#{tx_str}_#{nodes_str}_#{consensus_str}_#{datetime_str}"
  end

  # --- สร้างไฟล์ JSON ในรูปแบบ Vega-Lite สำหรับ Consensus Benchmarks ---
  defp generate_vega_lite_spec(suite_struct, output_file, tx_count_for_run) do
    Logger.debug("Attempting to generate Vega-Lite spec. Output file: #{output_file}") # เริ่มสร้าง Vega-Lite spec

    # ตรวจสอบว่า Benchee suite_struct มีข้อมูล scenarios ที่ถูกต้อง
    if suite_struct && Map.has_key?(suite_struct, :scenarios) && is_list(suite_struct.scenarios) && !Enum.empty?(suite_struct.scenarios) do
      Logger.info("Found #{Enum.count(suite_struct.scenarios)} scenarios in Benchee results. Processing for Vega-Lite.") # พบ scenarios, กำลังประมวลผล
      try do
        # แปลงข้อมูลจาก Benchee scenarios ให้อยู่ในรูปแบบที่ Vega-Lite ต้องการ
        vega_data_list =
          Enum.map(suite_struct.scenarios, fn scenario ->
            parts = String.split(scenario.job_name, " / ", parts: 3) # แยกส่วนจากชื่อ job

            consensus_type_str = List.first(parts) # เช่น "POA"
            nodes_str = Enum.at(parts, 1)          # เช่น "1 nodes"

            node_count =
              if nodes_str do
                case Regex.run(~r/^(\d+) nodes$/, nodes_str) do # ดึงจำนวนโหนด
                  [_, count_str] -> String.to_integer(count_str)
                  _ ->
                    Logger.warning("Could not parse node count from: '#{nodes_str}' in job '#{scenario.job_name}'. Defaulting to 0.")
                    0
                end
              else
                Logger.warning("Could not extract nodes string from job_name: '#{scenario.job_name}'. Defaulting to 0.")
                0
              end

            # ดึงค่า IPS (Iterations Per Second) อย่างปลอดภัย
            ips =
              scenario
              |> Map.get(:run_time_data, %{})
              |> Map.get(:statistics, %{})
              |> Map.get(:ips, 0.0)

            if ips == 0.0 do
              Logger.warning("IPS is 0.0 for job: '#{scenario.job_name}'. Check Benchee statistics.") # IPS เป็น 0, ควรตรวจสอบ
            end

            # สร้าง map ข้อมูลสำหรับ Vega-Lite
            %{
              "Consensus" => consensus_type_str,
              "Nodes" => node_count,
              "IPS" => ips,
              "Transactions" => tx_count_for_run # จำนวนธุรกรรมที่ใช้ในการรันนี้
            }
          end)

        Logger.debug("Transformed data for Vega-Lite: #{inspect(vega_data_list, pretty: true, limit: :infinity)}") # ข้อมูลที่แปลงแล้ว

        if Enum.empty?(vega_data_list) do
          Logger.error("Vega data list is empty after processing scenarios. No Vega-Lite file will be generated.") # ไม่มีข้อมูลสำหรับ Vega-Lite
        else
          # สร้าง Vega-Lite specification ทั้งหมด
          full_vega_spec_map = create_consensus_vega_spec_map(vega_data_list, tx_count_for_run)
          # แปลงเป็น JSON string
          json_vega_spec = Jason.encode!(full_vega_spec_map, pretty: true)
          # เขียนลงไฟล์
          File.write!(output_file, json_vega_spec)
          Logger.info("Consensus Vega-Lite spec with embedded data saved to #{output_file}") # บันทึกไฟล์ Vega-Lite spec แล้ว
        end
      rescue
        e -> Logger.error("ERROR during Consensus Vega-Lite spec creation: #{inspect(e)}\nStacktrace: #{inspect(__STACKTRACE__)}") # เกิดข้อผิดพลาด
      catch
        type, reason -> Logger.error("CATCH during Consensus Vega-Lite spec: #{type} - #{inspect(reason)}\nStacktrace: #{inspect(__STACKTRACE__)}") # เกิดข้อผิดพลาด (catch)
      end
    else
      Logger.error("Could not generate Vega-Lite spec: Benchee results missing :scenarios, :scenarios is not a list, or scenarios list is empty.") # ข้อมูล scenarios ไม่ถูกต้อง
    end
  end

  # ฟังก์ชันสำหรับสร้าง Vega-Lite specification map
  defp create_consensus_vega_spec_map(data_list, tx_count) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "title" => "Consensus Algorithm Performance (Transactions: #{tx_count})",
      "description" => "Throughput (IPS) vs. Number of Nodes for various consensus algorithms.",
      "data" => %{"values" => data_list}, # ข้อมูลที่แปลงแล้วจะถูกใส่ที่นี่
      "mark" => %{"type" => "line", "point" => true}, # ประเภทของกราฟ (เส้นและจุด)
      "encoding" => %{ # การ map ข้อมูลไปยังแกนและสี
        "x" => %{
          "field" => "Nodes", # แกน X คือจำนวนโหนด
          "type" => "quantitative",
          "title" => "Number of Nodes",
          "axis" => %{"tickMinStep" => 1}, # ให้แสดง tick เป็นจำนวนเต็ม
          "sort" => "ascending" # เรียงข้อมูลตามแกน X จากน้อยไปมาก
        },
        "y" => %{
          "field" => "IPS", # แกน Y คือ IPS
          "type" => "quantitative",
          "title" => "Throughput (Iterations Per Second)",
          "axis" => %{"format" => ",.0f"} # รูปแบบการแสดงผลแกน Y
        },
        "color" => %{
          "field" => "Consensus", # สีของเส้นแทนประเภท Consensus
          "type" => "nominal",
          "title" => "Consensus Algorithm"
        },
        "tooltip" => [ # ข้อมูลที่จะแสดงเมื่อ hover บนจุด
          %{"field" => "Consensus", "type" => "nominal", "title" => "Algorithm"},
          %{"field" => "Nodes", "type" => "quantitative", "title" => "Nodes"},
          %{"field" => "IPS", "type" => "quantitative", "title" => "IPS", "format" => ",.2f"},
          %{"field" => "Transactions", "type" => "quantitative", "title" => "Txs per Run"}
        ]
      },
      "width" => "container", # ให้ความกว้างของกราฟปรับตาม container
      "height" => 400
    }
  end
end

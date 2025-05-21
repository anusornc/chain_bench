defmodule ChainBench.GraphBenchmarkRunner do
  @moduledoc """
  Orchestrates graph creation and benchmarking of query operations using Benchee.
  Implements targeted queries and optional deterministic graph generation.
  โมดูลนี้ทำหน้าที่จัดการการสร้างกราฟและทดสอบประสิทธิภาพ (benchmark) ของการ query ข้อมูลในกราฟโดยใช้ Benchee
  รองรับการ query แบบเจาะจง (targeted queries) และการสร้างกราฟแบบกำหนดผลลัพธ์ได้ (deterministic) ผ่านการใช้ seed
  """
  require Logger

  alias ChainBench.GraphOperations # กำหนดชื่อย่อสำหรับ ChainBench.GraphOperations เพื่อความสะดวก

  @doc """
  Runs the full graph benchmark suite with enhanced query targeting.
  รันชุด benchmark สำหรับกราฟทั้งหมด พร้อมด้วยการ query แบบเจาะจงที่ปรับปรุงแล้ว

  `opts` is a map containing:
    - `:sizes`: List of total transactions for graphs. # รายการจำนวนธุรกรรมทั้งหมดสำหรับสร้างกราฟ
    - `:dag_avg_parents`: Integer for DAG graph. # จำนวนเฉลี่ยของ parent node สำหรับ DAG
    - `:blockdag_params`: Map with `:tx_per_block`, `:k_internal`, `:k_external`. # พารามิเตอร์สำหรับ BlockDAG
    - `:benchee_warmup`, `:benchee_time`, `:benchee_memory_time`: Benchee settings. # การตั้งค่า Benchee
    - `:output_dir`, `:output_basename`: For report filenames. # ชื่อไดเรกทอรีและชื่อไฟล์พื้นฐานสำหรับรายงาน
    - `:random_seed_graph`: Optional integer seed for graph generation. # seed (integer) สำหรับการสร้างกราฟแบบสุ่มที่กำหนดผลลัพธ์ได้ (ถ้ามี)
    - `:random_seed_query`: Optional integer seed for selecting random query targets. # seed (integer) สำหรับการเลือก target node แบบสุ่มที่กำหนดผลลัพธ์ได้ (ถ้ามี)
  """
  def run_suite(opts) do
    # --- ดึงค่าพารามิเตอร์ต่างๆ จาก opts ---
    sizes = Map.fetch!(opts, :sizes)
    dag_avg_parents = Map.fetch!(opts, :dag_avg_parents)
    blockdag_params = Map.fetch!(opts, :blockdag_params)
    benchee_warmup = Map.fetch!(opts, :benchee_warmup)
    benchee_time = Map.fetch!(opts, :benchee_time)
    benchee_memory_time = Map.fetch!(opts, :benchee_memory_time)
    output_dir = Map.fetch!(opts, :output_dir)
    output_basename_opt = Map.get(opts, :output_basename) # อาจเป็น nil
    random_seed_graph = Map.get(opts, :random_seed_graph) # อาจเป็น nil
    random_seed_query = Map.get(opts, :random_seed_query) # อาจเป็น nil

    # --- การตั้งค่าชื่อไฟล์และไดเรกทอรี ---
    base_filename_path =
      Path.join(
        output_dir,
        if is_nil(output_basename_opt) or String.trim(output_basename_opt) == "" do
          # ถ้าไม่ได้กำหนดชื่อไฟล์พื้นฐานมา ให้สร้างจาก timestamp และ seed (ถ้ามี)
          timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
          seed_suffix = if random_seed_graph, do: "_seed#{random_seed_graph}", else: ""
          "graph_bench_results_#{timestamp}#{seed_suffix}"
        else
          output_basename_opt # ใช้ชื่อที่กำหนดมา
        end
      )
    File.mkdir_p(output_dir) # สร้างไดเรกทอรีถ้ายังไม่มี
    benchee_html_output_file = base_filename_path <> "_benchee.html" # ชื่อไฟล์รายงาน HTML ของ Benchee
    vega_spec_with_data_file = base_filename_path <> "_vega_spec.json" # ชื่อไฟล์ Vega-Lite JSON

    Logger.info("Setting up graphs for benchmarking...") # เริ่มการตั้งค่ากราฟ
    if random_seed_graph, do: Logger.info("Using random seed for graph generation: #{random_seed_graph}") # แจ้งถ้าใช้ seed
    setup_start_time = System.monotonic_time(:millisecond) # จับเวลาเริ่มตั้งค่า

    # --- การตั้งค่ากราฟ (Graph Setup) ---
    # สร้างกราฟครั้งเดียวสำหรับแต่ละขนาด โดยส่ง random_seed_graph ไปด้วย
    graph_creation_opts = %{random_seed: random_seed_graph}

    graphs_with_targets_by_size =
      Enum.map(sizes, fn size ->
        Logger.info("Creating graphs of size #{size} transactions...") # กำลังสร้างกราฟขนาด...
        num_blocks = ceil(size / blockdag_params.tx_per_block) |> trunc # คำนวณจำนวนบล็อกสำหรับ BlockDAG

        # สร้างโครงสร้างกราฟต่างๆ
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
        # คำนวณ target node ล่วงหน้าสำหรับขนาดกราฟนี้ เพื่อความสอดคล้องในการทดสอบแต่ละ job ของ Benchee
        # ส่ง random_seed_query ไปเพื่อการเลือก target node แบบสุ่มที่กำหนดผลลัพธ์ได้
        query_target_opts = %{random_seed_for_query: random_seed_query}
        targets = %{
          latest: GraphOperations.get_latest_tx_vertex(size),
          middle: GraphOperations.get_middle_tx_vertex(size),
          near_genesis: GraphOperations.get_near_genesis_tx_vertex(size),
          random: GraphOperations.get_random_tx_vertex(size, query_target_opts)
        }
        {size, graph_map_for_size, targets} # เก็บ ขนาด, map ของกราฟ, และ map ของ target node ที่เลือกไว้
      end)
      |> Map.new(fn {s, gm, t} -> {s, {gm, t}} end) # แปลงเป็น map: size => {graph_map, targets_map}


    setup_duration_ms = System.monotonic_time(:millisecond) - setup_start_time # คำนวณเวลารวมที่ใช้ตั้งค่า
    Logger.info("Graph setup finished in #{setup_duration_ms / 1000} seconds.") # การตั้งค่ากราฟเสร็จสิ้น

    # --- เตรียม Input สำหรับ Benchee ---
    # Benchee ต้องการ input ในรูปแบบ %{"ชื่อ Input" => actual_input_for_function}
    benchee_inputs =
      Enum.map(graphs_with_targets_by_size, fn {size, {graph_map, targets}} ->
        {"Size #{size} Tx", {graph_map, targets}} # ชื่อ Input จะแสดงในรายงาน Benchee
      end)
      |> Map.new()

    # --- กำหนด Benchmark Jobs สำหรับ Benchee ---
    # สำหรับแต่ละประเภทกราฟ จะสร้าง job สำหรับ query target ที่แตกต่างกัน
    graph_types = [:blockchain, :dag, :blockdag] # ประเภทกราฟที่จะทดสอบ
    query_types = [ # ประเภทของการ query (target node)
      {:latest, "Latest Tx to Genesis"},
      {:middle, "Middle Tx to Genesis"},
      {:near_genesis, "Near Genesis Tx to Genesis"},
      {:random, "Random Tx to Genesis"}
    ]

    benchmark_jobs =
      for graph_key <- graph_types, {target_key, target_desc} <- query_types, into: %{} do
        job_name = "#{Atom.to_string(graph_key) |> String.capitalize()} - #{target_desc}" # ชื่อ job สำหรับ Benchee
        # ฟังก์ชันที่ Benchee จะรัน โดยรับ {graph_map, targets_map} เป็น input
        job_function = fn {graph_map, targets_map} ->
          specific_graph = Map.get(graph_map, graph_key) # ดึงกราฟที่ต้องการจาก map
          target_node = Map.get(targets_map, target_key) # ดึง target node ที่ต้องการจาก map
          GraphOperations.query_path_to_genesis?(specific_graph, target_node) # เรียกฟังก์ชัน query
        end
        {job_name, job_function}
      end

    # ตรวจสอบว่ามี job ที่จะรันหรือไม่
    if Enum.empty?(benchmark_jobs) do
      Logger.warning("No benchmark jobs generated. Check input parameters (e.g., graph types, query types).") # ไม่มี job ถูกสร้าง
      {:error, :no_benchmark_jobs_generated} # คืนค่า error แบบสอดคล้อง
    else
      Logger.info("Starting graph query benchmarks with #{map_size(benchmark_jobs)} distinct jobs...") # เริ่ม benchmark การ query กราฟ
      if random_seed_query, do: Logger.info("Using random seed for query target selection: #{random_seed_query}") # แจ้งถ้าใช้ seed สำหรับ query

      # --- รัน Benchee ---
      suite_struct =
        Benchee.run(
          benchmark_jobs,
          inputs: benchee_inputs, # input ที่เตรียมไว้
          time: benchee_time, # เวลาที่ใช้ในการวัดผล
          memory_time: benchee_memory_time, # เวลาที่ใช้ในการวัดหน่วยความจำ (ถ้า > 0)
          warmup: benchee_warmup, # เวลา warmup
          formatters: [ # รูปแบบผลลัพธ์
            Benchee.Formatters.Console, # แสดงผลทาง console
            {Benchee.Formatters.HTML, file: benchee_html_output_file} # สร้างรายงาน HTML
          ]
        )

      Logger.info("Benchmark finished. Benchee HTML report saved to #{benchee_html_output_file}") # Benchmark เสร็จสิ้น

      # --- การดึงข้อมูลและการสร้างไฟล์ Vega-Lite JSON ---
      if is_list(suite_struct.scenarios) and not Enum.empty?(suite_struct.scenarios) do
        try do
          # แปลงผลลัพธ์จาก Benchee scenarios ให้อยู่ในรูปแบบ list ของ map สำหรับ Vega-Lite
          vega_data_list =
            Enum.map(suite_struct.scenarios, fn scenario ->
              # ดึง GraphType และ QueryTarget จากชื่อ job
              [graph_type_str, query_target_str] = String.split(scenario.job_name, " - ", parts: 2)

              # ดึงขนาด Transaction จากชื่อ input
              tx_size =
                case Regex.run(~r/Size (\d+) Tx/, scenario.input_name) do
                  [_, size_str] -> String.to_integer(size_str)
                  _ -> Logger.warning("Could not parse size from: #{scenario.input_name}"); 0 # ถ้า parse ไม่ได้ ให้เป็น 0
                end
              # ดึงค่า IPS (Iterations Per Second) อย่างปลอดภัย
              ips = scenario |> Map.get(:run_time_data, %{}) |> Map.get(:statistics, %{}) |> Map.get(:ips, 0.0)

              %{
                "GraphType" => graph_type_str,
                "QueryTarget" => query_target_str,
                "TxCount" => tx_size,
                "IPS" => ips
              }
            end)

          # สร้าง Vega-Lite specification ทั้งหมด
          full_vega_spec_map = create_vega_spec_map_enhanced(vega_data_list)
          # แปลงเป็น JSON string
          json_vega_spec = Jason.encode!(full_vega_spec_map, pretty: true)
          # เขียนลงไฟล์
          File.write!(vega_spec_with_data_file, json_vega_spec)
          Logger.info("Full Vega spec with embedded data saved to #{vega_spec_with_data_file}") # บันทึกไฟล์ Vega-Lite spec แล้ว
          # คืนค่า path ของไฟล์ที่สร้างขึ้น
          {:ok, %{html_report: benchee_html_output_file, vega_spec: vega_spec_with_data_file}}
        rescue
          e -> # กรณีเกิด error ระหว่างการสร้าง Vega spec
            Logger.error("Error during Vega spec creation: #{inspect(e)}")
            {:error, {:vega_spec_generation_failed, inspect(e)}} # คืนค่า error แบบสอดคล้อง
        catch
          type, reason -> # กรณีเกิด error (catch)
            Logger.error("Catch during Vega spec: #{type} - #{inspect(reason)}")
            {:error, {:vega_spec_generation_catch, {type, inspect(reason)}}} # คืนค่า error แบบสอดคล้อง
        end
      else
        Logger.error("No scenarios found in Benchee results for Vega spec generation or scenarios list is empty.") # ไม่พบ scenarios
        {:error, :no_scenarios_for_vega_spec} # คืนค่า error
      end
    end
  end


  # ฟังก์ชันสำหรับสร้าง Vega-Lite specification map ที่ปรับปรุงแล้ว (รองรับ Facet)
  defp create_vega_spec_map_enhanced(data_list) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json", # Schema ของ Vega-Lite
      "title" => "Graph Query Performance: Path to Genesis", # ชื่อกราฟหลัก
      "data" => %{"values" => data_list}, # ข้อมูลที่แปลงแล้วจะถูกใส่ที่นี่
      "facet" => %{ # ใช้ Facet เพื่อสร้างกราฟย่อยตาม QueryTarget
        "column" => %{"field" => "QueryTarget", "type" => "nominal", "title" => "Query Target"}
      },
      "spec" => %{ # Specification สำหรับแต่ละกราฟย่อยใน Facet
        "width" => 250, # ความกว้างของกราฟย่อย
        "height" => 300, # ความสูงของกราฟย่อย
        "mark" => %{"type" => "line", "point" => true}, # ประเภทของกราฟ (เส้นและจุด)
        "encoding" => %{ # การ map ข้อมูลไปยังแกนและสี
          "x" => %{
            "field" => "TxCount", # แกน X คือจำนวน Transaction ทั้งหมด
            "type" => "quantitative",
            "title" => "Total Transactions",
            "sort" => "ascending" # เรียงข้อมูลตามแกน X จากน้อยไปมาก
          },
          "y" => %{
            "field" => "IPS", # แกน Y คือ IPS
            "type" => "quantitative",
            "title" => "Query IPS",
            "axis" => %{"format" => ",.0f"} # รูปแบบการแสดงผลแกน Y (จำนวนเต็ม)
          },
          "color" => %{
            "field" => "GraphType", # สีของเส้นแทนประเภทกราฟ
            "type" => "nominal",
            "title" => "Graph Type"
          },
          "tooltip" => [ # ข้อมูลที่จะแสดงเมื่อ hover บนจุด
            %{"field" => "GraphType", "title" => "Graph"},
            %{"field" => "QueryTarget", "title" => "Target"},
            %{"field" => "TxCount", "title" => "Tx Count"},
            %{"field" => "IPS", "title" => "IPS", "format" => ",.2f"}
          ]
        }
      },
      "resolve" => %{"scale" => %{"y" => "independent"}} # ให้แกน Y ของแต่ละกราฟย่อยมี scale อิสระต่อกัน
    }
  end
end

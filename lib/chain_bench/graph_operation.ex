defmodule ChainBench.GraphOperations do
  @moduledoc """
  Provides functions for creating various graph structures (blockchain, DAG, BlockDAG)
  and querying them. This module is part of the ChainBench application.
  Includes options for deterministic graph generation via seeding.
  โมดูลนี้มีฟังก์ชันสำหรับสร้างโครงสร้างกราฟแบบต่างๆ (blockchain, DAG, BlockDAG)
  และฟังก์ชันสำหรับ query ข้อมูลในกราฟเหล่านั้น เป็นส่วนหนึ่งของแอปพลิเคชัน ChainBench
  รวมถึงตัวเลือกสำหรับการสร้างกราฟแบบกำหนดผลลัพธ์ได้ (deterministic) ผ่านการใช้ seed
  """
  require Logger

  @genesis_tx {:tx, 0} # กำหนดค่าคงที่สำหรับ genesis transaction/vertex

  # === Getter for Genesis Transaction ===
  # ฟังก์ชันสำหรับดึงค่า genesis_tx
  def genesis_tx, do: @genesis_tx

  # === Random Seeding Helper ===
  # ฟังก์ชันช่วยสำหรับการตั้งค่า seed ของตัวสร้างเลขสุ่ม
  defp maybe_seed_random(nil), do: :ok # ถ้าไม่ได้ระบุ seed มา ก็ไม่ต้องทำอะไร
  defp maybe_seed_random(seed) when is_integer(seed) do
    # ตั้งค่า seed สำหรับ :rand module
    # การใช้ tuple สำหรับ seed อาจช่วยเพิ่ม entropy ได้ดีกว่าถ้าให้มาแค่ integer ตัวเดียว
    # :rand.seed(:exsplus, {seed, seed * 2, seed * 3})
    # เพื่อความง่ายและตรงไปตรงมากับการใช้ :rand.uniform ในภายหลัง จะตั้งค่า seed ของ :rand โดยตรง
    # :rand module แบบเก่ามีการจัดการ global state ที่ค่อนข้างซับซ้อน
    # หากต้องการการ seeding แบบ local ที่แข็งแรงกว่า อาจใช้ :rand.ecah/1 หรือ :rand.exs1024/1
    # แล้วส่ง state ไปรอบๆ แต่ในที่นี้จะใช้ global seed เพื่อความง่าย
    :rand.seed(:exs1024, seed) # ใช้อัลกอริทึมที่รู้จักกันดีและ integer seed
    Logger.debug("Random generator seeded with: #{seed}") # บันทึก log ว่ามีการตั้งค่า seed
  end
  defp maybe_seed_random(_invalid_seed), do: Logger.warning("Invalid random seed provided. Using default randomness.") # แจ้งเตือนถ้า seed ไม่ถูกต้อง


  # === Graph Creation Functions ===
  # === ฟังก์ชันสำหรับสร้างกราฟ ===

  @doc """
  Creates a simple linear transaction chain.
  สร้าง chain ของ transaction แบบเส้นตรงอย่างง่าย
  """
  def create_blockchain_graph(num_txs, _opts \\ []) do # เพิ่ม opts เพื่อให้ API สอดคล้องกัน แต่ไม่ได้ใช้ในฟังก์ชันนี้
    graph = :digraph.new([:acyclic]) # สร้างกราฟใหม่แบบไม่มีวงจร (acyclic)
    :digraph.add_vertex(graph, @genesis_tx) # เพิ่ม genesis vertex เข้าไปในกราฟ

    # วนลูปสร้าง transaction ที่เหลือและเชื่อมโยงกับ transaction ก่อนหน้า
    Enum.reduce(1..(num_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index} # transaction ปัจจุบัน
      prev_tx = {:tx, tx_index - 1} # transaction ก่อนหน้า
      :digraph.add_vertex(current_graph, current_tx) # เพิ่ม transaction ปัจจุบันเข้ากราฟ
      :digraph.add_edge(current_graph, current_tx, prev_tx) # เพิ่ม edge จาก transaction ปัจจุบันไปยัง transaction ก่อนหน้า
      current_graph # คืนค่ากราฟที่อัปเดตแล้ว
    end)
  end

  @doc """
  Creates a pure Directed Acyclic Graph (DAG) of transactions.
  Accepts an optional `:random_seed` in opts.
  สร้างกราฟ DAG ของ transaction โดยตรง
  รับ `:random_seed` ที่เป็น optional ใน opts สำหรับการสร้างแบบกำหนดผลลัพธ์ได้
  """
  def create_dag_graph(num_txs, avg_parents, opts \\ []) do
    maybe_seed_random(opts[:random_seed]) # ตั้งค่า seed ถ้ามีการระบุมา

    graph = :digraph.new([:acyclic])
    :digraph.add_vertex(graph, @genesis_tx)
    num_parents_to_select = max(1, avg_parents) # กำหนดจำนวน parent ที่จะเลือก (อย่างน้อย 1)

    # วนลูปสร้าง transaction และเชื่อมโยงกับ parent ที่สุ่มเลือก
    Enum.reduce(1..(num_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index}
      :digraph.add_vertex(current_graph, current_tx)

      max_parent_index = tx_index - 1 # index สูงสุดของ parent ที่เป็นไปได้
      if max_parent_index >= 0 do
        parent_candidates_indices = 0..max_parent_index # ช่วงของ index ของ parent ที่เป็นไปได้
        actual_num_parents = min(num_parents_to_select, max_parent_index + 1) # จำนวน parent ที่จะเลือกจริงๆ

        # Enum.take_random ใช้ global state ของ :rand module
        selected_parent_indices = Enum.take_random(parent_candidates_indices, actual_num_parents) # สุ่มเลือก parent

        # เพิ่ม edge จาก transaction ปัจจุบันไปยัง parent ที่เลือก
        Enum.each(selected_parent_indices, fn parent_index ->
          parent_tx = {:tx, parent_index}
          :digraph.add_edge(current_graph, current_tx, parent_tx)
        end)
      end
      current_graph
    end)
  end

  @doc """
  Creates a BlockDAG where blocks contain internal transaction DAGs.
  Accepts an optional `:random_seed` in opts.
  สร้าง BlockDAG โดยที่แต่ละ block จะมี DAG ของ transaction ภายใน
  รับ `:random_seed` ที่เป็น optional ใน opts สำหรับการสร้างแบบกำหนดผลลัพธ์ได้
  """
  def create_blockdag_internal_tx_dag(num_blocks, tx_per_block, k_internal, k_external, opts \\ []) do
    maybe_seed_random(opts[:random_seed]) # ตั้งค่า seed ถ้ามีการระบุมา

    graph = :digraph.new([:acyclic])
    :digraph.add_vertex(graph, @genesis_tx)
    num_total_txs = num_blocks * tx_per_block # จำนวน transaction ทั้งหมด

    num_internal_parents_to_select = max(0, k_internal) # จำนวน parent ภายใน block ที่จะเลือก
    num_external_parents_to_select = max(1, k_external) # จำนวน parent ภายนอก block ที่จะเลือก (อย่างน้อย 1 เพื่อเชื่อมโยง block)

    # วนลูปสร้าง transaction ทีละตัว
    Enum.reduce(1..(num_total_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index}
      :digraph.add_vertex(current_graph, current_tx)

      current_block_id = div(tx_index, tx_per_block) # ID ของ block ปัจจุบัน
      current_block_start_tx_index = current_block_id * tx_per_block # index เริ่มต้นของ transaction ใน block ปัจจุบัน

      # --- เลือก Internal Parents (ภายใน block เดียวกัน, index < current_tx_index) ---
      internal_candidates_indices =
        if current_block_start_tx_index <= (tx_index - 1) do
          Enum.to_list(current_block_start_tx_index..(tx_index - 1)) # รายการ index ของ internal parent ที่เป็นไปได้
        else
          [] # ไม่มี internal parent ถ้าเป็น transaction แรกใน block
        end

      actual_num_internal = min(num_internal_parents_to_select, Enum.count(internal_candidates_indices)) # จำนวน internal parent ที่จะเลือกจริงๆ
      selected_internal_parents_indices = Enum.take_random(internal_candidates_indices, actual_num_internal) # สุ่มเลือก internal parent

      # --- เลือก External Parents (จาก block ก่อนหน้า) ---
      external_candidates_indices =
        if current_block_start_tx_index - 1 >= 0 do
          Enum.to_list(0..(current_block_start_tx_index - 1)) # รายการ index ของ external parent ที่เป็นไปได้
        else
          [] # ไม่มี external parent ถ้าเป็น block แรก
        end

      actual_num_external = min(num_external_parents_to_select, Enum.count(external_candidates_indices)) # จำนวน external parent ที่จะเลือกจริงๆ
      selected_external_parents_indices = Enum.take_random(external_candidates_indices, actual_num_external) # สุ่มเลือก external parent

      # รวม parent ทั้งหมดและตรวจสอบการเชื่อมโยง
      all_selected_parents_indices = selected_internal_parents_indices ++ selected_external_parents_indices
      final_parent_indices =
        if Enum.empty?(all_selected_parents_indices) and tx_index > 0 do
          # ถ้าไม่มี parent ที่ถูกเลือกเลย และไม่ใช่ genesis transaction ให้เชื่อมโยงกับ transaction ก่อนหน้าเพื่อความต่อเนื่อง
          [max(0, tx_index - 1)] # ป้องกัน index ติดลบ
        else
          MapSet.to_list(MapSet.new(all_selected_parents_indices)) # ใช้ MapSet เพื่อให้ได้ parent ที่ไม่ซ้ำกัน
        end

      # เพิ่ม edge เข้าไปในกราฟ
      Enum.each(final_parent_indices, fn parent_index ->
        parent_tx = {:tx, parent_index}
        if :digraph.vertex(current_graph, parent_tx) != false do # ตรวจสอบว่า parent vertex มีอยู่จริง (ควรจะมีเสมอ)
          :digraph.add_edge(current_graph, current_tx, parent_tx)
        end
      end)

      current_graph
    end)
  end

  # === Query Functions ===
  # === ฟังก์ชันสำหรับ Query กราฟ ===
  @doc """
  Checks if a path exists from the `start_node` to the genesis transaction.
  Returns `true` if a path exists, `false` otherwise.
  ตรวจสอบว่ามีเส้นทางจาก `start_node` ไปยัง genesis transaction หรือไม่
  คืนค่า `true` ถ้ามีเส้นทาง, `false` ถ้าไม่มี
  """
  def query_path_to_genesis?(graph, start_node) do
    # ตรวจสอบว่า start_node ถูกต้องก่อน query
    if start_node == @genesis_tx do
      true # เส้นทางจาก genesis ไป genesis มีอยู่เสมอ (ความยาว 0)
    else
      # ตรวจสอบว่า start_node มีอยู่ในกราฟหรือไม่
      case :digraph.vertex(graph, start_node) do
        false ->
          # Logger.warning("Query start_node #{inspect(start_node)} does not exist in the graph.") # สามารถ uncomment เพื่อ debug
          false # start_node ไม่มีในกราฟ ดังนั้นจึงไม่มีเส้นทาง
        _ ->
          # :digraph.get_path คืนค่า list (เส้นทาง) ถ้าพบ, หรือ `false` ถ้าไม่พบ
          case :digraph.get_path(graph, start_node, @genesis_tx) do
            false -> false # ไม่พบเส้นทาง
            _path -> true  # พบเส้นทาง
          end
      end
    end
  end

  # === Target Node Selection Helpers ===
  # === ฟังก์ชันช่วยสำหรับการเลือก Target Node ===
  @doc "Selects the latest non-genesis transaction vertex."
  # "เลือก vertex ของ transaction ล่าสุดที่ไม่ใช่ genesis"
  def get_latest_tx_vertex(num_total_txs) do
    # num_total_txs รวมถึง genesis (tx 0) ถ้าเรานับแบบ 1-based
    # ถ้า num_txs จาก input หมายถึง "จำนวน transaction *นอกเหนือจาก* genesis"
    # ดังนั้นตัวล่าสุดคือ {:tx, num_txs - 1}
    # สมมติว่า num_total_txs คือจำนวน vertex ทั้งหมดรวม genesis (0 ถึง N-1)
    if num_total_txs <= 1, do: @genesis_tx, else: {:tx, num_total_txs - 1}
  end

  @doc "Selects a transaction vertex from the middle of the graph."
  # "เลือก vertex ของ transaction ที่อยู่ตรงกลางกราฟ"
  def get_middle_tx_vertex(num_total_txs) do
    if num_total_txs <= 1, do: @genesis_tx, else: {:tx, div(num_total_txs - 1, 2)}
  end

  @doc "Selects a transaction vertex near genesis (e.g., tx 1 or tx 2 if available)."
  # "เลือก vertex ของ transaction ที่อยู่ใกล้ genesis (เช่น tx 1 หรือ tx 2 ถ้ามี)"
  def get_near_genesis_tx_vertex(num_total_txs) do
    cond do
      num_total_txs <= 1 -> @genesis_tx
      num_total_txs == 2 -> {:tx, 1} # มีแค่ tx 1 นอกจาก genesis
      true -> {:tx, min(2, num_total_txs - 1)} # เลือก tx 2 ถ้าเป็นไปได้, หรือตัวล่าสุดถ้ามีน้อยกว่า 3 txs
    end
  end

  @doc """
  Selects a random non-genesis transaction vertex.
  Accepts an optional `:random_seed_for_query` in opts for deterministic query target selection.
  เลือก vertex ของ transaction แบบสุ่มที่ไม่ใช่ genesis
  รับ `:random_seed_for_query` ที่เป็น optional ใน opts สำหรับการเลือก target แบบกำหนดผลลัพธ์ได้
  """
  def get_random_tx_vertex(num_total_txs, opts \\ []) do
    # การ seeding แบบ local นี้สำหรับการเลือก query target จะเป็นอิสระจาก seed ของการสร้างกราฟ
    case opts[:random_seed_for_query] do
      nil -> :ok
      seed when is_integer(seed) -> :rand.seed(:exs1024, seed + 1000) # ใช้ seed ที่ offset ไปเล็กน้อย
      _ -> :ok
    end

    if num_total_txs <= 1 do
      @genesis_tx # มีแค่ genesis
    else
      # สุ่มเลือก index จาก 1 ถึง num_total_txs - 1
      # :rand.uniform/1 คืนค่า integer N โดยที่ 1 <= N <= K
      # ดังนั้นถ้า num_total_txs คือ 500, vertices คือ 0..499 เราต้องการเลือกจาก 1..499
      # :rand.uniform(K) จะให้ค่า 1..K ดังนั้น K ควรเป็น num_total_txs - 1
      random_index = :rand.uniform(num_total_txs - 1)
      {:tx, random_index}
    end
  end

end

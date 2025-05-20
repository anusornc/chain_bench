defmodule ChainBench.BlockchainSimulations do
  @moduledoc """
  Contains the core simulation logic for different blockchain consensus mechanisms.
  These functions are designed to be benchmarked by Benchee and are part of the ChainBench application.
  โมดูลนี้เก็บตรรกะหลักสำหรับการจำลองกลไกฉันทามติ (consensus) ของบล็อกเชนแบบต่างๆ
  ฟังก์ชันเหล่านี้ถูกออกแบบมาเพื่อใช้ทดสอบประสิทธิภาพ (benchmark) ด้วย Benchee และเป็นส่วนหนึ่งของแอปพลิเคชัน ChainBench
  """
  require Logger

  # --- Simulated Consensus Implementations ---
  # แต่ละฟังก์ชันรับ tx_count (จำนวนธุรกรรม), node_count (จำนวนโหนด),
  # และ PID ของ Task.Supervisor ที่ใช้จัดการโหนดจำลอง

  @doc """
  จำลอง Proof of Authority (PoA).
  ธุรกรรมทั้งหมดจะถูกส่งไปยัง validator node ตัวเดียว (โหนดแรกในรายการ)
  มีการหน่วงเวลา Process.sleep(1) เพื่อจำลองเวลาที่ใช้ในการสร้างบล็อก
  """
  def simulate_poa(tx_count, node_count, task_supervisor_pid) do
    # เริ่มการทำงานของโหนดจำลองสำหรับรอบการจำลองนี้
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoA_Node_#{i}") end)
        pid
      end)

    # ทำการจำลอง
    if node_count > 0 do
      validator_node = hd(nodes) # แบบง่าย: โหนดแรกเป็น validator
      Enum.each(1..tx_count, fn tx_num ->
        send(validator_node, {:validate, tx_num}) # ส่งธุรกรรมให้ validator ตรวจสอบ
        # Process.sleep(1) จำลองเวลาที่ใช้ในการสร้างบล็อกหรือความหน่วงของเครือข่าย
        # สำหรับ benchmark ที่สมจริงมากขึ้น ควรแทนที่ด้วยการทำงานที่ใช้ CPU จริง
        # หรือรูปแบบการโต้ตอบที่ซับซ้อนกว่านี้
        Process.sleep(1) # จำลองเวลาสร้างบล็อก
      end)
    end

    # สั่งหยุดการทำงานของโหนดจำลองหลังจากรอบการจำลองนี้เสร็จสิ้น
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  @doc """
  จำลอง Practical Byzantine Fault Tolerance (PBFT).
  ธุรกรรมจะถูกส่งไปยังโหนดทั้งหมด และมีการหน่วงเวลาเพื่อจำลอง overhead ของการสื่อสารหลายรอบใน PBFT
  Process.sleep(1 + div(node_count, 5)) เป็นการหน่วงเวลาที่ปรับตามจำนวนโหนด
  """
  def simulate_pbft(tx_count, node_count, task_supervisor_pid) do
    # เริ่มโหนดจำลอง
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PBFT_Node_#{i}") end)
        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        # จำลองการส่งข้อความ (vote) ไปยังโหนดทั้งหมดและรอฉันทามติ
        Enum.each(nodes, &send(&1, {:vote, tx_num}))
        # การหน่วงเวลาแบบง่ายเพื่อจำลอง overhead ของการสื่อสารหลายรอบใน PBFT
        Process.sleep(1 + div(node_count, 5)) # หน่วงเวลาที่ปรับตามจำนวนโหนด; ปรับค่าได้ตามต้องการ
      end)
    end

    # หยุดโหนดจำลอง
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  @doc """
  จำลอง Proof of Work (PoW).
  เลือก miner แบบสุ่มจากรายการโหนดเพื่อ "ขุด" ธุรกรรม
  มีการหน่วงเวลา Process.sleep(5 + Enum.random(1..5)) เพื่อจำลองเวลาที่ใช้ในการขุด PoW ซึ่งควรจะเป็นงานที่ใช้ CPU จริง
  """
  def simulate_pow(tx_count, node_count, task_supervisor_pid) do
    # เริ่มโหนดจำลอง
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoW_Node_#{i}") end)
        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        miner = Enum.random(nodes) # สุ่มเลือก miner
        send(miner, {:mine, tx_num}) # ส่งธุรกรรมให้ miner ขุด
        # จำลองเวลาที่ใช้ในการขุด PoW; ตามหลักการแล้วควรเป็นการคำนวณที่ใช้ CPU
        Process.sleep(5 + Enum.random(1..5)) # หน่วงเวลาแบบสุ่มสำหรับการขุด
      end)
    end

    # หยุดโหนดจำลอง
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  @doc """
  จำลอง Proof of Stake (PoS).
  เลือก validator แบบสุ่ม (แบบง่าย ไม่ได้อิงตาม stake จริง) เพื่อตรวจสอบธุรกรรม
  มีการหน่วงเวลา Process.sleep(2 + Enum.random(0..2)) เพื่อจำลองเวลาที่ใช้ในการตรวจสอบ PoS
  """
  def simulate_pos(tx_count, node_count, task_supervisor_pid) do
    # เริ่มโหนดจำลอง
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("PoS_Node_#{i}") end)
        pid
      end)

    if node_count > 0 do
      Enum.each(1..tx_count, fn tx_num ->
        validator = Enum.random(nodes) # สุ่มเลือก validator (แบบง่าย ไม่ได้อิงตาม stake จริง)
        send(validator, {:validate, tx_num}) # ส่งธุรกรรมให้ validator ตรวจสอบ
        # จำลองเวลาที่ใช้ในการตรวจสอบ PoS
        Process.sleep(2 + Enum.random(0..2)) # หน่วงเวลาแบบสุ่มสำหรับการตรวจสอบ
      end)
    end
    # หยุดโหนดจำลอง
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  @doc """
  จำลอง Delegated Proof of Stake (DPoS).
  เลือก delegates จำนวนหนึ่ง (กำหนดค่าได้ผ่าน Application config) จากโหนดทั้งหมด
  ธุรกรรมจะถูกส่งไปยัง delegates เหล่านี้แบบ round-robin
  มีการหน่วงเวลา Process.sleep(...) ที่กำหนดค่าได้ เพื่อจำลองเวลาสร้างบล็อก
  """
  def simulate_dpos(tx_count, node_count, task_supervisor_pid) do
    # เริ่มโหนดจำลอง
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn -> generic_node("DPoS_Node_#{i}") end)
        pid
      end)

    if node_count > 0 do
      # ใช้ชื่อแอปพลิเคชันจากโปรเจกต์สำหรับดึงค่า config
      delegate_count = min(node_count, Application.get_env(:chain_bench, :dpos_delegates, 5))
      delegates = Enum.take_random(nodes, delegate_count) # เลือก delegates แบบสุ่ม (สมจริงกว่าเดิม)

      if Enum.empty?(delegates) do
        Logger.warning("DPoS simulation: No delegates available for node_count: #{node_count}") # ไม่มี delegates ให้เลือก
      else
        Enum.each(1..tx_count, fn tx_idx ->
          # ส่งธุรกรรมให้ delegates แบบ round-robin
          delegate_index = rem(tx_idx - 1, length(delegates))
          delegate = Enum.at(delegates, delegate_index)
          send(delegate, {:validate, tx_idx})
          Process.sleep(Application.get_env(:chain_bench, :dpos_block_time_ms, 3)) # หน่วงเวลาที่กำหนดค่าได้
        end)
      end
    end
    # หยุดโหนดจำลอง
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  @doc """
  จำลอง Hybrid Proof of Authority (HybridPoA).
  ใช้การเลือก validator แบบ round-robin ผสมกับกลไก fairness
  เพื่อให้แน่ใจว่าไม่มี validator รายใดสร้างบล็อกมากหรือน้อยเกินไป
  มีการหน่วงเวลา Process.sleep(1 + Enum.random(0..1)) เพื่อจำลองเวลาประมวลผลบล็อก
  """
  def simulate_hybrid_poa(tx_count, node_count, task_supervisor_pid) do
    # เริ่มโหนดจำลอง
    nodes =
      Enum.map(1..node_count, fn i ->
        {:ok, pid} =
          Task.Supervisor.start_child(task_supervisor_pid, fn ->
            generic_node("HybridPoA_Node_#{i}")
          end)
        pid
      end)

    if node_count > 0 do
      # เก็บจำนวนบล็อกที่แต่ละโหนดได้สร้าง (เริ่มต้นที่ 0)
      initial_block_counts = Enum.into(nodes, %{}, fn pid -> {pid, 0} end)

      # reduce ใช้จำลองรอบการสร้างบล็อก
      Enum.reduce(1..tx_count, {initial_block_counts, -1}, fn tx_num,
                                                               {current_block_counts,
                                                                current_rr_idx} ->
        # ส่วนของ Round-robin: เลือก validator ตัวถัดไปตามลำดับ
        new_rr_idx = rem(current_rr_idx + 1, node_count)
        candidate_validator_pid = Enum.at(nodes, new_rr_idx)

        # ส่วนของ Fairness: ตรวจสอบว่า validator ที่ถูกเลือกไม่ได้นำหน้า validator อื่นมากเกินไป
        min_blocks_validated =
          if Map.values(current_block_counts) |> Enum.empty?(),
            do: 0,
            else: Enum.min(Map.values(current_block_counts)) # จำนวนบล็อกน้อยที่สุดที่ validator สร้าง

        final_validator_pid =
          # ถ้า validator ที่ถูกเลือก (candidate) สร้างบล็อกมากกว่า (min_blocks_validated + 1)
          # ให้เลือก validator ที่สร้างบล็อกน้อยที่สุดแทน เพื่อให้โหนดที่ตามหลังได้มีโอกาส
          if current_block_counts[candidate_validator_pid] > min_blocks_validated + 1 do
            Enum.min_by(current_block_counts, fn {_pid, count} -> count end, fn ->
              {candidate_validator_pid, 0} # fallback กรณี current_block_counts ว่าง (ไม่ควรเกิด)
            end)
            |> elem(0) # เอา PID ออกมา
          else
            candidate_validator_pid # ถ้าไม่นำหน้ามาก ก็ใช้ candidate เดิม
          end

        send(final_validator_pid, {:validate, tx_num}) # ส่งธุรกรรมให้ validator ที่ถูกเลือก
        Process.sleep(1 + Enum.random(0..1)) # จำลองเวลาประมวลผลบล็อก

        # อัปเดตจำนวนบล็อกที่ validator สร้าง
        updated_block_counts = Map.update!(current_block_counts, final_validator_pid, &(&1 + 1))
        {updated_block_counts, new_rr_idx} # คืนค่า state ใหม่สำหรับรอบถัดไป
      end)
    end

    # หยุดโหนดจำลอง
    Enum.each(nodes, &Task.Supervisor.terminate_child(task_supervisor_pid, &1))
    :ok
  end

  # --- โหนดจำลองแบบทั่วไป (Generic Simulated Node) ---
  # โหนดนี้จะรับ message และทำการ hash ข้อมูลเพื่อจำลองการทำงาน
  # สำหรับ benchmark ที่สมจริงมากขึ้น ควรให้โหนดนี้ทำงานที่เฉพาะเจาะจงกับประเภท message
  # และ consensus algorithm ที่กำลังจำลอง
  def generic_node(node_name) do
    receive do
      {:validate, _tx_num} -> # เมื่อได้รับ message :validate
        :crypto.hash(:sha256, :rand.bytes(32)) # จำลองงานตรวจสอบ (เช่น ตรวจสอบลายเซ็น, ตรรกะธุรกรรม)
        generic_node(node_name) # วนกลับมารอฟัง message ต่อไป

      {:vote, _tx_num} -> # เมื่อได้รับ message :vote
        :crypto.hash(:sha256, :rand.bytes(16)) # จำลองงาน vote หรือประมวลผล message
        generic_node(node_name) # วนกลับมารอฟัง message ต่อไป

      {:mine, _tx_num} -> # เมื่อได้รับ message :mine
        :crypto.hash(:sha256, :rand.bytes(64)) # จำลองงานขุด (สำหรับ PoW จริงๆ จะซับซ้อนกว่านี้)
        generic_node(node_name) # วนกลับมารอฟัง message ต่อไป

      unexpected_msg -> # เมื่อได้รับ message ที่ไม่รู้จัก
        Logger.warning("[#{node_name}] received unexpected message: #{inspect(unexpected_msg)}") # แจ้งเตือน
        generic_node(node_name) # วนกลับมารอฟัง message ต่อไป
    after
      # Timeout เพื่อป้องกันไม่ให้โหนดค้างอยู่ตลอดไปหากไม่ได้รับ message
      # ปรับค่าได้ตามเวลาที่คาดว่าจะใช้ในการจำลอง
      Application.get_env(:chain_bench, :node_receive_timeout, 30_000) ->
        :ok # โหนด process ออกจากการทำงาน
    end
  end
end

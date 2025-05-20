defmodule ChainBench.GraphOperations do
  @moduledoc """
  Provides functions for creating various graph structures (blockchain, DAG, BlockDAG)
  and querying them. This module is part of the ChainBench application.
  Includes options for deterministic graph generation via seeding.
  """
  require Logger

  @genesis_tx {:tx, 0} # Represents the genesis transaction/vertex

  # === Getter for Genesis Transaction ===
  def genesis_tx, do: @genesis_tx

  # === Random Seeding Helper ===
  defp maybe_seed_random(nil), do: :ok # No seed provided, do nothing
  defp maybe_seed_random(seed) when is_integer(seed) do
    # Seed with a tuple for better entropy if just an integer is given
    # :rand.seed(:exsplus, {seed, seed * 2, seed * 3})
    # For simplicity and directness with :rand.uniform later, ensure :rand is seeded.
    # The old :rand module is tricky with global state.
    # For more robust local seeding, one might use :rand.ecah/1 or :rand.exs1024/1
    # and pass the state around. For now, we'll use the global seed for simplicity.
    :rand.seed(:exs1024, seed) # Using a known good algorithm and integer seed
    Logger.debug("Random generator seeded with: #{seed}")
  end
  # Corrected from Logger.warn to Logger.warning
  defp maybe_seed_random(_invalid_seed), do: Logger.warning("Invalid random seed provided. Using default randomness.")


  # === Graph Creation Functions ===

  @doc """
  Creates a simple linear transaction chain.
  """
  def create_blockchain_graph(num_txs, _opts \\ []) do # Opts added for consistent API, not used here
    graph = :digraph.new([:acyclic])
    :digraph.add_vertex(graph, @genesis_tx)

    Enum.reduce(1..(num_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index}
      prev_tx = {:tx, tx_index - 1}
      :digraph.add_vertex(current_graph, current_tx)
      :digraph.add_edge(current_graph, current_tx, prev_tx)
      current_graph
    end)
  end

  @doc """
  Creates a pure Directed Acyclic Graph (DAG) of transactions.
  Accepts an optional `:random_seed` in opts.
  """
  def create_dag_graph(num_txs, avg_parents, opts \\ []) do
    maybe_seed_random(opts[:random_seed])

    graph = :digraph.new([:acyclic])
    :digraph.add_vertex(graph, @genesis_tx)
    num_parents_to_select = max(1, avg_parents)

    Enum.reduce(1..(num_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index}
      :digraph.add_vertex(current_graph, current_tx)

      max_parent_index = tx_index - 1
      if max_parent_index >= 0 do
        parent_candidates_indices = 0..max_parent_index
        actual_num_parents = min(num_parents_to_select, max_parent_index + 1)

        # Enum.take_random uses the :rand module's global state
        selected_parent_indices = Enum.take_random(parent_candidates_indices, actual_num_parents)

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
  """
  def create_blockdag_internal_tx_dag(num_blocks, tx_per_block, k_internal, k_external, opts \\ []) do
    maybe_seed_random(opts[:random_seed])

    graph = :digraph.new([:acyclic])
    :digraph.add_vertex(graph, @genesis_tx)
    num_total_txs = num_blocks * tx_per_block

    num_internal_parents_to_select = max(0, k_internal)
    num_external_parents_to_select = max(1, k_external)

    Enum.reduce(1..(num_total_txs - 1), graph, fn tx_index, current_graph ->
      current_tx = {:tx, tx_index}
      :digraph.add_vertex(current_graph, current_tx)

      current_block_id = div(tx_index, tx_per_block)
      current_block_start_tx_index = current_block_id * tx_per_block

      internal_candidates_indices =
        if current_block_start_tx_index <= (tx_index - 1) do
          Enum.to_list(current_block_start_tx_index..(tx_index - 1))
        else
          []
        end

      actual_num_internal = min(num_internal_parents_to_select, Enum.count(internal_candidates_indices))
      selected_internal_parents_indices = Enum.take_random(internal_candidates_indices, actual_num_internal)

      external_candidates_indices =
        if current_block_start_tx_index - 1 >= 0 do
          Enum.to_list(0..(current_block_start_tx_index - 1))
        else
          []
        end

      actual_num_external = min(num_external_parents_to_select, Enum.count(external_candidates_indices))
      selected_external_parents_indices = Enum.take_random(external_candidates_indices, actual_num_external)

      all_selected_parents_indices = selected_internal_parents_indices ++ selected_external_parents_indices
      final_parent_indices =
        if Enum.empty?(all_selected_parents_indices) and tx_index > 0 do
          [max(0, tx_index - 1)]
        else
          MapSet.to_list(MapSet.new(all_selected_parents_indices))
        end

      Enum.each(final_parent_indices, fn parent_index ->
        parent_tx = {:tx, parent_index}
        if :digraph.vertex(current_graph, parent_tx) != false do
          :digraph.add_edge(current_graph, current_tx, parent_tx)
        end
      end)

      current_graph
    end)
  end

  # === Query Functions ===
  @doc """
  Checks if a path exists from the `start_node` to the genesis transaction.
  Returns `true` if a path exists, `false` otherwise.
  """
  def query_path_to_genesis?(graph, start_node) do
    # Ensure start_node is valid before querying
    if start_node == @genesis_tx do
      true # Path from genesis to genesis always exists (length 0)
    else
      # Check if start_node exists in the graph
      case :digraph.vertex(graph, start_node) do
        false ->
          # Logger.warning("Query start_node #{inspect(start_node)} does not exist in the graph.")
          false # Start node doesn't exist, so no path
        _ ->
          # :digraph.get_path returns a list (the path) if found, or `false` otherwise.
          case :digraph.get_path(graph, start_node, @genesis_tx) do
            false -> false # No path found
            _path -> true  # Path exists
          end
      end
    end

  end

  # === Target Node Selection Helpers ===
  @doc "Selects the latest non-genesis transaction vertex."
  def get_latest_tx_vertex(num_total_txs) do
    # num_total_txs includes the implicit genesis (tx 0) if we consider it as 1-based count
    # If num_txs from input means "number of transactions *in addition to* genesis",
    # then the latest is {:tx, num_txs -1}.
    # Assuming num_total_txs is the count of vertices including genesis (0 to N-1)
    if num_total_txs <= 1, do: @genesis_tx, else: {:tx, num_total_txs - 1}
  end

  @doc "Selects a transaction vertex from the middle of the graph."
  def get_middle_tx_vertex(num_total_txs) do
    if num_total_txs <= 1, do: @genesis_tx, else: {:tx, div(num_total_txs - 1, 2)}
  end

  @doc "Selects a transaction vertex near genesis (e.g., tx 1 or tx 2 if available)."
  def get_near_genesis_tx_vertex(num_total_txs) do
    cond do
      num_total_txs <= 1 -> @genesis_tx
      num_total_txs == 2 -> {:tx, 1} # Only tx 1 exists besides genesis
      true -> {:tx, min(2, num_total_txs - 1)} # Prefer tx 2 if possible, else latest if < 3 txs
    end
  end

  @doc """
  Selects a random non-genesis transaction vertex.
  Accepts an optional `:random_seed_for_query` in opts for deterministic query target selection.
  """
  def get_random_tx_vertex(num_total_txs, opts \\ []) do
    # This local seeding for query target selection is independent of graph generation seed.
    case opts[:random_seed_for_query] do
      nil -> :ok
      seed when is_integer(seed) -> :rand.seed(:exs1024, seed + 1000) # Offset seed
      _ -> :ok
    end

    if num_total_txs <= 1 do
      @genesis_tx # Only genesis exists
    else
      # Randomly select an index from 1 to num_total_txs - 1
      # :rand.uniform/1 returns an integer N such that 1 <= N <= K.
      # So, if num_total_txs is 500, vertices are 0..499. We want to pick from 1..499.
      # :rand.uniform(K) gives 1..K. So K should be num_total_txs - 1.
      random_index = :rand.uniform(num_total_txs - 1)
      {:tx, random_index}
    end
  end

end

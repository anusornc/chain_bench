defmodule ChainBench.BenchmarkCliHelpers do
  @moduledoc """
  Shared CLI argument parsing helpers for benchmark Mix tasks.
  """

  # Parse a comma-separated string of positive integers (e.g., node counts, graph sizes)
  def parse_positive_int_list(arg_string) do
    try do
      arg_string
      |> String.split(",", trim: true)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_integer/1)
      |> Enum.filter(&(&1 > 0))
      |> case do
        [] -> if String.trim(arg_string) != "", do: :error_parsing, else: []
        valid_list -> Enum.uniq(valid_list) |> Enum.sort()
      end
    rescue
      ArgumentError -> :error_parsing
    end
  end

  # Parse a comma-separated string of atoms (e.g., consensus types)
  def parse_atom_list(arg_string) do
    try do
      arg_string
      |> String.split(",", trim: true)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)
      |> case do
        [] -> if String.trim(arg_string) != "", do: :error_parsing, else: []
        valid_list -> Enum.uniq(valid_list)
      end
    rescue
      ArgumentError -> :error_parsing
    end
  end
end

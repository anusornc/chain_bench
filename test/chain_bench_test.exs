defmodule ChainBenchTest do
  use ExUnit.Case
  doctest ChainBench

  test "greets the world" do
    assert ChainBench.hello() == :world
  end
end

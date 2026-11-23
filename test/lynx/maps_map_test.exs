defmodule Lynx.MapsMapTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "maps:map agrees with BEAM for pure callbacks and mixed keys", %{tmp_dir: dir} do
    maps = [%{}, %{1 => :a, 1.0 => :b, :atom => 7}, %{{:x, 1} => [3], [] => :empty}]

    cases =
      maps
      |> Enum.with_index(1)
      |> Enum.map(fn {input, n} ->
        expected = :maps.map(fn key, value -> {key, value} end, input)

        {n, IO.iodata_to_binary(:io_lib.format("~tp", [input])),
         IO.iodata_to_binary(:io_lib.format("~tp", [expected]))}
      end)

    exports = Enum.map_join(cases, ",", fn {n, _, _} -> "c#{n}/0" end)

    laws =
      Enum.map_join(cases, "\n", fn {n, _, _} ->
        "-law #{"#"}{name => {l#{n}, []}, ensures => c#{n}}.\n-proof ~\"\"\"\nrfl\n\"\"\"."
      end)

    functions =
      Enum.map_join(cases, "\n", fn {n, input, expected} ->
        "c#{n}() -> maps:map(fun(K,V) -> {K,V} end, #{input}) =:= #{expected}."
      end)

    path = Path.join(dir, "maps_map_diff.erl")
    File.write!(path, "-module(maps_map_diff).\n-export([#{exports}]).\n#{laws}\n#{functions}\n")

    {:ok, :maps_map_diff, binary} =
      :compile.file(String.to_charlist(path), [:binary, :debug_info])

    reports = Lynx.Laws.verify([binary], cache: false, debug_dir: dir, debug: :olean)

    assert Enum.all?(
             Enum.reject(reports, &String.ends_with?(&1.module, ".laws")),
             &(&1.status == :ok)
           ),
           inspect(reports)

    checks =
      Enum.map_join(cases, ",\n", fn {n, _, _} ->
        "match Lynx.sequential (Lynx.apply Erlang.maps_map_diff.«c#{n}/0» Erlang.program.fun_table 10) with | .ok (.atom \"true\") => true | _ => false"
      end)

    lean = Path.join(dir, "Eval.lean")
    File.write!(lean, "import Erlang.program\n#eval [#{checks}]\n")
    lean_path = dir <> ":" <> Path.expand("Lean/.lake/build/lib/lean")

    {output, 0} =
      System.cmd("lake", ["env", "lean", lean],
        env: [{"LEAN_PATH", lean_path}],
        stderr_to_stdout: true
      )

    assert String.trim(output) == "[true, true, true]"
  end
end

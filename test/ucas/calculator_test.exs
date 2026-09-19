defmodule Ucas.CalculatorTest do
  use ExUnit.Case, async: true

  alias Ucas.Calculator

  describe "parse_grades/1" do
    test "extracts grade tokens" do
      assert Calculator.parse_grades("A*A*A*") == ["A*", "A*", "A*"]
      assert Calculator.parse_grades("AAB") == ["A", "A", "B"]
    end

    test "ignores spaces, commas and case" do
      assert Calculator.parse_grades("a*, a, b") == ["A*", "A", "B"]
    end

    test "rejects anything that is not a grade" do
      assert Calculator.parse_grades("192") == []
      assert Calculator.parse_grades("not grades") == []
      assert Calculator.parse_grades("") == []
    end
  end

  describe "points_for_grades/1" do
    test "sums the standard tariff values" do
      assert Calculator.points_for_grades(["A*", "A", "B"]) == 144
      assert Calculator.points_for_grades(["A", "A", "B"]) == 136
      assert Calculator.points_for_grades(["E"]) == 16
    end
  end

  describe "grades_for_points/2" do
    test "rounds down to the closest combination" do
      assert {:ok, ["C", "C", "C"], 96} = Calculator.grades_for_points(100, 3)
    end

    test "prefers the most balanced combination" do
      # 136 is reachable by AAB (spread 8) and A*AC (spread 24); AAB wins.
      assert {:ok, ["A", "A", "B"], 136} = Calculator.grades_for_points(136, 3)
    end

    test "caps at the maximum possible total" do
      assert {:ok, ["A*", "A*", "A*"], 168} = Calculator.grades_for_points(192, 3)
    end

    test "handles a single A-level" do
      assert {:ok, ["A"], 48} = Calculator.grades_for_points(50, 1)
    end

    test "reports when points are below the minimum" do
      assert Calculator.grades_for_points(10, 3) == :below_minimum
    end
  end
end

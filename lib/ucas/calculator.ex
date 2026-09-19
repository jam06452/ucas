defmodule Ucas.Calculator do
  @moduledoc """
  Converts between A-level grades and UCAS tariff points.

    * `points_for_grades/1` sums the standard tariff value of each grade.
    * `grades_for_points/2` returns the closest grade combination that does not
      exceed the given points, i.e. it rounds down.
  """

  # Standard UCAS tariff points for A-level grades.
  @grade_values %{"A*" => 56, "A" => 48, "B" => 40, "C" => 32, "D" => 24, "E" => 16}
  @grade_order ["A*", "A", "B", "C", "D", "E"]
  @default_subjects 3

  @doc """
  Extracts grade tokens from free text, e.g. `"A*A*A*"` -> `["A*", "A*", "A*"]`.

  Only grade tokens and separators (spaces/commas) are accepted; anything else
  yields an empty list.
  """
  def parse_grades(value) when is_binary(value) do
    normalized = value |> String.upcase() |> String.replace(~r/[\s,]/, "")

    if normalized != "" and Regex.match?(~r/^(A\*|[A-E])+$/, normalized) do
      ~r/A\*|[A-E]/ |> Regex.scan(normalized) |> List.flatten()
    else
      []
    end
  end

  def parse_grades(_value), do: []

  @doc "Total UCAS tariff points for a list of grades."
  def points_for_grades(grades) do
    Enum.sum(Enum.map(grades, &Map.fetch!(@grade_values, &1)))
  end

  @doc "The default number of A-levels assumed when converting points to grades."
  def default_subjects, do: @default_subjects

  @doc """
  Returns the closest grade combination (for `count` A-levels) whose total does
  not exceed `points`, or `:below_minimum` when no combination fits.

  Among combinations with the same total, the most balanced one wins (smallest
  spread between the best and worst grade), which matches how a student would
  naturally distribute a points target across subjects.
  """
  def grades_for_points(points, count) when is_integer(points) and points >= 0 do
    best =
      @grade_order
      |> combinations(count)
      |> Enum.map(&{&1, points_for_grades(&1)})
      |> Enum.filter(fn {_combo, total} -> total <= points end)
      |> Enum.max_by(
        fn {combo, total} -> {total, -spread(combo), min_grade_value(combo)} end,
        fn -> nil end
      )

    case best do
      nil -> :below_minimum
      {combo, total} -> {:ok, combo, total}
    end
  end

  def grades_for_points(_points, _count), do: :below_minimum

  @doc "Parses a points string, returning `{:ok, integer}` or `:error`."
  def parse_points(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {points, ""} when points >= 0 -> {:ok, points}
      _ -> :error
    end
  end

  def parse_points(_raw), do: :error

  # All ordered combinations of `count` grades drawn from `options`.
  defp combinations(_options, 0), do: [[]]

  defp combinations(options, count) do
    for option <- options, rest <- combinations(options, count - 1), do: [option | rest]
  end

  defp spread(combo) do
    values = Enum.map(combo, &Map.fetch!(@grade_values, &1))
    Enum.max(values) - Enum.min(values)
  end

  defp min_grade_value(combo) do
    combo |> Enum.map(&Map.fetch!(@grade_values, &1)) |> Enum.min()
  end
end

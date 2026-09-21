defmodule Ucas.Search.QueryTest do
  use ExUnit.Case, async: true

  alias Ucas.Search.Query

  describe "to_params/1" do
    test "searches the weighted fields with typo tolerance and prefix matching" do
      params = Query.new(q: "Computer Science") |> Query.to_params()

      assert params[:q] == "Computer Science"
      assert params[:query_by] == "course_name,provider_name,course_code,entry_requirements"
      assert params[:query_by_weights] == "4,3,2,1"
      assert params[:num_typos] == "2,2,0,0"
      assert params[:prefix] == "true"
    end

    test "facets on the required attributes" do
      params = Query.new() |> Query.to_params()

      assert params[:facet_by] ==
               "provider_name,qualification_name,study_mode_name,academic_year,campus_name"
    end

    test "defaults to relevance then course name, 20 per page" do
      params = Query.new() |> Query.to_params()

      assert params[:sort_by] == "_text_match:desc,course_name:asc"
      assert params[:page] == 1
      assert params[:per_page] == 20
    end

    test "a blank query matches everything" do
      assert Query.new(q: "") |> Query.to_params() |> Keyword.fetch!(:q) == "*"
      assert Query.new() |> Query.to_params() |> Keyword.fetch!(:q) == "*"
    end

    test "omits filter_by when no filters are selected" do
      refute Keyword.has_key?(Query.new() |> Query.to_params(), :filter_by)
    end

    test "honours custom pagination" do
      params = Query.new(page: 3, per_page: 50) |> Query.to_params()

      assert params[:page] == 3
      assert params[:per_page] == 50
    end
  end

  describe "build_filter_by/1" do
    test "ORs values within a facet and ANDs across facets" do
      filters = %{
        "study_mode_name" => ["Full-time"],
        "qualification_name" => ["BSc", "MSc"]
      }

      assert Query.build_filter_by(filters) ==
               "qualification_name:=[`BSc`, `MSc`] && study_mode_name:=[`Full-time`]"
    end

    test "wraps values containing spaces in backticks" do
      filters = %{"provider_name" => ["University of Oxford"]}

      assert Query.build_filter_by(filters) == "provider_name:=[`University of Oxford`]"
    end

    test "accepts MapSets" do
      filters = %{"academic_year" => MapSet.new(["2025/26", "2026/27"])}

      assert Query.build_filter_by(filters) == "academic_year:=[`2025/26`, `2026/27`]"
    end

    test "ignores unknown fields and empty selections" do
      filters = %{"unknown" => ["x"], "provider_name" => [], "campus_name" => nil}

      assert Query.build_filter_by(filters) == nil
    end

    test "escapes backticks in values" do
      assert Query.escape_value("a`b") == "`a\\`b`"
    end

    test "builds an overlap filter for a tariff range" do
      filters = %{"tariff_points" => %{min: 96, max: 112}}

      assert Query.build_filter_by(filters) ==
               "tariff_points_min:<=112 && tariff_points_max:>=96"
    end

    test "combines a tariff range with facet filters" do
      filters = %{
        "study_mode_name" => ["Full-time"],
        "tariff_points" => %{min: 96, max: 112}
      }

      assert Query.build_filter_by(filters) ==
               "study_mode_name:=[`Full-time`] && tariff_points_min:<=112 && tariff_points_max:>=96"
    end

    test "ignores an incomplete tariff range" do
      assert Query.build_filter_by(%{"tariff_points" => %{min: 96}}) == nil
      assert Query.build_filter_by(%{"tariff_points" => nil}) == nil
    end

    test "builds an overlap filter for a duration range" do
      filters = %{"duration_months" => %{min: 36, max: 60}}

      assert Query.build_filter_by(filters) ==
               "duration_months_min:<=60 && duration_months_max:>=36"
    end

    test "combines a duration range with facet and tariff filters" do
      filters = %{
        "study_mode_name" => ["Full-time"],
        "tariff_points" => %{min: 96, max: 112},
        "duration_months" => %{min: 36, max: 60}
      }

      assert Query.build_filter_by(filters) ==
               "study_mode_name:=[`Full-time`] && tariff_points_min:<=112 && tariff_points_max:>=96 && duration_months_min:<=60 && duration_months_max:>=36"
    end

    test "ignores an incomplete duration range" do
      assert Query.build_filter_by(%{"duration_months" => %{max: 60}}) == nil
      assert Query.build_filter_by(%{"duration_months" => nil}) == nil
    end
  end

  describe "filter_by_excluding/2" do
    test "drops only the given facet's selection" do
      query =
        Query.new(
          filters: %{
            "provider_name" => ["University of Oxford"],
            "study_mode_name" => ["Full-time"]
          }
        )

      assert Query.filter_by_excluding(query, "provider_name") ==
               "study_mode_name:=[`Full-time`]"

      assert Query.filter_by_excluding(query, "study_mode_name") ==
               "provider_name:=[`University of Oxford`]"
    end

    test "returns nil when nothing else is selected" do
      query = Query.new(filters: %{"provider_name" => ["University of Oxford"]})
      assert Query.filter_by_excluding(query, "provider_name") == nil
    end

    test "keeps the tariff range when excluding a facet" do
      query =
        Query.new(
          filters: %{
            "provider_name" => ["University of Oxford"],
            "tariff_points" => %{min: 96, max: 112}
          }
        )

      assert Query.filter_by_excluding(query, "provider_name") ==
               "tariff_points_min:<=112 && tariff_points_max:>=96"
    end
  end
end

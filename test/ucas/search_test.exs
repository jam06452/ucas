defmodule Ucas.SearchTest do
  use ExUnit.Case, async: false

  alias Ucas.Search
  alias Ucas.Search.FakeTypesenseClient

  setup do
    FakeTypesenseClient.reset()
    :ok
  end

  test "returns hits and facet counts" do
    FakeTypesenseClient.set_search_response(%{
      hits: [%{"id" => "1", "course_name" => "Computer Science"}],
      facets: %{"provider_name" => [{"University of Oxford", 2}]},
      found: 1
    })

    assert {:ok, result} = Search.search(%{q: "computer"})

    assert result.found == 1
    assert result.hits == [%{"id" => "1", "course_name" => "Computer Science"}]
    assert result.facets["provider_name"] == [%{value: "University of Oxford", count: 2}]
    assert result.per_page == 20
  end

  test "sends the weighted query, filters and pagination to Typesense" do
    FakeTypesenseClient.set_search_response(%{found: 0})

    Search.search(%{
      q: "law",
      filters: %{"study_mode_name" => ["Full-time"]},
      page: 2
    })

    query = FakeTypesenseClient.last_query()

    assert query[:q] == "law"
    assert query[:query_by] == "course_name,provider_name,course_code,entry_requirements"
    assert query[:query_by_weights] == "4,3,2,1"
    assert query[:filter_by] == "study_mode_name:=[`Full-time`]"
    assert query[:sort_by] == "_text_match:desc,course_name:asc"
    assert query[:page] == 2
    assert query[:per_page] == 20
  end

  test "computes each facet's counts without that facet's own filter" do
    FakeTypesenseClient.set_search_response(%{found: 0})

    Search.search(%{
      filters: %{"provider_name" => ["University of Oxford"], "study_mode_name" => ["Full-time"]}
    })

    searches = FakeTypesenseClient.last_searches()

    provider = Enum.find(searches, &(&1[:facet_by] == "provider_name"))
    assert provider[:filter_by] == "study_mode_name:=[`Full-time`]"

    study_mode = Enum.find(searches, &(&1[:facet_by] == "study_mode_name"))
    assert study_mode[:filter_by] == "provider_name:=[`University of Oxford`]"

    # The main query keeps every filter.
    assert FakeTypesenseClient.last_query()[:filter_by] ==
             "provider_name:=[`University of Oxford`] && study_mode_name:=[`Full-time`]"
  end

  test "reindex upserts documents into the collection" do
    assert {:ok, 0} = Search.reindex([%{id: "1", course_name: "Computer Science"}])
    assert :import_documents in FakeTypesenseClient.calls()
  end

  test "reindex with no documents is a no-op" do
    assert {:ok, 0} = Search.reindex([])
    refute :import_documents in FakeTypesenseClient.calls()
  end
end

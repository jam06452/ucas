defmodule Ucas.Search.FakeTypesenseClient do
  @moduledoc """
  In-memory stand-in for the Typesense HTTP client, wired up in
  `config/test.exs` via `config :open_api_typesense, client: __MODULE__`.

  Tests seed the search response with `set_search_response/1` and the
  collection state with `set_collection/1`, then inspect the calls Typesense
  received with `calls/0` and the last search query with `last_query/0`.
  """

  use GenServer

  alias OpenApiTypesense.ApiResponse
  alias OpenApiTypesense.CollectionResponse
  alias OpenApiTypesense.FacetCounts
  alias OpenApiTypesense.FacetCountsCounts
  alias OpenApiTypesense.MultiSearchResult
  alias OpenApiTypesense.MultiSearchResultItem
  alias OpenApiTypesense.SearchRequestParams
  alias OpenApiTypesense.SearchResult
  alias OpenApiTypesense.SearchResultHit

  @name __MODULE__

  @empty %{hits: [], facets: %{}, found: 0}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: @name)

  @doc "Seeds the response returned for the next search request."
  def set_search_response(response), do: GenServer.call(@name, {:set_response, response})

  @doc """
  Sets the collection state: an integer document count, or `:missing` to
  simulate a collection that has not been created yet.
  """
  def set_collection(state), do: GenServer.call(@name, {:set_collection, state})

  @doc """
  Makes the next `create_collection` calls fail with the given message, so
  callers can exercise how a duplicate-collection error is handled. Pass `nil`
  to stop failing.
  """
  def fail_create_collection(message),
    do: GenServer.call(@name, {:fail_create_collection, message})

  @doc "Returns the query params of the most recent search request."
  def last_query, do: GenServer.call(@name, :last_query)

  @doc "Returns the searches sent in the most recent multi_search request."
  def last_searches, do: GenServer.call(@name, :last_searches)

  @doc "Returns the Typesense operations received, oldest first."
  def calls, do: GenServer.call(@name, :calls)

  @doc "Clears all seeded state and recorded calls."
  def reset, do: GenServer.call(@name, :reset)

  # `OpenApiTypesense.Client` callback used when a `:client` is configured.
  def request(_conn, %{call: {_module, :search_collection}} = params) do
    GenServer.call(@name, {:search, params.query})
  end

  def request(_conn, %{call: {_module, :multi_search}} = params) do
    GenServer.call(@name, {:multi_search, params.body})
  end

  def request(_conn, %{call: {_module, operation}})
      when operation in [
             :get_collection,
             :create_collection,
             :delete_collection,
             :import_documents
           ] do
    GenServer.call(@name, {:operation, operation})
  end

  def request(_conn, _params), do: {:ok, %{}}

  @impl GenServer
  def init(_opts),
    do: {:ok, new_state()}

  defp new_state do
    %{
      response: @empty,
      last_query: nil,
      last_searches: [],
      collection: :missing,
      create_error: nil,
      calls: []
    }
  end

  @impl GenServer
  def handle_call({:set_response, response}, _from, state) do
    {:reply, :ok, %{state | response: response}}
  end

  def handle_call({:set_collection, collection}, _from, state) do
    {:reply, :ok, %{state | collection: collection}}
  end

  def handle_call({:fail_create_collection, message}, _from, state) do
    {:reply, :ok, %{state | create_error: message}}
  end

  def handle_call(:last_query, _from, state), do: {:reply, state.last_query, state}

  def handle_call(:last_searches, _from, state), do: {:reply, state.last_searches, state}

  def handle_call(:calls, _from, state), do: {:reply, Enum.reverse(state.calls), state}

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, new_state()}
  end

  def handle_call({:search, query}, _from, state) do
    result = to_search_result(state.response, query)
    {:reply, {:ok, result}, record(%{state | last_query: query}, :search_collection)}
  end

  def handle_call({:multi_search, body}, _from, state) do
    searches = body.searches
    results = Enum.map(searches, &to_result_item(state.response, &1))

    {:reply, {:ok, %MultiSearchResult{results: results}},
     %{state | last_query: main_query(searches), last_searches: searches}}
  end

  def handle_call({:operation, :get_collection}, _from, state) do
    reply =
      case state.collection do
        :missing -> {:error, %ApiResponse{message: "Not found"}}
        count -> {:ok, %CollectionResponse{name: "course_study_options", num_documents: count}}
      end

    {:reply, reply, record(state, :get_collection)}
  end

  def handle_call({:operation, :create_collection}, _from, state) do
    state = record(state, :create_collection)

    case state.create_error do
      nil ->
        reply = {:ok, %CollectionResponse{name: "course_study_options", num_documents: 0}}
        {:reply, reply, %{state | collection: 0}}

      message ->
        {:reply, {:error, %ApiResponse{message: message}}, state}
    end
  end

  def handle_call({:operation, :delete_collection}, _from, state) do
    {:reply, {:ok, %{}}, %{record(state, :delete_collection) | collection: :missing}}
  end

  def handle_call({:operation, :import_documents}, _from, state) do
    {:reply, {:ok, []}, record(state, :import_documents)}
  end

  defp record(state, operation), do: %{state | calls: [operation | state.calls]}

  # The main query is the one without a `facet_by`; the rest are per-facet
  # queries used for disjunctive counts.
  defp main_query(searches), do: Enum.find(searches, &is_nil(Map.get(&1, :facet_by)))

  defp to_result_item(response, %{facet_by: field} = _search) when is_binary(field) do
    counts = response |> Map.get(:facets, %{}) |> Map.get(field, [])
    %MultiSearchResultItem{facet_counts: [to_facet_counts({field, counts})]}
  end

  defp to_result_item(response, search) do
    %MultiSearchResultItem{
      found: Map.get(response, :found, 0),
      page: Map.get(search, :page, 1),
      hits: Enum.map(Map.get(response, :hits, []), &%SearchResultHit{document: &1}),
      request_params: %SearchRequestParams{
        collection_name: "course_study_options",
        per_page: Map.get(search, :per_page, 20),
        q: Map.get(search, :q, "*")
      }
    }
  end

  defp to_search_result(response, query) do
    %SearchResult{
      found: Map.get(response, :found, 0),
      page: Keyword.get(query, :page, 1),
      hits: Enum.map(Map.get(response, :hits, []), &%SearchResultHit{document: &1}),
      facet_counts: Enum.map(Map.get(response, :facets, %{}), &to_facet_counts/1),
      request_params: %SearchRequestParams{
        collection_name: "course_study_options",
        per_page: Keyword.get(query, :per_page, 20),
        q: Keyword.get(query, :q, "*")
      }
    }
  end

  defp to_facet_counts({field, values}) do
    %FacetCounts{
      field_name: field,
      counts:
        Enum.map(values, fn {value, count} ->
          %FacetCountsCounts{value: value, count: count}
        end)
    }
  end
end

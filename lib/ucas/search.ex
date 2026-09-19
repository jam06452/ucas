defmodule Ucas.Search do
  @moduledoc """
  Full-text search and faceted filtering over the flattened
  `course_study_options` Typesense collection.

  ## Example

      iex> Ucas.Search.search(%{q: "computer science", filters: %{"study_mode_name" => ["Full-time"]}})
      {:ok, %{hits: [...], facets: %{"provider_name" => [...]}, found: 42, page: 1, per_page: 20}}

  Use `reindex/0` (or `mix ucas.search.reindex`) to (re)build the collection
  from Postgres.
  """

  alias Ucas.Search.{Document, Query}

  @type facet_value :: %{value: String.t(), count: non_neg_integer()}

  @type result :: %{
          hits: [map()],
          facets: %{String.t() => [facet_value()]},
          found: non_neg_integer(),
          page: pos_integer(),
          per_page: pos_integer()
        }

  @doc """
  Runs a search and returns hits plus facet counts.

  Uses a Typesense `multi_search`: one query for the hits and one per facet
  field with that field's own filter removed. This keeps facet counts
  *disjunctive*, so selecting a provider still shows the other providers and
  multiple values can be combined within a facet.
  """
  @spec search(Query.t() | map() | keyword()) :: {:ok, result()} | {:error, String.t()}
  def search(%Query{} = query) do
    case do_multi_search(query) do
      {:ok, %{results: [main | _rest]} = result} ->
        case Map.get(main, :error) do
          error when is_binary(error) -> {:error, error}
          _ -> {:ok, normalize(result, query)}
        end

      {:error, reason} ->
        {:error, error_message(reason)}
    end
  end

  def search(attrs), do: search(Query.new(attrs))

  # Wrapped so the error type is `term()`: `ExTypesense.multi_search/1`'s spec
  # only mentions `OpenApiTypesense.ApiResponse`, but the HTTP client can also
  # return a plain string on transport failures.
  @spec do_multi_search(Query.t()) :: {:ok, map()} | {:error, term()}
  defp do_multi_search(%Query{} = query) do
    searches = [main_search(query) | Enum.map(Query.facets(), &facet_search(query, &1))]
    ExTypesense.multi_search(searches)
  end

  defp main_search(query) do
    query
    |> Query.base_params()
    |> Keyword.merge(
      filter_by: Query.filter_by(query),
      page: query.page,
      per_page: query.per_page
    )
    |> reject_empty()
    |> search_map()
  end

  defp facet_search(query, field) do
    query
    |> Query.base_params()
    |> Keyword.merge(
      filter_by: Query.filter_by_excluding(query, field),
      facet_by: field,
      max_facet_values: query.max_facet_values,
      per_page: 0
    )
    |> reject_empty()
    |> search_map()
  end

  defp search_map(params) do
    params |> Map.new() |> Map.put(:collection, Document.collection_name())
  end

  defp reject_empty(params), do: Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)

  @doc "Creates the Typesense collection if it does not already exist."
  @spec create_collection() :: {:ok, term()} | {:error, term()}
  def create_collection, do: ExTypesense.create_collection(Document)

  @doc """
  Drops and recreates the collection.

  Useful before a full reindex so schema changes and removed documents are
  picked up cleanly.
  """
  @spec recreate_collection() :: {:ok, term()} | {:error, term()}
  def recreate_collection do
    _ = ExTypesense.drop_collection(Document.collection_name())
    create_collection()
  end

  @doc """
  Upserts every study option from Postgres into the Typesense collection.

  Returns the number of successfully indexed documents. Accepts an explicit
  list of documents for callers that already have them (and for tests).
  """
  @spec reindex() :: {:ok, non_neg_integer()} | {:error, term()}
  def reindex, do: reindex(Document.all())

  @spec reindex([map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def reindex([]), do: {:ok, 0}

  def reindex(documents) when is_list(documents) do
    case ExTypesense.import_documents(Document.collection_name(), documents, action: "upsert") do
      {:ok, results} -> {:ok, Enum.count(results, &(&1["success"] == true))}
      {:error, _reason} = error -> error
    end
  end

  # The multi_search result is `[main | facet_results]`: hits come from the
  # main query, facet counts from the per-facet queries.
  defp normalize(%{results: [main | facet_results]}, query) do
    %{
      hits: Enum.map(main.hits, &stringify_keys(&1.document)),
      facets: normalize_facets(facet_results),
      found: main.found,
      page: main.page || query.page,
      per_page: request_per_page(main.request_params)
    }
  end

  # Typesense decodes documents with atom keys; normalise to string keys so
  # callers (and templates) can use `document["field"]`, which also returns
  # `nil` for the optional fields that may be absent.
  defp stringify_keys(nil), do: %{}

  defp stringify_keys(document) do
    Map.new(document, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_facets(facet_results) do
    facet_results
    |> Enum.flat_map(fn result ->
      case result.facet_counts do
        [facet | _rest] -> [{facet.field_name, normalize_counts(facet.counts)}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_counts(counts) do
    Enum.map(counts, fn count -> %{value: count.value, count: count.count} end)
  end

  defp request_per_page(params) do
    per_page = if is_map(params), do: Map.get(params, "per_page") || Map.get(params, :per_page)
    if is_integer(per_page), do: per_page, else: Query.default_per_page()
  end

  @spec error_message(term()) :: String.t()
  defp error_message(reason) do
    if is_binary(reason) do
      reason
    else
      Map.get(reason, :message, "Search is temporarily unavailable. Please try again.")
    end
  end
end

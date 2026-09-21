defmodule Ucas.Search.Query do
  @moduledoc """
  Search and filter parameters for the Typesense `course_study_options`
  collection.

  Encapsulates the multi-field weighting, typo tolerance, prefix matching,
  faceting and pagination rules so callers can build a Typesense payload
  without knowing the details.

  ## Field weighting

  `course_name` is searched with the highest priority, followed by
  `provider_name`, `course_code` and finally `entry_requirements`:

      query_by: "course_name,provider_name,course_code,entry_requirements"
      query_by_weights: "4,3,2,1"

  Typo tolerance is enabled for `course_name` and `provider_name` (two typos
  each) and disabled for the code and requirements fields, while prefix
  matching stays on to support search-as-you-type.
  """

  @query_fields ~w(course_name provider_name course_code entry_requirements)
  @query_weights "4,3,2,1"
  @num_typos "2,2,0,0"
  @facets ~w(provider_name qualification_name study_mode_name academic_year campus_name)
  @tariff_field "tariff_points"
  @duration_field "duration_months"
  @default_per_page 20
  @default_sort "_text_match:desc,course_name:asc"

  defstruct q: "",
            filters: %{},
            page: 1,
            per_page: @default_per_page,
            sort_by: @default_sort,
            max_facet_values: 50

  @type t :: %__MODULE__{
          q: String.t(),
          filters: %{optional(String.t()) => Enumerable.t()},
          page: pos_integer(),
          per_page: pos_integer(),
          sort_by: String.t(),
          max_facet_values: pos_integer()
        }

  @doc "Facet fields exposed to the UI, in display order."
  @spec facets() :: [String.t()]
  def facets, do: @facets

  @doc "Fields searched, in priority order."
  @spec query_fields() :: [String.t()]
  def query_fields, do: @query_fields

  @doc "Default number of records per page."
  @spec default_per_page() :: pos_integer()
  def default_per_page, do: @default_per_page

  @doc "Builds a query from a map or keyword list of attributes."
  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}), do: struct(__MODULE__, attrs)

  @doc """
  Converts the query into Typesense search parameters (a keyword list).

  A blank `q` becomes `*` (match all) and an empty `filter_by` is omitted so
  the payload stays valid for Typesense.
  """
  @spec to_params(t()) :: keyword()
  def to_params(%__MODULE__{} = query) do
    query
    |> base_params()
    |> Keyword.merge(
      facet_by: Enum.join(@facets, ","),
      max_facet_values: query.max_facet_values,
      filter_by: filter_by(query),
      page: query.page,
      per_page: query.per_page
    )
    |> reject_empty()
  end

  @doc """
  Search parameters shared by the main and per-facet queries: the weighted
  fields, typo tolerance, prefix matching and sort order.
  """
  @spec base_params(t()) :: keyword()
  def base_params(%__MODULE__{} = query) do
    [
      q: normalize_q(query.q),
      query_by: Enum.join(@query_fields, ","),
      query_by_weights: @query_weights,
      num_typos: @num_typos,
      prefix: "true",
      sort_by: query.sort_by
    ]
  end

  @doc "Filter expression for all selected facets."
  @spec filter_by(t()) :: String.t() | nil
  def filter_by(%__MODULE__{filters: filters}), do: build_filter_by(filters)

  @doc """
  Filter expression excluding one facet field.

  Used to compute disjunctive facet counts: a facet's own selection is left
  out of its counts so the other values remain visible and selectable.
  """
  @spec filter_by_excluding(t(), String.t()) :: String.t() | nil
  def filter_by_excluding(%__MODULE__{filters: filters}, field) do
    filters |> Map.delete(field) |> build_filter_by()
  end

  @doc """
  Builds the Typesense `filter_by` expression from facet selections.

  Multiple values for one facet are OR-ed together, while different facets are
  AND-ed with `&&` (Typesense does not accept the `AND` keyword), e.g.:

      study_mode_name:=[`Full-time`] && qualification_name:=[`BSc`, `MSc`]

  Values are wrapped in backticks so names containing spaces or reserved
  characters are matched literally.

  A numeric tariff range may be supplied under the `#{@tariff_field}` key as
  `%{min: integer, max: integer}`. It matches documents whose own tariff range
  overlaps the selection, e.g. `%{min: 96, max: 112}` matches a course asking
  for "104 - 120 UCAS Tariff points".

  A course duration range, in months, may be supplied under the
  `#{@duration_field}` key in the same shape and matches by overlap too.
  """
  @spec build_filter_by(map()) :: String.t() | nil
  def build_filter_by(filters) when is_map(filters) do
    facet_clauses =
      filters
      |> Enum.filter(fn {field, values} -> field in @facets and present?(values) end)
      |> Enum.sort_by(fn {field, _values} -> field end)
      |> Enum.map(fn {field, values} ->
        "#{field}:=[#{Enum.map_join(values, ", ", &escape_value/1)}]"
      end)

    range_clauses =
      tariff_clauses(Map.get(filters, @tariff_field)) ++
        duration_clauses(Map.get(filters, @duration_field))

    case facet_clauses ++ range_clauses do
      [] -> nil
      clauses -> Enum.join(clauses, " && ")
    end
  end

  defp tariff_clauses(%{min: min, max: max}) when is_integer(min) and is_integer(max) do
    ["tariff_points_min:<=#{max}", "tariff_points_max:>=#{min}"]
  end

  defp tariff_clauses(_range), do: []

  defp duration_clauses(%{min: min, max: max}) when is_integer(min) and is_integer(max) do
    ["duration_months_min:<=#{max}", "duration_months_max:>=#{min}"]
  end

  defp duration_clauses(_range), do: []

  @doc false
  @spec escape_value(term()) :: String.t()
  def escape_value(value) when is_binary(value) do
    "`" <> String.replace(value, "`", "\\`") <> "`"
  end

  def escape_value(value), do: escape_value(to_string(value))

  defp present?(values), do: values not in [nil, []] and Enum.count(values) > 0

  defp reject_empty(params), do: Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)

  defp normalize_q(q) when q in [nil, ""], do: "*"
  defp normalize_q(q), do: q
end

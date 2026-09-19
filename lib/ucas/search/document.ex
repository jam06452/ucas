defmodule Ucas.Search.Document do
  @moduledoc """
  Typesense collection schema and Postgres flattening for the
  `course_study_options` read model.

  Each document is a single course study option, denormalised with its course,
  provider, qualification, study mode, academic year and campus so it can be
  searched and faceted in one Typesense query.

  The collection is defined from the normalised tables created by
  `Ucas.Repo.Migrations.CreateTables`; `all/0` joins them into the flat shape
  Typesense indexes.
  """

  @behaviour ExTypesense

  import Ecto.Query

  alias Ucas.Repo

  @collection "course_study_options"

  # Matches the tariff range embedded in `entry_requirements`, e.g.
  # "96 - 112 UCAS Tariff points".
  @tariff_regex ~r/(\d+)\s*-\s*(\d+)\s*UCAS Tariff points/i

  @doc "Typesense collection name."
  @spec collection_name() :: String.t()
  def collection_name, do: @collection

  @impl ExTypesense
  def get_field_types do
    %{
      name: @collection,
      fields: [
        # Searchable, weighted fields.
        %{name: "course_name", type: "string", sort: true},
        %{name: "provider_name", type: "string", facet: true},
        %{name: "course_code", type: "string", optional: true},
        %{name: "entry_requirements", type: "string", optional: true},
        # Facet fields.
        %{name: "qualification_name", type: "string", facet: true},
        %{name: "study_mode_name", type: "string", facet: true},
        %{name: "academic_year", type: "string", facet: true},
        %{name: "campus_name", type: "string", facet: true, optional: true},
        # Numeric range filter, parsed from `entry_requirements`.
        %{name: "tariff_points_min", type: "int32", optional: true},
        %{name: "tariff_points_max", type: "int32", optional: true},
        # Display-only fields.
        %{name: "duration", type: "string", optional: true},
        %{name: "start_date", type: "string", optional: true},
        %{name: "course_id", type: "string"},
        %{name: "provider_id", type: "string"}
      ]
    }
  end

  @doc "Returns every study option flattened into a Typesense document."
  @spec all() :: [map()]
  def all do
    flatten_query()
    |> Repo.all()
    |> Enum.map(&put_tariff/1)
    |> Enum.map(&drop_nils/1)
  end

  defp flatten_query do
    from(so in "course_study_option",
      join: c in "course",
      on: c.id == so.course_id,
      join: p in "provider",
      on: p.id == c.provider_id,
      join: q in "qualification",
      on: q.id == so.qualification_id,
      join: sm in "study_mode",
      on: sm.id == so.study_mode_id,
      join: ay in "academic_year",
      on: ay.id == so.academic_year_id,
      left_join: campus in "campus",
      on: campus.id == so.campus_id,
      select: %{
        id: fragment("?::text", so.id),
        course_id: fragment("?::text", c.id),
        course_name: c.name,
        course_code: c.code,
        provider_id: fragment("?::text", p.id),
        provider_name: p.name,
        qualification_name: q.name,
        study_mode_name: sm.name,
        academic_year: ay.year,
        campus_name: campus.name,
        duration: so.duration,
        start_date: so.start_date,
        entry_requirements: so.entry_requirements
      }
    )
  end

  # Extracts the numeric tariff range from the free-text entry requirements so
  # it can be range-filtered in Typesense. Documents without a parseable range
  # are left untouched and simply won't match a tariff filter.
  defp put_tariff(%{entry_requirements: requirements} = document)
       when is_binary(requirements) do
    case Regex.run(@tariff_regex, requirements) do
      [_, min, max] ->
        Map.merge(document, %{
          tariff_points_min: String.to_integer(min),
          tariff_points_max: String.to_integer(max)
        })

      _ ->
        document
    end
  end

  defp put_tariff(document), do: document

  # Typesense rejects `null` for string fields, so optional fields that are
  # absent in Postgres are omitted from the document entirely.
  defp drop_nils(document) do
    Map.reject(document, fn {_key, value} -> is_nil(value) end)
  end
end

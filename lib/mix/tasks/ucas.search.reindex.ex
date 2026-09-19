defmodule Mix.Tasks.Ucas.Search.Reindex do
  @shortdoc "Recreate the Typesense collection and index all course study options"

  @moduledoc """
  Recreates the `course_study_options` Typesense collection and imports every
  flattened course study option from Postgres.

      mix ucas.search.reindex

  Run this after loading courses (see `load_courses.py`) or whenever the
  collection schema changes.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    collection = Ucas.Search.Document.collection_name()

    case Ucas.Search.recreate_collection() do
      {:ok, _response} ->
        Mix.shell().info("Created Typesense collection #{collection}")

      {:error, reason} ->
        Mix.raise("Failed to create collection #{collection}: #{inspect(reason)}")
    end

    case Ucas.Search.reindex() do
      {:ok, count} ->
        Mix.shell().info("Indexed #{count} documents into #{collection}")

      {:error, reason} ->
        Mix.raise("Failed to index documents: #{inspect(reason)}")
    end
  end
end

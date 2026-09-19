defmodule Ucas.Search.Bootstrap do
  @moduledoc """
  Ensures the Typesense collection exists and is populated from Postgres when
  the application starts.

  Typesense keeps its own copy of the data, so this only indexes when the
  collection is missing or empty; a populated collection is left untouched.
  Set `config :ucas, search_bootstrap: false` to disable it (tests do this),
  or run `mix ucas.search.reindex` to force a refresh (e.g. after a schema
  change).

  The work runs in a `Task` so it never blocks the supervision tree, and it
  never raises: a Typesense outage is logged rather than taking the app down.
  """

  require Logger

  alias Ucas.Search
  alias Ucas.Search.Document

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @doc false
  def start_link(_opts), do: Task.start_link(&run/0)

  @doc false
  def run do
    if Application.get_env(:ucas, :search_bootstrap, true) do
      ensure_indexed()
    end
  end

  @doc """
  Indexes from Postgres unless the collection already has documents.

  Returns `:ok` regardless of the outcome; failures are logged so a Typesense
  outage cannot crash the application.
  """
  @spec ensure_indexed() :: :ok
  def ensure_indexed do
    case ExTypesense.get_collection(Document.collection_name()) do
      {:ok, %{num_documents: count}} when is_integer(count) and count > 0 ->
        Logger.debug(fn -> "Typesense collection already has #{count} documents" end)
        :ok

      {:ok, _empty} ->
        create_and_index("collection is empty")

      {:error, _reason} ->
        create_and_index("collection is missing")
    end
  rescue
    error ->
      Logger.error("Typesense bootstrap failed: #{Exception.message(error)}")
      :ok
  end

  defp create_and_index(reason) do
    Logger.info("Indexing course study options from Postgres (#{reason})")

    with {:ok, _collection} <- Search.create_collection(),
         {:ok, count} <- Search.reindex() do
      Logger.info("Indexed #{count} course study options into Typesense")
      :ok
    else
      {:error, reason} ->
        Logger.error("Typesense bootstrap failed: #{inspect(reason)}")
        :ok
    end
  end
end

defmodule Ucas.Search.Bootstrap do
  @moduledoc """
  Ensures the Typesense collection exists and is populated from Postgres when
  the application starts.

  Typesense keeps its own copy of the data, so this only indexes when the
  collection is missing or empty; a populated collection is left untouched.
  Set `config :ucas, search_bootstrap: false` to disable it (tests do this),
  or run `mix ucas.search.reindex` to force a refresh (e.g. after a schema
  change).

  The check-then-act is serialized in-process (`:global.trans/2`): the `Task`
  is transient, so a crash restarts it, and without the lock a restarted copy
  could race the still-running original and both try to create the collection.
  `create_and_index/1` is idempotent, so a duplicate run is only wasteful.

  The work runs in a `Task` so it never blocks the supervision tree, and it
  never raises: a Typesense outage is logged rather than taking the app down.
  """

  require Logger

  alias Ucas.Search
  alias Ucas.Search.Document

  @lock {__MODULE__, :ensure_indexed}

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
    :global.trans(@lock, fn -> do_ensure_indexed() end, [node()])
    :ok
  rescue
    error ->
      Logger.error("Typesense bootstrap failed: #{Exception.message(error)}")
      :ok
  end

  defp do_ensure_indexed do
    case ExTypesense.get_collection(Document.collection_name()) do
      {:ok, %{num_documents: count}} when is_integer(count) and count > 0 ->
        Logger.debug(fn -> "Typesense collection already has #{count} documents" end)
        :ok

      {:ok, _empty} ->
        create_and_index("collection is empty")

      {:error, _reason} ->
        create_and_index("collection is missing")
    end
  end

  defp create_and_index(reason) do
    Logger.info("Indexing course study options from Postgres (#{reason})")

    with {:ok, _collection} <- ensure_collection(),
         {:ok, count} <- Search.reindex() do
      Logger.info("Indexed #{count} course study options into Typesense")
      :ok
    else
      {:error, reason} ->
        Logger.error("Typesense bootstrap failed: #{inspect(reason)}")
        :ok
    end
  end

  # Typesense rejects a duplicate `create_collection` with 409 ("A collection
  # with name `x` already exists"), which is the outcome we wanted anyway: a
  # concurrent or previous run already created it. Treat that as success so a
  # benign race doesn't abort the reindex.
  defp ensure_collection do
    case Search.create_collection() do
      {:error, %{message: message}} = error when is_binary(message) ->
        if duplicate_collection?(message), do: {:ok, :already_exists}, else: error

      result ->
        result
    end
  end

  defp duplicate_collection?(message), do: String.contains?(message, "already exists")
end

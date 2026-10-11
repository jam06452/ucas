defmodule Ucas.Search.BootstrapTest do
  use ExUnit.Case, async: false

  alias Ucas.Search.Bootstrap
  alias Ucas.Search.FakeTypesenseClient

  setup do
    FakeTypesenseClient.reset()
    :ok
  end

  test "creates the collection when it is missing" do
    FakeTypesenseClient.set_collection(:missing)

    assert :ok = Bootstrap.ensure_indexed()
    assert :get_collection in FakeTypesenseClient.calls()
    assert :create_collection in FakeTypesenseClient.calls()
  end

  test "creates the collection when it exists but is empty" do
    FakeTypesenseClient.set_collection(0)

    assert :ok = Bootstrap.ensure_indexed()
    assert :create_collection in FakeTypesenseClient.calls()
  end

  test "still indexes when a concurrent run already created the collection" do
    FakeTypesenseClient.set_collection(:missing)

    FakeTypesenseClient.fail_create_collection(
      "A collection with name `course_study_options` already exists."
    )

    assert :ok = Bootstrap.ensure_indexed()
    assert :import_documents in FakeTypesenseClient.calls()
  end

  test "leaves a populated collection untouched" do
    FakeTypesenseClient.set_collection(20_000)

    assert :ok = Bootstrap.ensure_indexed()
    assert :get_collection in FakeTypesenseClient.calls()
    refute :create_collection in FakeTypesenseClient.calls()
    refute :import_documents in FakeTypesenseClient.calls()
  end
end

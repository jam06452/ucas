defmodule UcasWeb.ConnCase do
  @moduledoc """
  Test case for tests that need a connection or a LiveView.
  """

  use ExUnit.CaseTemplate

  import Phoenix.ConnTest

  using do
    quote do
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      use UcasWeb, :verified_routes

      @endpoint UcasWeb.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: build_conn()}
  end
end

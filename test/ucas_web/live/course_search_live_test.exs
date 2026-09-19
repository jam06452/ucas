defmodule UcasWeb.CourseSearchLiveTest do
  use UcasWeb.ConnCase, async: false

  alias Ucas.Search.FakeTypesenseClient

  @facets %{
    "provider_name" => [{"University of Oxford", 1}],
    "qualification_name" => [{"BSc", 1}],
    "study_mode_name" => [{"Full-time", 1}],
    "academic_year" => [{"2025/26", 1}],
    "campus_name" => [{"City Centre", 1}]
  }

  @hit %{
    "id" => "1",
    "course_id" => "cd41b216-1f3b-49ec-945b-ae71defb7325",
    "course_name" => "Computer Science",
    "provider_name" => "University of Oxford",
    "qualification_name" => "BSc",
    "study_mode_name" => "Full-time",
    "academic_year" => "2025/26",
    "campus_name" => "City Centre",
    "course_code" => "G400",
    "duration" => "3 years",
    "start_date" => "September 2026"
  }

  setup do
    FakeTypesenseClient.reset()
    :ok
  end

  test "renders search results and facet filters", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{hits: [@hit], facets: @facets, found: 1})

    {:ok, view, html} = live(conn, ~p"/search")

    assert html =~ "Computer Science"
    assert has_element?(view, "#course-search-form")
    assert has_element?(view, "input[name=q]")
    assert has_element?(view, "#course-1")

    assert has_element?(
             view,
             "a#course-1[href='https://www.ucas.com/explore/courses/cd41b216-1f3b-49ec-945b-ae71defb7325/computer-science?studyYear=2025/26']"
           )

    assert has_element?(
             view,
             "input[phx-value-field=provider_name][phx-value-option='University of Oxford']"
           )

    assert has_element?(
             view,
             "input[phx-value-field=study_mode_name][phx-value-option=Full-time]"
           )

    assert has_element?(view, "button[phx-value-field=academic_year][phx-value-option='2025/26']")
  end

  test "facet controls avoid the reserved phx-value-value key", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{facets: @facets, found: 0})
    {:ok, view, html} = live(conn, ~p"/search")

    # LiveView's extractMeta overwrites `phx-value-value` with the element's own
    # `value` property (a checkbox defaults to "on"), so facet controls must use
    # a different key or the real value is lost.
    refute html =~ "phx-value-value"
    assert has_element?(view, "input[phx-value-option=Full-time]")
  end

  test "toggling a facet sends it as a filter", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{facets: @facets, found: 0})
    {:ok, view, _html} = live(conn, ~p"/search")

    view
    |> element("input[phx-value-field=study_mode_name][phx-value-option=Full-time]")
    |> render_click()

    assert FakeTypesenseClient.last_query()[:filter_by] == "study_mode_name:=[`Full-time`]"
  end

  test "typing a query searches with the typed term", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})
    {:ok, view, _html} = live(conn, ~p"/search")

    view |> form("#course-search-form", q: "law") |> render_change()

    assert FakeTypesenseClient.last_query()[:q] == "law"
  end

  test "shows an empty state when there are no results", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search")

    assert has_element?(view, "h3", "No courses match your search")
  end

  test "renders the tariff slider at the full range", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search")

    assert has_element?(view, "#facet-tariff_points")
    assert has_element?(view, "#tariff-slider")
    assert has_element?(view, "input[name=tariff_min][value='0']")
    assert has_element?(view, "input[name=tariff_max][value='240']")
  end

  test "dragging the tariff slider filters by range", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search")

    view
    |> form("#tariff-form", tariff_min: "96", tariff_max: "112")
    |> render_change()

    assert FakeTypesenseClient.last_query()[:filter_by] ==
             "tariff_points_min:<=112 && tariff_points_max:>=96"
  end

  test "reads the tariff range from the URL", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search?tariff_min=96&tariff_max=112")

    assert has_element?(view, "input[name=tariff_min][value='96']")
    assert has_element?(view, "input[name=tariff_max][value='112']")

    assert FakeTypesenseClient.last_query()[:filter_by] ==
             "tariff_points_min:<=112 && tariff_points_max:>=96"
  end

  test "clearing the tariff filter removes it", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search?tariff_min=96&tariff_max=112")

    view
    |> element("#facet-tariff_points button[phx-click=clear-tariff]")
    |> render_click()

    assert FakeTypesenseClient.last_query()[:filter_by] == nil
  end

  test "calculator converts grades into UCAS points", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search")

    assert has_element?(view, "#ucas-calculator")

    view
    |> form("#ucas-calculator-form", calc: "A*A*A*")
    |> render_change()

    assert has_element?(view, "#ucas-result", "168")
    assert render(view) =~ "UCAS points"
  end

  test "calculator rounds UCAS points down to grades", %{conn: conn} do
    FakeTypesenseClient.set_search_response(%{found: 0})

    {:ok, view, _html} = live(conn, ~p"/search")

    view
    |> form("#ucas-calculator-form", calc: "102")
    |> render_change()

    assert has_element?(view, "#ucas-result", "CCC")
    assert render(view) =~ "A-level grades"
  end
end

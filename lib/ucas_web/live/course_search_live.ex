defmodule UcasWeb.CourseSearchLive do
  @moduledoc """
  Course search page — Typesense-backed search and faceted filtering.
  State is fully synchronized with the URL via `push_patch` and `handle_params`.
  """

  use UcasWeb, :live_view

  require Logger

  alias Ucas.Calculator
  alias Ucas.Search
  alias Ucas.Search.Query

  @known_facets [
    "provider_name",
    "qualification_name",
    "study_mode_name",
    "academic_year",
    "campus_name"
  ]

  # Bounds of the UCAS tariff range slider. The dataset's tariff ranges run
  # from 0 to 240 points.
  @tariff_min 0
  @tariff_max 240

  # ---------------------------------------------------------------------
  # Lifecycle & State (URL-Driven)
  # ---------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    # Mount sets up the static/default assigns.
    # The actual data fetching happens in handle_params.
    socket =
      assign(socket,
        per_page: Query.default_per_page(),
        facets: %{},
        results: [],
        found: 0,
        total_pages: 1,
        error: nil,
        input: "",
        result: "",
        result_label: ""
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    q = Map.get(params, "q", "")
    page = parse_page(params)
    filters = parse_filters(params)
    tariff = parse_tariff(params)

    socket =
      socket
      |> assign(
        q: q,
        search_form: to_form(%{"q" => q}),
        page: page,
        filters: filters,
        tariff: tariff
      )
      |> run_search()

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------
  # Events (Push Patch Only)
  # ---------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    path = build_path(q, socket.assigns.filters, socket.assigns.tariff, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("toggle-filter", %{"field" => field, "option" => value}, socket) do
    filters = toggle_filter(socket.assigns.filters, field, value)
    path = build_path(socket.assigns.q, filters, socket.assigns.tariff, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear-filter", %{"field" => field}, socket) do
    filters = Map.delete(socket.assigns.filters, field)
    path = build_path(socket.assigns.q, filters, socket.assigns.tariff, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("tariff", params, socket) do
    {current_min, current_max} = socket.assigns.tariff

    tariff =
      normalize_tariff(
        parse_int(params["tariff_min"], current_min),
        parse_int(params["tariff_max"], current_max)
      )

    path = build_path(socket.assigns.q, socket.assigns.filters, tariff, 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear-tariff", _params, socket) do
    path = build_path(socket.assigns.q, socket.assigns.filters, default_tariff(), 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear-all", _params, socket) do
    path = build_path("", %{}, default_tariff(), 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    path =
      build_path(
        socket.assigns.q,
        socket.assigns.filters,
        socket.assigns.tariff,
        String.to_integer(page)
      )

    socket = push_patch(socket, to: path)
    {:noreply, push_event(socket, "scroll-to-top", %{})}
  end

  def handle_event("convert", %{"calc" => value}, socket) do
    {result, label} = convert(value)

    {:noreply, assign(socket, input: value, result: result, result_label: label)}
  end

  # ---------------------------------------------------------------------
  # Search Execution
  # ---------------------------------------------------------------------

  defp run_search(socket) do
    %{q: q, filters: filters, page: page, per_page: per_page, tariff: tariff} = socket.assigns

    query =
      Query.new(
        q: q,
        filters: tariff_filter(filters, tariff),
        page: page,
        per_page: per_page
      )

    case Search.search(query) do
      {:ok, %{hits: hits, facets: facets, found: found}} ->
        total_pages = max(ceil(found / per_page), 1)

        socket =
          assign(socket,
            results: hits,
            facets: facets,
            found: found,
            total_pages: total_pages,
            error: nil
          )

        # A stale/hand-edited/back-button URL can request a page beyond the
        # current result set (e.g. after a filter shrinks the total). Snap
        # back to the last valid page instead of showing a false empty state.
        if page > total_pages do
          path = build_path(q, filters, tariff, total_pages)
          push_patch(socket, to: path)
        else
          socket
        end

      {:error, reason} ->
        Logger.error("Course search failed: #{inspect(reason)}")

        assign(socket,
          results: [],
          facets: %{},
          found: 0,
          total_pages: 1,
          error: "We couldn't complete your search. Please try again."
        )
    end
  end

  # ---------------------------------------------------------------------
  # URL & Params Helpers
  # ---------------------------------------------------------------------

  defp build_path(q, filters, tariff, page) do
    filters_map = Enum.into(filters, %{}, fn {k, v} -> {k, MapSet.to_list(v)} end)

    params =
      %{"q" => q, "page" => page}
      |> Map.merge(filters_map)
      |> Map.merge(tariff_params(tariff))
      |> Enum.reject(fn
        {"q", ""} -> true
        {"page", 1} -> true
        {_, []} -> true
        _ -> false
      end)
      |> Map.new()

    # Note: Replace ~p"/search" with your actual route macro if different
    ~p"/search?#{params}"
  end

  # Only persists the tariff bounds that differ from the full range, so a
  # fully-open slider keeps the URL clean.
  defp tariff_params({min, max}) do
    %{}
    |> maybe_put("tariff_min", min, min > @tariff_min)
    |> maybe_put("tariff_max", max, max < @tariff_max)
  end

  defp maybe_put(params, key, value, true), do: Map.put(params, key, value)
  defp maybe_put(params, _key, _value, false), do: params

  defp parse_tariff(params) do
    normalize_tariff(
      parse_int(params["tariff_min"], @tariff_min),
      parse_int(params["tariff_max"], @tariff_max)
    )
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_value, default), do: default

  # Clamps rather than swaps: if the two bounds cross, the max is pulled up
  # to meet the min. Swapping which bound a handle represents mid-drag is
  # what made the slider feel like it was fighting the user.
  defp normalize_tariff(min, max) do
    min = min |> max(@tariff_min) |> min(@tariff_max)
    max = max |> min(@tariff_max) |> max(min)

    {min, max}
  end

  defp default_tariff, do: {@tariff_min, @tariff_max}

  defp tariff_bounds, do: {@tariff_min, @tariff_max}

  defp parse_filters(params) do
    Enum.reduce(@known_facets, %{}, fn field, acc ->
      case params[field] do
        nil -> acc
        values when is_list(values) -> Map.put(acc, field, MapSet.new(values))
        value -> Map.put(acc, field, MapSet.new([value]))
      end
    end)
  end

  defp toggle_filter(filters, field, value) do
    values = Map.get(filters, field, MapSet.new())

    values =
      if MapSet.member?(values, value) do
        MapSet.delete(values, value)
      else
        MapSet.put(values, value)
      end

    if MapSet.size(values) == 0 do
      Map.delete(filters, field)
    else
      Map.put(filters, field, values)
    end
  end

  defp parse_page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, _rest} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_params), do: 1

  # ---------------------------------------------------------------------
  # View Helpers
  # ---------------------------------------------------------------------

  defp format_count(count) do
    count
    |> Integer.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  # `selected` values are always strings (they come from the URL / phx-value
  # attributes), but Typesense can return numeric facet values (e.g.
  # academic_year as an integer). Without normalizing both sides to strings,
  # a selected option would never register as "checked" and would appear a
  # second time as a synthetic zero-count entry.
  defp facet_options(facets, field, selected) do
    options =
      facets
      |> Map.get(field, [])
      |> Enum.map(fn option -> %{option | value: to_string(option.value)} end)

    present = MapSet.new(options, & &1.value)

    missing =
      selected
      |> MapSet.difference(present)
      |> Enum.map(&%{value: &1, count: 0})

    {chosen, rest} = Enum.split_with(options, &MapSet.member?(selected, &1.value))

    chosen ++ rest ++ missing
  end

  defp selected(filters, field), do: Map.get(filters, field, MapSet.new())

  defp facet_title("provider_name"), do: "Provider"
  defp facet_title("qualification_name"), do: "Qualification"
  defp facet_title("study_mode_name"), do: "Study mode"
  defp facet_title("academic_year"), do: "Academic year"
  defp facet_title("campus_name"), do: "Campus"

  defp active_filter_count(filters, tariff) do
    facet_count =
      Enum.reduce(filters, 0, fn {_field, values}, acc -> acc + MapSet.size(values) end)

    facet_count + if(tariff_active?(tariff), do: 1, else: 0)
  end

  defp tariff_active?({min, max}), do: min > @tariff_min or max < @tariff_max

  defp tariff_filter(filters, tariff) do
    if tariff_active?(tariff) do
      {min, max} = tariff
      Map.put(filters, "tariff_points", %{min: min, max: max})
    else
      filters
    end
  end

  defp tariff_label({min, max}) do
    "#{min} - #{max}#{if max >= @tariff_max, do: "+"} points"
  end

  # Positions the highlighted segment of the slider track between the two
  # handles, as percentages of the full range. Used only for the initial
  # server-rendered position; the JS hook takes over from there.
  defp tariff_fill_style(min, max, bounds_min, bounds_max) do
    span = bounds_max - bounds_min
    left = (min - bounds_min) / span * 100
    width = (max - min) / span * 100

    "left: #{left}%; width: #{width}%"
  end

  # ---------------------------------------------------------------------
  # Render & UI Components
  # ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="course-search-page"
      phx-hook="ScrollToTop"
      class="min-h-screen bg-brand-base text-brand-light font-sans"
    >
      <div class="w-full px-6 py-8 flex flex-col lg:flex-row gap-6">
        <.sidebar
          filters={@filters}
          facets={@facets}
          tariff={@tariff}
          input={@input}
          result={@result}
          result_label={@result_label}
        />

        <div class="flex-1 min-w-0">
          <.search_bar form={@search_form} q={@q} />
          <.active_filters filters={@filters} tariff={@tariff} found={@found} />

          <div
            :if={@error}
            class="bg-[#2a1d1a] border border-[#5a3a2e] rounded-3xl p-6 mb-4 text-sm text-[#f0a08c]"
          >
            {@error}
          </div>

          <.results list={@results} />
          <.empty_state :if={@results == [] and is_nil(@error)} />
          <.pagination page={@page} total_pages={@total_pages} />
        </div>
      </div>
    </div>
    """
  end

  defp sidebar(assigns) do
    ~H"""
    <aside class="w-full lg:w-[320px] shrink-0 bg-brand-surface border border-brand-border rounded-3xl p-6 h-fit">
      <div class="flex items-center justify-between mb-6">
        <h2 class="font-serif text-2xl">Filters</h2>
        <button
          type="button"
          phx-click="clear-all"
          class="text-brand-accent text-sm hover:text-brand-accent-hover transition-colors focus:outline-none focus:underline"
        >
          Reset all
        </button>
      </div>

      <.calculator input={@input} result={@result} result_label={@result_label} />

      <.tariff_slider tariff={@tariff} bounds={tariff_bounds()} />

      <.facet_checkboxes
        field="provider_name"
        title={facet_title("provider_name")}
        options={facet_options(@facets, "provider_name", selected(@filters, "provider_name"))}
        selected={selected(@filters, "provider_name")}
        scroll?={true}
      />
      <.facet_checkboxes
        field="qualification_name"
        title={facet_title("qualification_name")}
        options={
          facet_options(@facets, "qualification_name", selected(@filters, "qualification_name"))
        }
        selected={selected(@filters, "qualification_name")}
        scroll?={true}
      />
      <.facet_checkboxes
        field="study_mode_name"
        title={facet_title("study_mode_name")}
        options={facet_options(@facets, "study_mode_name", selected(@filters, "study_mode_name"))}
        selected={selected(@filters, "study_mode_name")}
      />
      <.facet_chips
        field="academic_year"
        title={facet_title("academic_year")}
        options={facet_options(@facets, "academic_year", selected(@filters, "academic_year"))}
        selected={selected(@filters, "academic_year")}
      />
      <.facet_checkboxes
        field="campus_name"
        title={facet_title("campus_name")}
        options={facet_options(@facets, "campus_name", selected(@filters, "campus_name"))}
        selected={selected(@filters, "campus_name")}
        scroll?={true}
      />
    </aside>
    """
  end

  defp calculator(assigns) do
    ~H"""
    <div id="ucas-calculator" class="pb-6 mb-6 border-b border-brand-border">
      <h3 class="text-sm font-medium text-brand-light mb-3">UCAS Calculator</h3>

      <form
        id="ucas-calculator-form"
        phx-change="convert"
        phx-submit="convert"
        phx-debounce="200"
        class="flex items-center gap-2"
      >
        <input
          id="ucas-input"
          type="text"
          name="calc"
          value={@input}
          autocomplete="off"
          placeholder="A*A*A* or 192"
          aria-label="A-level grades or UCAS points"
          class="flex-1 min-w-0 bg-brand-elevated border border-brand-border rounded-xl px-3 py-2 text-sm text-center text-brand-light placeholder:text-brand-subtle focus:outline-none focus:border-brand-border-focus focus:ring-1 focus:ring-brand-border-focus transition-colors"
        />

        <.icon name="hero-arrow-right" class="h-4 w-4 shrink-0 text-brand-muted" />

        <div
          id="ucas-result"
          class="flex-1 min-w-0 bg-brand-base border border-brand-border rounded-xl px-3 py-2 text-sm text-center text-brand-light"
        >
          {@result}
        </div>
      </form>

      <p class="text-[11px] text-brand-subtle mt-2 text-center">
        {if @result_label == "", do: "Type grades or points to convert.", else: @result_label}
      </p>
    </div>
    """
  end

  # Converts a single input that may hold either A-level grades or UCAS points.
  # Returns `{result, result_label}`.
  defp convert(value) do
    case Calculator.parse_points(value) do
      {:ok, points} ->
        case Calculator.grades_for_points(points, Calculator.default_subjects()) do
          {:ok, combo, _total} -> {Enum.join(combo), "A-level grades"}
          :below_minimum -> {"\u2014", "A-level grades"}
        end

      :error ->
        case Calculator.parse_grades(value) do
          [] -> {"", ""}
          grades -> {Integer.to_string(Calculator.points_for_grades(grades)), "UCAS points"}
        end
    end
  end

  defp search_bar(assigns) do
    ~H"""
    <.form
      for={@form}
      id="course-search-form"
      phx-change="search"
      phx-submit="search"
      class="mb-6"
    >
      <div class="flex items-center gap-3 bg-brand-surface border border-brand-border rounded-2xl px-5 py-4 focus-within:border-brand-border-focus focus-within:ring-1 focus-within:ring-brand-border-focus transition-colors">
        <.icon name="hero-magnifying-glass" class="h-4 w-4 text-brand-muted shrink-0" />
        <input
          type="text"
          name="q"
          value={@q}
          phx-debounce="250"
          autocomplete="off"
          placeholder="Search by course, provider or code..."
          class="flex-1 bg-transparent outline-none text-sm placeholder:text-brand-subtle"
        />
      </div>
    </.form>
    """
  end

  defp active_filters(assigns) do
    assigns = assign(assigns, filter_count: active_filter_count(assigns.filters, assigns.tariff))

    ~H"""
    <div>
      <div
        :if={map_size(@filters) > 0 or tariff_active?(@tariff)}
        class="flex flex-wrap items-center gap-2 mb-4"
      >
        <span class="text-xs text-brand-muted">Filters:</span>
        <%= for {field, values} <- @filters, value <- values do %>
          <button
            type="button"
            phx-click="toggle-filter"
            phx-value-field={field}
            phx-value-option={value}
            class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs bg-brand-elevated border border-brand-border text-brand-light hover:border-brand-border-focus focus:outline-none focus:ring-2 focus:ring-brand-accent transition-colors"
          >
            {value}
            <.icon name="hero-x-mark" class="h-3 w-3" />
          </button>
        <% end %>
        <button
          :if={tariff_active?(@tariff)}
          type="button"
          phx-click="clear-tariff"
          class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs bg-brand-elevated border border-brand-border text-brand-light hover:border-brand-border-focus focus:outline-none focus:ring-2 focus:ring-brand-accent transition-colors"
        >
          {tariff_label(@tariff)}
          <.icon name="hero-x-mark" class="h-3 w-3" />
        </button>
        <button
          type="button"
          phx-click="clear-all"
          class="text-xs text-brand-accent hover:text-brand-accent-hover transition-colors ml-1 focus:outline-none focus:underline"
        >
          Clear all
        </button>
      </div>

      <p class="text-xs text-brand-muted mb-4">
        {format_count(@found)} {if @found == 1, do: "course", else: "courses"} found
        <span :if={@filter_count > 0}>
          &bull; {@filter_count} filter{if @filter_count == 1, do: "", else: "s"}
        </span>
      </p>
    </div>
    """
  end

  defp results(assigns) do
    ~H"""
    <div :if={@list != []} class="grid grid-cols-1 xl:grid-cols-2 gap-4">
      <a
        :for={course <- @list}
        id={"course-#{course["id"]}"}
        href={ucas_course_url(course)}
        target="_blank"
        rel="noopener noreferrer"
        class="block bg-brand-surface border border-brand-border rounded-3xl p-6 hover:border-brand-border-hover transition-colors"
      >
        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
          <div class="min-w-0">
            <h3 class="font-serif text-2xl text-brand-accent mb-1">{course["course_name"]}</h3>
            <p class="text-sm text-brand-muted">
              {course["provider_name"]}
              <span :if={course["campus_name"]} class="mx-1.5">&bull;</span>
              {course["campus_name"]}
            </p>
          </div>

          <div class="flex flex-wrap gap-2 sm:justify-end shrink-0">
            <span
              :if={course["course_code"]}
              class="px-3 py-1.5 rounded-full text-xs font-medium bg-brand-elevated text-brand-light border border-brand-border"
            >
              {course["course_code"]}
            </span>
            <span class="px-3 py-1.5 rounded-full text-xs font-medium bg-brand-accent/10 text-brand-accent border border-brand-accent/30">
              {course["qualification_name"]}
            </span>
          </div>
        </div>

        <p class="text-sm text-brand-muted mt-4">
          <span :if={course["duration"]}>{course["duration"]}</span>
          <span :if={course["duration"] && course["start_date"]} class="mx-1.5">&bull;</span>
          <span :if={course["start_date"]}>{course["start_date"]}</span>
          <span :if={course["study_mode_name"]} class="mx-1.5">&bull;</span>
          <span :if={course["study_mode_name"]}>{course["study_mode_name"]}</span>
          <span :if={course["academic_year"]} class="mx-1.5">&bull;</span>
          <span :if={course["academic_year"]}>{course["academic_year"]}</span>
        </p>

        <p :if={course["entry_requirements"]} class="text-xs text-brand-subtle mt-3">
          {course["entry_requirements"]}
        </p>
      </a>
    </div>
    """
  end

  # Builds the public UCAS course page URL. The course title is slugified to
  # match UCAS' URL format, e.g. "2D Animation and Stop Motion" becomes
  # "2d-animation-and-stop-motion".
  defp ucas_course_url(course) do
    slug =
      course["course_name"]
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "https://www.ucas.com/explore/courses/#{course["course_id"]}/#{slug}?studyYear=#{course["academic_year"]}"
  end

  defp pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-center gap-4 mt-8">
      <button
        type="button"
        phx-click="page"
        phx-value-page={@page - 1}
        disabled={@page <= 1}
        class="px-4 py-2 rounded-2xl text-sm border border-brand-border text-brand-light hover:border-brand-border-focus focus:outline-none focus:ring-2 focus:ring-brand-accent transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
      >
        Previous
      </button>
      <span class="text-xs text-brand-muted">Page {@page} of {@total_pages}</span>
      <button
        type="button"
        phx-click="page"
        phx-value-page={@page + 1}
        disabled={@page >= @total_pages}
        class="px-4 py-2 rounded-2xl text-sm border border-brand-border text-brand-light hover:border-brand-border-focus focus:outline-none focus:ring-2 focus:ring-brand-accent transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
      >
        Next
      </button>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="bg-brand-surface border border-brand-border rounded-3xl p-12 text-center">
      <h3 class="font-serif text-2xl mb-2">No courses match your search</h3>
      <p class="text-sm text-brand-muted mb-6">
        Try a different search term or clear a filter to see more results.
      </p>
      <button
        type="button"
        phx-click="clear-all"
        class="inline-flex items-center justify-center bg-brand-cream hover:bg-brand-cream-hover text-brand-base font-medium px-6 py-3 rounded-2xl focus:outline-none focus:ring-2 focus:ring-brand-accent focus:ring-offset-2 focus:ring-offset-brand-base transition-colors duration-200 text-sm"
      >
        Reset all filters
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------
  # Tariff Slider
  #
  # Dragging used to be driven entirely by `phx-change`, which fired a
  # server round trip (and a morphdom patch) on every single pixel of drag.
  # That's what made the slider feel laggy and unresponsive. The
  # `TariffSlider` JS hook (assets/js/tariff_slider.js) now handles dragging
  # fully client-side — instant visual feedback, zero server calls — and
  # only pushes an event to the server once, on release. See the comment at
  # the bottom of this file for how to wire the hook into app.js.
  # ---------------------------------------------------------------------

  attr :tariff, :any, required: true
  attr :bounds, :any, required: true

  defp tariff_slider(assigns) do
    {min, max} = assigns.tariff
    {bounds_min, bounds_max} = assigns.bounds

    assigns =
      assign(assigns, min: min, max: max, bounds_min: bounds_min, bounds_max: bounds_max)

    ~H"""
    <div class="pb-6 mb-6 border-b border-brand-border last:border-b-0 last:pb-0 last:mb-0">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-medium text-brand-light">UCAS Tariff Points</h3>
        <button
          :if={@min > @bounds_min or @max < @bounds_max}
          type="button"
          phx-click="clear-tariff"
          class="text-xs text-brand-accent hover:text-brand-accent-hover transition-colors focus:outline-none focus:underline"
        >
          Clear
        </button>
      </div>

      <div
        id="tariff-slider"
        phx-hook="TariffSlider"
        data-bounds-min={@bounds_min}
        data-bounds-max={@bounds_max}
        class="relative h-4 flex items-center"
      >
        <div class="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-1.5 rounded-full bg-brand-elevated">
        </div>
        <div
          data-role="fill"
          class="absolute top-1/2 -translate-y-1/2 h-1.5 rounded-full bg-brand-accent"
          style={tariff_fill_style(@min, @max, @bounds_min, @bounds_max)}
        >
        </div>
        <input
          type="range"
          name="tariff_min"
          min={@bounds_min}
          max={@bounds_max}
          value={@min}
          aria-label="Minimum UCAS tariff points"
          class={tariff_input_classes(if(@min >= @max, do: "z-20", else: "z-10"))}
        />
        <input
          type="range"
          name="tariff_max"
          min={@bounds_min}
          max={@bounds_max}
          value={@max}
          aria-label="Maximum UCAS tariff points"
          class={tariff_input_classes("z-10")}
        />
      </div>

      <p data-role="tariff-label" class="mt-3 text-xs text-brand-muted">
        {@min} - {@max}{if @max >= @bounds_max, do: "+"} Points
      </p>
    </div>
    """
  end

  # Two native range inputs are stacked over a shared track. `pointer-events`
  # is disabled on the inputs and re-enabled on the thumbs so each handle stays
  # independently draggable; the z-index swap keeps the lower handle grabbable
  # when both handles meet.
  defp tariff_input_classes(z_index) do
    [
      "absolute inset-0 h-4 w-full appearance-none bg-transparent pointer-events-none",
      "[&::-webkit-slider-thumb]:pointer-events-auto [&::-webkit-slider-thumb]:h-4 [&::-webkit-slider-thumb]:w-4 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-brand-base [&::-webkit-slider-thumb]:bg-brand-accent [&::-webkit-slider-thumb]:cursor-grab [&::-webkit-slider-thumb]:transition-transform [&::-webkit-slider-thumb]:hover:scale-110",
      "[&::-moz-range-thumb]:pointer-events-auto [&::-moz-range-thumb]:h-4 [&::-moz-range-thumb]:w-4 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-brand-base [&::-moz-range-thumb]:bg-brand-accent [&::-moz-range-thumb]:cursor-grab",
      z_index
    ]
  end

  # ---------------------------------------------------------------------
  # Facet Components
  # ---------------------------------------------------------------------

  attr :field, :string, required: true
  attr :title, :string, required: true
  attr :options, :list, required: true
  attr :selected, :any, required: true
  attr :scroll?, :boolean, default: false

  defp facet_checkboxes(assigns) do
    ~H"""
    <div
      id={"facet-#{@field}"}
      class="pb-6 mb-6 border-b border-brand-border last:border-b-0 last:pb-0 last:mb-0"
    >
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-medium text-brand-light">{@title}</h3>
        <button
          :if={MapSet.size(@selected) > 0}
          type="button"
          phx-click="clear-filter"
          phx-value-field={@field}
          class="text-xs text-brand-accent hover:text-brand-accent-hover transition-colors focus:outline-none focus:underline"
        >
          Clear
        </button>
      </div>
      <div class={["flex flex-col gap-2", @scroll? && "max-h-56 overflow-y-auto pr-1"]}>
        <p :if={@options == []} class="text-xs text-brand-subtle">No options</p>
        <label
          :for={option <- @options}
          phx-click="toggle-filter"
          phx-value-field={@field}
          phx-value-option={option.value}
          class="flex items-center justify-between gap-2 text-sm text-brand-light cursor-pointer group"
        >
          <span class="flex items-center gap-2 min-w-0">
            <input
              type="checkbox"
              checked={MapSet.member?(@selected, option.value)}
              class="h-4 w-4 shrink-0 rounded accent-brand-accent bg-brand-base border-brand-border pointer-events-none focus:ring-2 focus:ring-brand-accent focus:ring-offset-1 focus:ring-offset-brand-surface"
            />
            <span class="truncate group-hover:text-white transition-colors">{option.value}</span>
          </span>
          <span class="text-xs text-brand-subtle shrink-0">{option.count}</span>
        </label>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :title, :string, required: true
  attr :options, :list, required: true
  attr :selected, :any, required: true

  defp facet_chips(assigns) do
    ~H"""
    <div
      id={"facet-#{@field}"}
      class="pb-6 mb-6 border-b border-brand-border last:border-b-0 last:pb-0 last:mb-0"
    >
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-medium text-brand-light">{@title}</h3>
        <button
          :if={MapSet.size(@selected) > 0}
          type="button"
          phx-click="clear-filter"
          phx-value-field={@field}
          class="text-xs text-brand-accent hover:text-brand-accent-hover transition-colors focus:outline-none focus:underline"
        >
          Clear
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <p :if={@options == []} class="text-xs text-brand-subtle">No options</p>
        <button
          :for={option <- @options}
          type="button"
          phx-click="toggle-filter"
          phx-value-field={@field}
          phx-value-option={option.value}
          class={[
            "px-3 py-1.5 rounded-full text-xs font-medium border transition-colors focus:outline-none focus:ring-2 focus:ring-brand-accent focus:ring-offset-2 focus:ring-offset-brand-surface",
            if(MapSet.member?(@selected, option.value),
              do: "bg-[#2a2118] text-[#f0a08c] border-[#5a3a2e]",
              else:
                "bg-brand-base text-brand-light border-brand-border hover:border-brand-border-focus"
            )
          ]}
        >
          {option.value}
        </button>
      </div>
    </div>
    """
  end
end

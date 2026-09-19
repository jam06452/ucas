# Ucas

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Course search

Course search and faceted filtering are backed by [Typesense](https://typesense.org)
through [`ex_typesense`](https://hex.pm/packages/ex_typesense). The local
Typesense instance is provided by `docker-compose.yml`.

1. Start the services: `docker compose up -d`
2. Load the course data into Postgres: `python3 load_courses.py`
3. Build the search index: `mix ucas.search.reindex`

The `course_study_options` collection is a flattened read model of the
normalised tables (see `Ucas.Search.Document`). Typesense keeps its own copy
of the data, so the index is built from Postgres only — `courses2.json` is
just the seed used by `load_courses.py` and is not needed at runtime.

On boot, `Ucas.Search.Bootstrap` indexes from Postgres when the collection is
missing or empty, and does nothing when it is already populated. This means a
fresh production database is indexed automatically; set
`config :ucas, search_bootstrap: false` to manage indexing out-of-band (e.g.
a deploy step running `mix ucas.search.reindex`). Run that task to force a
refresh after a schema change.

Search queries, filters and facets are built by `Ucas.Search.Query`, and the
page lives at `/search` (`UcasWeb.CourseSearchLive`).

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

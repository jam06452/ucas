ExUnit.start()

# The fake Typesense client is configured in `config/test.exs`; start it once
# for the whole suite so search calls never hit a real server.
{:ok, _pid} = Ucas.Search.FakeTypesenseClient.start_link()

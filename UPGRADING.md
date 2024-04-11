# Upgrading from v0.2 to v0.3

v0.2.0 and prior relied on deprecated functionality in `goth`.

As of v0.3 a Goth module is required. We suggest following [their documentation](https://hexdocs.pm/goth/1.4.3/readme.html#upgrading-from-goth-1-2) for upgrading for your particular use-case.

For `waffle_gcs` and the `:token_fetcher` option, that might look something like this:

```elixir
defmodule MyApp.WaffleTokenFetcher do
  @behaviour Waffle.Storage.Google.Token.Fetcher

  @impl true
  def get_token(_scope) when is_binary(_scope) do
    Goth.fetch!(MyApp.Goth).token
  end
end
```

And configure `waffle_gcs` to use your module:

```elixir
config :waffle,
  storage: Waffle.Storage.Google.CloudStorage,
  bucket: "gcs-bucket-name",
  token_fetcher: MyApp.WaffleTokenFetcher
```



If you don't already have Goth module implementation, and want to be able to configure it per environment, here's an example that reads from the application configuration during startup.

```elixir
# lib/my_app/goth.ex
defmodule MyApp.Goth

  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(_args) do
    env_opts = Keyword.new(Application.get_env(:my_app, MyApp.Goth, []))
    opts = Keyword.merge([name: MyApp.Goth], env_opts)

    %{
      :id => MyApp.Goth,
      :start => {Goth, :start_link, [opts]}
    }
  end
end
```

```elixir
# config.exs
config :my_app, MyApp.Goth, source: {:metadata, []}

# config/test.exs
# Optional, for if you need to stub `goth` in test
#   requires a custom `:http_client` module/function from the `Goth.start_link/1` documentation.
config :my_app, MyApp.Goth,
  source: {:metadata, []},
  http_client: {&MyAppTest.GothHttpClientStub.access_token_response/1, []}
```

```elixir
# lib/my_app/application.exs
defmodule MyApp.Application do
  use Application
def start(_type, _args) do
  children = [
    # ... other things
    # The `child_spec/1` handles fetching the proper config
    MyApp.Goth
    # ... other things
  ]
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

For other `:source` configurations of `MyApp.Goth`, check out the `goth` documentation for [`Goth.start_link/1`](https://hexdocs.pm/goth/Goth.html#start_link/1)

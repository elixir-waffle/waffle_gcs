# Upgrading

Step-by-step notes for upgrading between versions. See
[CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## From v0.2.x to Unreleased (upcoming 0.3.0)

### Elixir version

Elixir < 1.15 is no longer supported (`mix.exs` now requires `~> 1.15`).

### Goth >= 1.3 and the required `:token_fetcher`

v0.2.0 and prior relied on deprecated functionality in `goth` (1.1's
`Goth.Token.for_scope/1`) through a built-in default fetcher. That default
(`Waffle.Storage.Google.Token.DefaultFetcher`) has been removed, and
`config :waffle, :token_fetcher` is now **required** — starting the adapter
without it raises at the first request.

With Goth >= 1.3, your app must start and own a Goth process. Follow the
[Goth upgrade guide](https://hexdocs.pm/goth/1.4.3/readme.html#upgrading-from-goth-1-2)
for your use case, then point `:token_fetcher` at a module that reads from it:

```elixir
defmodule MyApp.WaffleTokenFetcher do
  @behaviour Waffle.Storage.Google.Token.Fetcher

  @impl true
  def get_token(scope) when is_binary(scope) do
    Goth.fetch!(MyApp.Goth).token
  end
end
```

```elixir
config :waffle,
  storage: Waffle.Storage.Google.CloudStorage,
  bucket: "gcs-bucket-name",
  token_fetcher: MyApp.WaffleTokenFetcher
```

If you don't already have a Goth process, an environment-configurable setup
looks like this:

```elixir
# lib/my_app/goth.ex
defmodule MyApp.Goth do
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(_args) do
    env_opts = Keyword.new(Application.get_env(:my_app, MyApp.Goth, []))
    opts = Keyword.merge([name: MyApp.Goth], env_opts)

    %{id: MyApp.Goth, start: {Goth, :start_link, [opts]}}
  end
end
```

```elixir
# config/config.exs
config :my_app, MyApp.Goth, source: {:metadata, []}

# config/test.exs
# Optional, for stubbing goth in test; requires a custom :http_client
# module/function per the Goth.start_link/1 documentation.
config :my_app, MyApp.Goth,
  source: {:metadata, []},
  http_client: {&MyAppTest.GothHttpClientStub.access_token_response/1, []}
```

```elixir
# lib/my_app/application.ex — add MyApp.Goth to your supervision tree
children = [
  # ...
  MyApp.Goth
  # ...
]
```

For other `:source` configurations, see
[`Goth.start_link/1`](https://hexdocs.pm/goth/Goth.html#start_link/1).

If you are still on Goth < 1.3, a compatibility fetcher,
`Waffle.Storage.Google.Token.GothTokenFetcher`, is compiled (only when
Goth < 1.3 is present) — set it as your `:token_fetcher` to keep the old
behavior. It is not available once you upgrade Goth.

### `bucket/1` overrides are now honored

Definitions can now select a bucket per file/scope, matching the S3 adapter:

```elixir
def bucket({_file, scope}), do: scope.bucket || bucket()
```

Previously this adapter always used `bucket/0` and silently ignored any
`bucket/1` override in your definition. Now `bucket/1` is called (with
`{file, scope}`) for uploads, deletes, and both public and signed URL
generation, falling back to `bucket/0` only when the definition doesn't
export it.

**Check before upgrading:** if any of your definitions define `bucket/1`
(perhaps copied from S3-oriented docs, or shared with an S3-backed app):

- If it returns something different from `bucket/0`, new uploads, deletes,
  and generated URLs will target that bucket after the upgrade — while
  previously uploaded objects remain in the `bucket/0` bucket. URLs for old
  files would then point at the wrong bucket. Either make `bucket/1` return
  the historical bucket for old records, or move/copy the old objects.
- If its clauses don't match the `{file, scope}` shape for every scope you
  store with, it can now raise `FunctionClauseError` at upload/URL time.
- During a rolling deploy, old nodes resolve via `bucket/0` while new nodes
  use `bucket/1`; if the two differ, writes briefly split across buckets.

Definitions without a `bucket/1` override are unaffected — waffle's default
`bucket/1` delegates to `bucket/0`.

### Content type is now inferred on upload

Objects uploaded without an explicit content type used to be stored as
`application/octet-stream` (so browsers downloaded images instead of
rendering them). Now `put/3` infers `contentType` from the filename via
`MIME.from_path/1` for both file and binary uploads.

- Headers set via `gcs_object_headers/2` keep precedence — if you already
  set a content type, nothing changes.
- Unknown extensions still fall back to `application/octet-stream`.
- If anything in your pipeline relied on new uploads being stored as
  `application/octet-stream`, set that explicitly in `gcs_object_headers/2`.
- Existing objects are not modified; only new uploads get the inferred type.

### Direct callers of `CloudStorage.put/3`

`put/3` no longer applies `filename/2` resolution internally; it joins the
storage dir with `file.file_name` as-is. Waffle resolves the version filename
before invoking the adapter, so uploads through `definition.store` are
unaffected (this is what fixes the doubled-filename bug, e.g.
`1_original_1_original_photo.png`).

If you call `Waffle.Storage.Google.CloudStorage.put/3` directly, pass the
final object name in `file.file_name` — it will no longer be re-resolved for
you. `path_for/3` and `fullname/3` are unchanged and still resolve names
exactly once.

## From v0.1.x to v0.2.0

- `waffle` moved from `0.0.3` to `~> 1.1`; follow waffle's own upgrade notes
  if you are coming from `arc`-era versions.
- Custom token generation became available via the
  `Waffle.Storage.Google.Token.Fetcher` behaviour and
  `config :waffle, :token_fetcher` (optional in 0.2.x).

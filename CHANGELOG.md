# Changelog

All notable changes to this project are documented in this file.

The format loosely follows [Common Changelog](https://common-changelog.org).
Breaking changes are marked **Breaking** — see [UPGRADING.md](UPGRADING.md)
for step-by-step upgrade instructions.

## [Unreleased]

### Changed

- **Breaking:** the Google client stack is replaced by a built-in minimal GCS
  JSON API client on [req](https://hex.pm/packages/req)
  ([#39](https://github.com/elixir-waffle/waffle_gcs/issues/39),
  [#32](https://github.com/elixir-waffle/waffle_gcs/issues/32)).
  `google_api_storage`, `google_gax`, `tesla`, and `poison` leave the
  dependency tree — including the tesla `1.18.2` pin and its five unfixable
  advisories — and `req`/`finch`/`mint` enter. `CloudStorage.put/3` returns
  `{:ok, %Waffle.Storage.Google.Object{}}` / `{:error, %Waffle.Storage.Google.Error{}}`
  (was `GoogleApi.Storage.V1.Model.Object` / `Tesla.Env`), `delete/3` returns
  `:ok` on success, and `CloudStorage.conn/0,1` is removed. The HTTP transport
  and JSON codec are configurable seams
  (`config :waffle_gcs, :transport` / `:json_codec`). See
  [UPGRADING.md](UPGRADING.md#new-gcs-client-result-types-and-removed-functions).
- **Breaking:** S3-style atom ACLs (`:public_read`, ...) now map to GCS's
  `predefinedAcl` upload parameter instead of being silently dropped —
  `@acl :public_read` actually makes objects public-readable;
  `:private`/`nil` send nothing (bucket default; compatible with uniform
  bucket-level access); unknown atoms raise
  ([#27](https://github.com/elixir-waffle/waffle_gcs/issues/27)). See
  [UPGRADING.md](UPGRADING.md#acl-atoms-now-work-and-unknown-ones-raise).
- **Breaking:** `config :waffle, :token_fetcher` is now required and
  `Waffle.Storage.Google.Token.DefaultFetcher` has been removed, adding
  official support for Goth >= 1.3 ([#2](https://github.com/elixir-waffle/waffle_gcs/pull/2))
  (Ulisses Almeida, @ulissesalmeida). A `GothTokenFetcher` is compiled only
  when Goth < 1.3 is present. See [UPGRADING.md](UPGRADING.md#goth--13-and-the-required-token_fetcher).
- **Breaking:** drop support for Elixir < 1.15 (`elixir: "~> 1.15"` in `mix.exs`)
- **Breaking:** `CloudStorage.put/3` no longer re-resolves the version
  filename; it joins the storage dir with `file.file_name` as-is, since Waffle
  resolves the name before calling the adapter. Fixes prefix-style
  `filename/2` results being applied twice (e.g. `1_original_1_original_photo.png`)
  ([#25](https://github.com/elixir-waffle/waffle_gcs/issues/25),
  [#1](https://github.com/elixir-waffle/waffle_gcs/pull/1),
  [#42](https://github.com/elixir-waffle/waffle_gcs/pull/42)). Only affects
  direct callers of `CloudStorage.put/3`; uploads via `definition.store` simply
  get the bug fix. `path_for/3` and `fullname/3` keep their resolving semantics.
- A definition's `bucket/1` callback (`bucket({file, scope})`) is now honored
  for uploads, deletes, and URL generation — matching the S3 adapter — with
  fallback to `bucket/0` when not exported
  ([#33](https://github.com/elixir-waffle/waffle_gcs/issues/33),
  [#46](https://github.com/elixir-waffle/waffle_gcs/pull/46)). **Behavior
  change** if a definition already overrides `bucket/1`: it was previously
  ignored by this adapter. See [UPGRADING.md](UPGRADING.md#bucket1-overrides-are-now-honored).
- Objects uploaded without an explicit content type in `gcs_object_headers/2`
  now get a `contentType` inferred from the filename via `MIME.from_path/1`
  instead of being stored as `application/octet-stream`
  ([#43](https://github.com/elixir-waffle/waffle_gcs/issues/43),
  [#45](https://github.com/elixir-waffle/waffle_gcs/pull/45)). Explicit headers
  keep precedence; unknown extensions still fall back to
  `application/octet-stream`.
- Bump `jose` from `1.10.1` to `1.11.12`
  ([#6](https://github.com/elixir-waffle/waffle_gcs/pull/6)) (Jim Kane, @fastjames)
- `mime` becomes a direct dependency, `~> 2.0.6 or ~> 2.1` (previously
  transitive, resolving to 1.x)
  ([#45](https://github.com/elixir-waffle/waffle_gcs/pull/45))
- Update repository links to `elixir-waffle/waffle_gcs`
  ([#3](https://github.com/elixir-waffle/waffle_gcs/pull/3))

### Fixed

- An exception raised inside a definition's `gcs_object_headers/2` or
  `gcs_optional_params/2` now propagates instead of being silently swallowed
  (which dropped all custom headers with no warning)
  ([#30](https://github.com/elixir-waffle/waffle_gcs/issues/30))
- Fix `resolve_file_name` being applied twice during `put`, which doubled
  prefix-style `filename/2` results in the stored object name
  ([#25](https://github.com/elixir-waffle/waffle_gcs/issues/25),
  [#1](https://github.com/elixir-waffle/waffle_gcs/pull/1),
  [#42](https://github.com/elixir-waffle/waffle_gcs/pull/42))
- Images and other well-known file types now render inline when served from
  GCS instead of downloading, because a content type is stored with the object
  ([#43](https://github.com/elixir-waffle/waffle_gcs/issues/43),
  [#45](https://github.com/elixir-waffle/waffle_gcs/pull/45))

## [0.2.0] - 2021-08-20

### Changed

- Bump `waffle` from `0.0.3` to `~> 1.1`
- Bump `google_api_storage` from `~> 0.12` to `~> 0.14`

### Added

- Initial support for custom token generation via the
  `Waffle.Storage.Google.Token.Fetcher` behaviour and the
  `config :waffle, :token_fetcher` option
- Allow custom GCS object headers with the `gcs_object_headers/2` definition
  callback

## [0.1.3] - 2023-02-02

_Retroactive tag (nash-io fork history)._

### Fixed

- Remove URL encoding when deleting objects, fixing `delete` for names that
  encode differently

## [0.1.2] - 2023-02-02

_Retroactive tag (nash-io fork history)._

### Changed

- Update `google_api_storage` to `0.34`

## [0.1.1] - 2019-09-27

_Initial tagged release of the `arc_gcs` port to Waffle._

[Unreleased]: https://github.com/elixir-waffle/waffle_gcs/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/elixir-waffle/waffle_gcs/compare/0.1.1...v0.2.0
[0.1.3]: https://github.com/elixir-waffle/waffle_gcs/releases/tag/0.1.3
[0.1.2]: https://github.com/elixir-waffle/waffle_gcs/releases/tag/0.1.2
[0.1.1]: https://github.com/elixir-waffle/waffle_gcs/releases/tag/0.1.1

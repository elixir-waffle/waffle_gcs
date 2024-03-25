# Changelog


## [0.2.1] - 2024-03-25

### Changed

- Update from `Mix.Config` to `Config` ([#4](https://github.com/elixir-waffle/waffle_gcs/pull/4)) (Rafael Scheffer, @rschef)
- Bump `google_api_storage` from `0.29` to `0.34` ([#4](https://github.com/elixir-waffle/waffle_gcs/pull/4)) (Rafael Scheffer, @rschef)
- Bump `waffle` from `1.1.5` to `1.1.8`
- Bump `ex_doc` from `0.25` to `0.31`
- Bump `dialyxir` from `1.1.0` to `1.4.3`


### Removed

- **Breaking:** drop maintenance support for Elixir versions `< v1.12`
- remove `Waffle.Storage.Google.CloudStorage.fullname/3` as it was a wrapper
  - Please use `Waffle.Definition.Versioning.resolve_file_name/3` directly instead


### Fixed
- fix `resolve_file_name` being called twice in certain scenarios [#1](https://github.com/elixir-waffle/waffle_gcs/pull/1)
  - remove `Waffle.Storage.Google.CloudStorage.fullname/3`. Please use `Waffle.Definition.Versioning.resolve_file_name/3` directly instead
  - changes `Waffle.Storage.Google.CloudStorage.path_for/3` to use the `:file_name` key


## [0.2.0] - 2021-08-20

### Changed
- Bump `waffle` from `0.0.3` to `1.1`
- Bump `google_api_storage` from `0.12` to `0.14`
### Added
- Initial support for custom token generation
- Allow custom GCS object headers w/ `gcs_object_headers/2` callback

---
#### References
- https://common-changelog.org

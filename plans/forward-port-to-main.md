# Forward-porting the double-filename fix + test overhaul into `main`

Status: written 2026-07-03 on branch `pkm/fix-double-filename` (cut from the
v0.2.x tag). This file lives under `plans/`, which is **not** in the `mix.exs`
`files:` whitelist, so it is excluded from the published hex package. It is safe
to commit to git.

> **Update 2026-07-03:** this is now step 0 of a larger plan set — see
> [plans/README.md](README.md) for the index and
> [plans/0.3-release.md](0.3-release.md) for everything else gating 0.3
> (GitHub milestone **v0.3**, issues #27–#37). The §4 gating question below is
> decided: **option (a)**, tracked as issue #33.

## Why this branch exists

`main` already carries PR #1 ("Fix resolve_file_name called twice"), which fixed
the double-filename bug (issue #25) by imitating the S3 adapter. Peter considers
that fix "not quite right." This branch, cut from v0.2.x, carries what we believe
is the **better fix** plus a from-scratch, bulletproof test suite. The goal of
this document is to make pulling both forward into `main` (which becomes 0.3)
low-risk and mechanical.

Two independent things need to move forward:

1. **The lib fix** — a small behavior change in `CloudStorage.put/3` /
   `path_for/3`. This is the actual reason for the branch.
2. **The test overhaul** — four clean commits that make the suite thorough and
   resilient. These are cleanly cherry-pickable, with the caveats below.

## Branch commits to move

| SHA (this branch) | Commit | Kind |
|---|---|---|
| `9bb1eef` | fix double filename calls while `put`'ing | lib fix **+ old test churn** (do NOT cherry-pick wholesale) |
| `6756769` | Add shared GCS test infrastructure | test |
| `394dbad` | Add feature-organized integration suite and #25 regression test | test |
| `8cc2eb7` | Slim cloud_storage_test to unit/module tests; drop legacy fixtures | test |
| `d9f3344` | Document test tag taxonomy and add offline-test tooling | test/tooling |

`9bb1eef` bundles the real lib change together with a large, now-superseded pile
of test edits. **Do not cherry-pick `9bb1eef` onto main.** Hand-apply the small
lib delta (below), then cherry-pick the four clean test commits.

## 1. The lib fix (the core change)

Both branches keep `put → delete → url` correct, but differ in *where* the
filename is resolved.

**`main` (PR #1):** `put/3` calls `path_for/3`, and `path_for/3` uses the
already-resolved `file.file_name` directly — it never calls `resolve_file_name`:

```elixir
def put(definition, version, meta) do
  path = path_for(definition, version, meta)
  ...

def path_for(definition, version, meta = {file, _scope}) do
  definition
  |> storage_dir(version, meta)
  |> Path.join(file.file_name)
end
```

The "not quite right" part: `path_for/3` no longer resolves the version filename
at all. Any caller that passes an unresolved file (i.e. anything other than the
post-`Store` path) gets a name that skipped `filename/2`.

**This branch (the better fix):** `put/3` bypasses `path_for/3` with a raw join
(Waffle has already resolved the name before calling the adapter), while
`path_for/3` *retains* its resolving semantics via a new `fullname/3` wrapper —
so `delete/3` and the URL builder (which both go through `path_for/3`) still
resolve exactly once:

```elixir
def put(definition, version, meta) do
  {file, _scope} = meta
  destination_dir = storage_dir(definition, version, meta)
  # Explicitly not `path_for`.
  # Waffle will have already called `Versioning.resolve_file_name` when calling `definition.store`
  path = Path.join(destination_dir, file.file_name)
  ...

def path_for(definition, version, meta) do
  definition
  |> storage_dir(version, meta)
  |> Path.join(fullname(definition, version, meta))
end

@doc "A wrapper for `Waffle.Definition.Versioning.resolve_file_name/3`."
def fullname(definition, version, meta) do
  Waffle.Definition.Versioning.resolve_file_name(definition, version, meta)
end
```

**Forward-port action:** in `main`'s `lib/waffle/storage/google/cloud_storage.ex`,
replace `put/3` and `path_for/3` with the branch versions and add `fullname/3`.
Nothing else in the module needs to change for the fix itself.

The double-filename regression test (`394dbad`) is what proves this is right and
stays right — see below.

## 2. Divergence trap: the token fetcher (do NOT drag it along)

`main` and the v0.2.x branch diverged on the Goth token fetcher, independently of
the double-filename fix. Keep them separate — don't let the forward-port quietly
swap main's token wiring.

| | `main` | this branch |
|---|---|---|
| `conn/1` | `Application.fetch_env!(:waffle, :token_fetcher)` (required) | `Application.get_env(:waffle, :token_fetcher, Token.DefaultFetcher)` (defaulted) |
| config | `token_fetcher: Waffle.GothTokenFetcher` | (unset; relies on default) |
| lib files | `token/fetcher.ex`, `token/goth_token_fetcher.ex` | `token/fetcher.ex`, `token/default_fetcher.ex` |

The test suite does **not** set `:token_fetcher`, so on `main` it will use main's
configured `Waffle.GothTokenFetcher` via `fetch_env!` — that's fine and requires
no change. **Do not** bring this branch's `conn/1` default, `token/default_fetcher.ex`,
or the config edit across unless you have separately decided to change main's
token story. It is orthogonal to issue #25.

## 3. Forward-porting the four test commits

Cherry-pick in order: `6756769` → `394dbad` → `8cc2eb7` → `d9f3344`.

**Fixture-image gotcha (found during execution):** the images the feature suite
references (`image two.png`, `image+three.png`, the updated `image.png`, and
`invalid_image.png`) live in `9bb1eef`, not in the four test commits. Pull them
across separately (`git checkout <sha> -- 'test/support/image*' ...`) before
running the suite.

What each brings, and what to watch:

- **`6756769` (shared infra):** adds `test/support/gcs_case.ex`
  (`Waffle.GCSCase`, an `ExUnit.CaseTemplate`) and
  `test/support/feature_definitions.ex` (single-purpose `GCSTest.*` defs +
  `GCSTest.FilenameProbe`). `main` already has `elixirc_paths(:test)` including
  `test/support`, so these compile. No conflicts expected — both files are new.

- **`394dbad` (integration suite + regression test):** adds
  `test/integration/gcs_features_test.exs` and
  `test/integration/double_filename_regression_test.exs`. New files, no conflict.
  The regression test drives `store` through `GCSTest.FilenameProbe` (which uses
  `@async false` so `send(self(), …)` from `filename/2` lands in the test
  process) and asserts the name resolves exactly once. **This is the guard for
  the §1 lib fix** — if main hasn't taken the lib fix yet, this test will fail
  (that's the point). Apply the lib fix first.

- **`8cc2eb7` (slim module tests + drop legacy fixtures):** overwrites
  `test/waffle/storage/google/cloud_storage_test.exs`, deletes
  `test/support/definitions.ex`, and repoints `test/support/cleanup.ex`'s
  teardown at `GCSTest.PublicUpload`. **Conflict risk here:** main's
  `cloud_storage_test.exs` and `cleanup.ex` differ, and `definitions.ex` on main
  may have content this branch never saw. Before applying, confirm nothing else
  in main's `test/` references `definitions.ex` (on this branch only the removed
  suites did; main has just `cloud_storage_test`, `util_test`, `url_v2_test`, and
  the last two don't use it). Resolve the overwrite by taking the branch version
  of `cloud_storage_test.exs` and the `GCSTest.PublicUpload` repoint in
  `cleanup.ex`.

- **`d9f3344` (taxonomy + tooling):** edits `test/test_helper.exs` (tag-taxonomy
  comment + version-gated exclude), `mix.exs` (adds `aliases/0` `test.unit` +
  `def cli` `preferred_envs`), and `README.md` (test docs). **Watch `mix.exs`:**
  main may already define `aliases/0`/`def cli`; merge rather than clobber. Also
  main's config uses `import Config` while this branch's `config/config.exs` still
  uses `use Mix.Config` — do not bring the branch's config file across.

## 4. The version-gating flip (most important behavioral gotcha)

`test/test_helper.exs` excludes `:bucket_with_file_and_scope` only while the lib
version is `< 0.3.0`:

```elixir
if Version.compare(lib_version, "0.3.0") == :lt do
  ExUnit.configure(exclude: [:bucket_with_file_and_scope])
end
```

That test (`GCSTest.WithBucketInScope`, "bucket/1 selects bucket from scope") is
tagged `upstream_mismatch` because **bucket-from-scope is not implemented** — it
currently returns the default bucket instead of the scope's. On this branch
(0.2.0) it is excluded and the suite is green.

**When `main` bumps to 0.3.0, this exclude stops applying and the test runs — and
fails.** Before cutting 0.3 you must either:

- **(a)** implement `bucket/1`-from-scope so `CloudStorage.bucket/1` honors a
  `bucket({file, scope})` definition callback (the real 0.3 feature), or
- **(b)** keep the test excluded by moving the tag to an unconditional
  `exclude:` (and note it as known-unsupported), or
- **(c)** raise the version threshold in the guard.

Option (a) is the intended 0.3 work; (b)/(c) are stopgaps. Decide deliberately —
don't let a green 0.2 suite lull you into a red 0.3 suite on the first `mix test`.

**Decided: option (a)** — implement bucket-from-scope, tracked in issue #33.
`WAFFLE_BUCKET2` has been added to the GHA repository secrets, so CI can run
the two-bucket test once the workflow passes it through (issue #36).

Related: several `@tag skip: "..."` tests encode "correct but not-yet-supported"
behavior (definition-level `asset_host`, `{:system}`/`false` asset_host,
plus-sign URL escaping). `skip:` **cannot** be re-enabled from the CLI. When you
start 0.3, convert the future-behavior skips into named exclude tags (like
`:bucket_with_file_and_scope`) so they can be toggled with `--include`.

## 5. Verification after forward-porting

Requires GCS creds (integration tests hit real GCS). Do not commit these:

```
export WAFFLE_BUCKET=<your test bucket>
export WAFFLE_BUCKET2=<your second test bucket>
export GCP_CREDENTIALS="$(cat /path/to/service-account.json)"
```

Then:

1. `mix test.unit` (== `mix test --exclude integration`) — fast offline units
   compile and pass. (Note: Goth auto-starts and needs creds even for unit runs;
   if so, run `mix test --exclude integration` with creds set.)
2. `mix test --include double_filename_regression` — the regression test passes
   **only if the §1 lib fix is applied**. To prove it bites, temporarily revert
   `put/3` to `path = path_for(...)`, confirm it fails on `refute_received`, then
   restore.
3. `mix test` — full suite green (0 failures). Confirm the after-suite cleanup
   left no stray objects in the bucket.
4. `mix test --only bucket_with_file_and_scope` — runs the 0.3-gated test; expect
   the documented `upstream_mismatch` failure until bucket/1-from-scope is
   implemented. Confirms the include/exclude toggle works.
5. Sanity: `grep -rn IO.inspect test/` is empty, and `grep -rln "defmacro assert_"
   test/` returns only `gcs_case.ex`.
6. `mix hex.build` (dry run) — confirm `plans/` is absent from the packaged file
   list (it is excluded by the `files:` whitelist).

## Quick checklist

- [ ] Hand-apply the `put/3` + `path_for/3` + `fullname/3` lib delta to main (§1).
- [ ] Decide the token-fetcher story deliberately; keep it separate (§2).
- [ ] Cherry-pick `6756769`, `394dbad`, `8cc2eb7`, `d9f3344` in order (§3).
- [ ] Merge (don't clobber) main's `mix.exs`; keep main's `import Config` (§3).
- [ ] Resolve the 0.3 version-gating flip for `:bucket_with_file_and_scope` (§4)
      — decided: implement bucket-from-scope, issue #33.
- [ ] Convert future-behavior `skip:` tags to exclude tags for 0.3 (§4).
- [ ] Run the full verification (§5).
- [ ] Continue with [0.3-release.md](0.3-release.md) (milestone v0.3).

# Offline contract test suite

Status: written 2026-07-03. Tracking issue: #38. Comes **after** the 0.3
test-gap work (#37) and before the client rewrite (#39) can start.

## Why

Today every behavioral test requires live GCS creds. The offline "unit" tests
only cover string construction (`path_for`, URL shapes, `Util`). Consequence:
`mix test.unit` passes no matter what you break in the HTTP layer, and CI can't
protect fork PRs at all (secrets don't flow to forks). A confident refactor of
the client internals — the whole point of the roadmap — is impossible under
that regime.

## Sequencing — honest about trust

Real-GCS testing is the only thing that has ever produced confidence in this
codebase. That stays true until proven otherwise:

1. **Trustworthy live suite first.** The #37 checklist lands; the live suite
   is the behavioral spec.
2. **Dual-target, don't fork.** The offline target runs the *same* feature
   suite (`test/integration/gcs_features_test.exs` + regression test) against
   [fsouza/fake-gcs-server](https://github.com/fsouza/fake-gcs-server) in
   docker. No parallel "mock suite" that can drift — one suite, two targets,
   selected by tag/env.
3. **Overlap period.** Both targets run in CI. Divergences either expose fake
   limitations (document + tag `:live_only`) or real bugs (fix). Expected
   `:live_only` candidates: ACL fidelity (`assert_acls_public_reader`),
   signed-URL server-side validation, 403-vs-404 semantics on deleted objects.
4. **Flip the gate.** Once stable: offline suite is the required check on every
   PR (forks included, zero secrets); live suite runs on push to `main` and
   before releases. Live remains the source of truth; offline is the tripwire.

## Mechanics

### Retargeting the current client (no dep forking needed)

google_gax's generated `Connection.new/1` returns a `Tesla.client` whose
per-client middleware runs **before** the module-level plugs, and
`Tesla.Middleware.BaseUrl` skips URLs that are already absolute. So a test-mode
connection can inject its own base URL ahead of the module's:

```elixir
# test-only conn: prepends BaseUrl so the module-level one no-ops
Tesla.client([
  {Tesla.Middleware.BaseUrl, System.get_env("GCS_ENDPOINT", "https://storage.googleapis.com")},
  {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]}
])
```

Verify the skip behavior once (one unit test against a Bypass) before relying
on it. Fallback: `config :google_api_storage, :base_url` — but that's read at
**dep compile time** (it's inside the generated `plug`), so it needs a forced
`mix deps.compile google_api_storage` in the offline CI job. The middleware
injection is cleaner.

Token handling offline: fake-gcs-server ignores auth — a static
`"test-token"` fetcher (via the existing `Token.Fetcher` behaviour) removes the
Goth dependency from offline runs entirely. This also removes the "Goth
auto-starts and needs creds even for unit runs" wart noted in
forward-port-to-main.md §5.

### Pure request builders (do this regardless)

Extract request construction into pure functions returning data — object name,
acl/predefinedAcl mapping (#27), headers merge, multipart-vs-iodata choice —
and unit-test them exhaustively with no network at all. This is the same seam
the client rewrite's transport layer needs
([client-rewrite.md](client-rewrite.md)); building it here means the rewrite
inherits tests instead of writing them.

### What the fake can't cover

- **Signature validity** → deterministic signing vectors (#37 item 4): fixed
  PEM + fixed expiration → exact expected signature string. When the v4 signer
  (#14) lands, same pattern with Google's published v4 test vectors.
- **Real ACL/IAM semantics, UBLA rejection** → stays `:live_only`.

## CI shape when done

| Job | Trigger | Needs secrets |
|---|---|---|
| unit + offline feature suite (fake-gcs-server service container) | every PR, incl. forks | no |
| live feature suite (`WAFFLE_BUCKET`, `WAFFLE_BUCKET2`, `GCP_CREDENTIALS`) | push to `main`, release tags | yes |

## Definition of done

A fork PR with zero secrets runs the full feature suite green against
fake-gcs-server, and a deliberately-introduced bug in `put/3` request
construction fails it.

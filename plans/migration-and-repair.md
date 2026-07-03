# Migration & repair tooling

Status: written 2026-07-03. Tracking issue: #40 (complements #20 "Add migration
docs" and #25 "Double filename"). Timing: any time after 0.3 ships — it runs on
the existing Google deps, so it is *not* blocked on the client rewrite (#39).

## Who is damaged, and how

Through the entire released v0.2.x line, `CloudStorage.put/3` re-resolved an
already-resolved filename (#25). Affected: any consumer whose `filename/2`
derives the name from `file.file_name` *plus* a prefix — the canonical
waffle-documented pattern:

```elixir
def filename(version, {file, scope}) do
  name = Path.basename(file.file_name, Path.extname(file.file_name))
  "#{scope.id}_#{version}_#{name}"
end
```

Their objects are stored under **doubled** names
(`1_original_1_original_photo.png`) while their DB rows hold the original
filename. Everything *works* for them today because `url/2` also
double-resolves — the broken write and broken read cancel out. **Which means
the 0.3 fix breaks their reads**: correct URL generation now points at
single-prefix names that don't exist in the bucket. This is why "just upgrade"
is not an answer and the release needs repair tooling + a loud migration guide.
Consumers won't risk their data on a vibes-based upgrade — correctly so.

Definitions whose `filename/2` ignores `file.file_name` (e.g. constant
`"thumb"`-style names) resolve idempotently and are unaffected. The guide must
help people classify themselves.

## Deliverable 1: `mix waffle_gcs.repair`

A bucket-repair task, shaped by these rules:

- **Dry-run is the default.** `mix waffle_gcs.repair --definition MyApp.Avatar --prefix uploads/`
  prints the `from → to` plan and a summary count. `--apply` executes.
- **Detection is definition-driven, not regex-guessing.** The task loads the
  user's definition, computes what `filename/2` produces for a given stored
  name, and checks whether stripping one application of the prefix yields a
  fixed point. A naive `^(.+)_\1` regex would false-positive on legitimately
  doubled-looking names — and false positives here rename user data.
- **Server-side `objects.rewrite`**, never download/re-upload. Verify the
  destination object (size/md5) before deleting the source.
- **Idempotent and resumable.** Re-running skips already-correct names;
  interruption mid-run leaves no half-state worse than "some files already
  repaired" (copy-then-delete ordering guarantees this).
- **`--check` mode** for the migration guide: "is my bucket affected?" without
  proposing changes.
- ACL preservation: `rewrite` copies metadata, but verify ACL behavior on
  fine-grained buckets explicitly in tests (UBLA buckets have nothing to
  preserve).

Test story: seed a bucket (fake-gcs-server once #38 lands; live before then)
with doubled names, non-doubled names, and adversarial lookalikes; assert the
plan, then the applied result, then idempotence of a second run.

## Deliverable 2: Igniter tasks

For host-app config surgery that docs alone get wrong:

- `mix waffle_gcs.install` — inject `config :waffle, storage: ..., bucket: ...`
  and the token setup chosen in #34 (Goth child spec + `goth_server` config,
  or legacy `config :goth, json:`), detecting which Goth generation the app
  uses.
- An `igniter.upgrade` hook for 0.2 → 0.3: apply config renames, print a
  pointed warning if the app's definitions match the affected-`filename/2`
  shape, linking the repair task.

Igniter is a dev-only dependency question — likely `optional: true` or a
separate `waffle_gcs_igniter` package so the core lib stays dep-light.

## Deliverable 3: the migration guide

Lives in the repo docs and the changelog (#8), and closes #20:

1. **Am I affected?** — the `filename/2` self-classification + `--check`.
2. **Upgrade order** — pin 0.2.x → run `--check` → upgrade to 0.3 in a branch →
   run repair dry-run → `--apply` during a low-traffic window → verify reads →
   deploy. (Reads through old doubled URLs keep working until repair runs,
   because 0.2 in prod still double-resolves; the danger window is *new 0.3
   code + unrepaired bucket*, so the guide must order deploy-after-repair.)
3. **Token config changes** (#34) with before/after config blocks per Goth
   generation.
4. **ACL changes** (#27): what `@acl :public_read` does now vs. the silent
   nothing it did before; UBLA guidance.

## Open questions

- Should repair also fix DB references for people whose workaround was storing
  doubled names in the DB? (Probably out of scope — document the situation,
  provide the mapping dump via `--plan-csv` so they can script their own.)
- Multi-tenant buckets with several definitions sharing a prefix: require
  `--definition` per run; refuse ambiguous prefixes.

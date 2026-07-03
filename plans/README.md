# Plans index

Written 2026-07-03, distilled from a full review of the library and test suite
(branch `pkm/fix-double-filename`). `plans/` is not in the `mix.exs` `files:`
whitelist, so none of this ships in the hex package.

The overall arc: **0.2 (released, buggy) → 0.3 (fix + hardened contract) →
offline test suite → client rewrite → repair/migration tooling.** Each stage is
a gate for the next; nothing later starts until the stage before it holds.

| Plan | What it covers | Milestone / issues |
|---|---|---|
| [forward-port-to-main.md](forward-port-to-main.md) | Mechanically moving the double-filename fix (#25) + test overhaul from this branch onto `main` | precursor to everything |
| [0.3-release.md](0.3-release.md) | Everything gating the 0.3 release: lib fixes, token decision, test-infra hazards, test-gap checklist, release mechanics | milestone **v0.3** — #27 #28 #29 #30 #31 #32 #33 #34 #35 #36 #37 (+ #8) |
| [offline-test-suite.md](offline-test-suite.md) | Dual-targeting the feature suite at fake-gcs-server so refactors are CI-protected without creds | #38 |
| [client-rewrite.md](client-rewrite.md) | Replacing google_api_storage/google_gax/legacy-Goth with a minimal hand-rolled client; swappable transport, signer-as-adapter, token seam | #39 (+ #14, #16, #18) |
| [migration-and-repair.md](migration-and-repair.md) | `mix waffle_gcs.repair` for doubled filenames, igniter tasks, migration guides | #40 (+ #20, #25) |

## Sequencing rules

1. **0.3 ships on the current Google deps.** The rewrite is not coupled to 0.3;
   0.3's job is to fix behavior and freeze the consumer contract.
2. **Live-creds tests remain the source of truth** until the offline suite
   (#38) has run green alongside them long enough to be trusted. Confidence in
   this codebase has only ever come from real GCS; that doesn't change by fiat.
3. **The rewrite (#39) starts only after** the error contract is library-owned
   (#32) and the offline suite is the enforced PR gate (#38). At that point the
   feature suite *is* the spec, and the rewrite happens under it.
4. **Repair tooling (#40) is independent** — it can ship any time after 0.3 on
   the existing deps, since it's a dev-time mix task.

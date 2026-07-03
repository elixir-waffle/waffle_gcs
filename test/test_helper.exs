# ── Tag taxonomy ─────────────────────────────────────────────────────────────
#
# :integration
#     Hits real Google Cloud Storage. Requires WAFFLE_BUCKET + GCP_CREDENTIALS
#     (and WAFFLE_BUCKET2 for the bucket-from-scope test). Applied to every test
#     module that `use Waffle.GCSCase`. Run only the fast offline units with
#     `mix test --exclude integration`.
#
# :tmp_dir
#     Opts into ExUnit's per-test temp directory (used by GCSCase to stage a
#     unique fixture upload per test).
#
# :bucket_with_file_and_scope
#     A 0.3 behavior (bucket/1 selected from the scope) not yet supported in
#     0.2.x. Excluded below when the lib version is < 0.3.0. Run it explicitly
#     with `mix test --include bucket_with_file_and_scope`.
#
# double_filename_regression: "..."
#     The guard for issue #25 (filename/2 must be resolved exactly once per
#     version during put). Run it explicitly with
#     `mix test --include double_filename_regression`.
#
# skip: "..."
#     Truly inert tests: deprecated APIs, or S3-specific behavior that doesn't
#     apply to GCS. NOTE: `skip` cannot be re-enabled from the CLI — when 0.3
#     work begins, future-behavior `skip`s should become exclude tags (like
#     :bucket_with_file_and_scope) so they can be toggled with `--include`.
#
# upstream_mismatch: "..."
#     Informational marker for divergence from the upstream Waffle S3/Local
#     adapters (a parity bug to reconcile later). Always paired with a `skip` or
#     an exclude tag so the suite stays green.
# ─────────────────────────────────────────────────────────────────────────────

lib_version = Mix.Project.config() |> Keyword.fetch!(:version)

# Tags for tests that are to be ignored for 0.2.x versions for one reason or another.
# See the individual tag for more information.
excludes_for_0_2_x = [
  :bucket_with_file_and_scope
]

if Version.compare(lib_version, "0.3.0") == :lt do
  ExUnit.configure(exclude: excludes_for_0_2_x)
end

ExUnit.start()

# The `after_suite/1` function was added in Elixir version 1.8.0
if Version.compare(System.version(), "1.8.0") != :lt do
  ExUnit.after_suite(&Cleanup.execute/1)
end

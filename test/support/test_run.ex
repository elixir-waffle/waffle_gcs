defmodule GCSTest.Run do
  @moduledoc """
  Per-run isolation for GCS test objects.

  Every test definition stores under `#{inspect(__MODULE__)}.storage_dir/0`
  (`uploads/<run id>`), so concurrent runs sharing a bucket — e.g. parallel CI
  matrix jobs — never touch each other's objects, and the after-suite cleanup
  (`Cleanup`) deletes only this run's prefix, never the whole bucket.

  The id comes from `WAFFLE_TEST_RUN_ID` when set (CI should set it to
  something job-unique, e.g. `<run id>-<matrix index>`); otherwise
  `test_helper.exs` generates a random one for the local run. Objects from
  runs that crashed before cleanup accumulate under their own prefixes —
  give test buckets a short lifecycle TTL to sweep those.
  """

  def id, do: System.fetch_env!("WAFFLE_TEST_RUN_ID")

  def storage_dir, do: "uploads/#{id()}"
end

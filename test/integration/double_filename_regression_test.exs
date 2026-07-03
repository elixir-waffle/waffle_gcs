defmodule Waffle.Integration.DoubleFilenameRegressionTest do
  # Regression guard for issue #25 ("double filename"): a definition whose
  # `filename/2` prepends a scope/version prefix must have that name resolved
  # exactly ONCE per version during `store`. The original bug had
  # `CloudStorage.put/3` re-resolve the (already-resolved) name via `path_for/3`,
  # producing `1_original_1_original_image.png`.
  #
  # `GCSTest.FilenameProbe.filename/2` sends `{:filename_resolved, version}` on each
  # call, so a buggy adapter shows up as a second message (and a doubled name).
  use Waffle.GCSCase

  @tag double_filename_regression: "issue #25 - filename/2 must be resolved exactly once per version during put"
  @tag timeout: 15_000
  test "filename/2 is resolved exactly once and the stored name is not doubled", meta do
    scope = %{id: 1}

    assert {:ok, name} = GCSTest.FilenameProbe.store({meta.tmp_path, scope})

    # Resolved exactly once for :original — a re-resolving `put` would send a second.
    # (Assert before any `url/2` call, which resolves the name again.)
    assert_received {:filename_resolved, :original}
    refute_received {:filename_resolved, _}

    # The stored name carries a single prefix, not a doubled one.
    assert name == meta.unique_basename <> ".png"

    assert GCSTest.FilenameProbe.url({name, scope}) ==
             "#{bucket_url()}/uploads/1_original_#{name}"

    assert_public(GCSTest.FilenameProbe, {name, scope})
    delete_and_assert_gone(GCSTest.FilenameProbe, {name, scope})
  end
end

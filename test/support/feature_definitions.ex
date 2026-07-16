# Focused, single-purpose Waffle definitions for integration tests.
# Each module tests exactly one feature — no multi-behavior overloading.
# All of them store under the per-run prefix (GCSTest.Run.storage_dir/0) so
# concurrent runs sharing a bucket stay isolated and cleanup stays scoped.

defmodule GCSTest.PublicUpload do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
end

defmodule GCSTest.PrivateUpload do
  use Waffle.Definition
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
end

defmodule GCSTest.WithContentType do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def gcs_object_headers(:original, _), do: %{contentType: "image/gif"}
  def gcs_object_headers(_, _), do: []
end

defmodule GCSTest.WithKeywordHeaders do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  # Same as GCSTest.WithContentType but returning a keyword list — both
  # shapes are documented as supported for gcs_object_headers/2.
  def gcs_object_headers(:original, _), do: [contentType: "image/gif"]
  def gcs_object_headers(_, _), do: []
end

defmodule GCSTest.WithOptionalParams do
  use Waffle.Definition
  # Deliberately no @acl: public access must come solely from the
  # predefinedAcl optional param reaching the API.
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def gcs_optional_params(_, _), do: [predefinedAcl: "publicRead"]
end

defmodule GCSTest.WithContentDisposition do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  def gcs_object_headers(:original, _),
    do: %{contentDisposition: "attachment; filename=\"abc.png\""}

  def gcs_object_headers(_, _), do: []
end

defmodule GCSTest.WithCustomFilename do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  def filename(_version, {file, scope}) do
    file_name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope.id}_#{file_name}"
  end
end

defmodule GCSTest.WithVersions do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  @versions [:original, :thumb]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  def transform(:thumb, _) do
    {"convert", "-strip -thumbnail 100x100^ -gravity center -extent 100x100 -format jpg", :jpg}
  end
end

defmodule GCSTest.WithSkippedVersion do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  @versions [:skipped]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def transform(:skipped, _), do: :skip
end

defmodule GCSTest.WithScopedDir do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, {_, scope}), do: "#{GCSTest.Run.storage_dir()}/scoped/#{scope.id}"
end

defmodule GCSTest.WithBucket do
  use Waffle.Definition
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def bucket, do: System.fetch_env!("WAFFLE_BUCKET")
end

defmodule GCSTest.WithAssetHost do
  use Waffle.Definition
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def asset_host, do: "cdn.example.com"
end

defmodule GCSTest.InvalidBucket do
  use Waffle.Definition
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def bucket, do: "invalid"
end

defmodule GCSTest.WithMultiVersionFilename do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  @versions [:original, :thumb]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  def filename(version, {file, scope}) do
    file_name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope.id}_#{version}_#{file_name}"
  end
end

defmodule GCSTest.WithBucketInScope do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()
  def bucket({_, scope}), do: scope[:bucket] || bucket()
  def bucket, do: System.fetch_env!("WAFFLE_BUCKET")
end

# Regression probe for issue #25 ("double filename"). `filename/2` announces every
# invocation to the calling process so a test can assert it's resolved exactly once
# per version during `store`. `@async false` (the documented switch — see
# `Waffle.Definition.Storage`) keeps version processing in the test process so the
# `send(self(), ...)` lands in the test's mailbox rather than a Task's.
defmodule GCSTest.FilenameProbe do
  use Waffle.Definition
  @acl [%{entity: "allUsers", role: "READER"}]
  @async false
  def storage_dir(_, _), do: GCSTest.Run.storage_dir()

  def filename(version, {file, scope}) do
    send(self(), {:filename_resolved, version})
    base = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope.id}_#{version}_#{base}"
  end
end

defmodule DummyDefBase do
  defmacro __using__(_) do
    quote do
      use Waffle.Definition

      def acl(_, {_, :private}), do: :private

      def filename(_, {file, :private}),
        do: Path.basename(file.file_name, Path.extname(file.file_name))

      def filename(_, {_, name}) when is_binary(name), do: name

      def storage_dir(_, _), do: "waffle-gcs-test"

      defoverridable acl: 2, filename: 2, storage_dir: 2
    end
  end
end

defmodule DummyDefinition do
  use DummyDefBase
end

defmodule DummyDefinitionInvalidBucket do
  use DummyDefBase

  def bucket(), do: "invalid"
end

defmodule NewDummyDefinition do
  use Waffle.Definition

  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, _), do: "waffle-gcs-test/uploads"
  def acl(_, {_, :private}), do: :private |> IO.inspect(label: "HERE")

  def gcs_object_headers(:original, {_, :with_content_type}),
    do: %{contentType: "image/gif"}

  def gcs_object_headers(:original, {_, :with_content_disposition}),
    do:
      %{contentDisposition: "attachment; filename=\"abc.png\""}
      |> IO.inspect()

  def gcs_object_headers(_, _), do: []
end

defmodule DefinitionWithConcatenatedFilename do
  use Waffle.Definition

  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]

  @versions [:original, :thumb]

  # From Waffle docs:
  # To retain the original filename, but prefix the version and user id:
  def filename(version, {file, scope}) do
    file_name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope.id}_#{version}_#{file_name}"
  end
end

defmodule DefinitionWithThumbnail do
  use Waffle.Definition
  @versions [:thumb]
  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]

  def transform(:thumb, _) do
    {"convert", "-strip -thumbnail 100x100^ -gravity center -extent 100x100 -format jpg", :jpg}
  end
end

defmodule DefinitionWithSkipped do
  use Waffle.Definition
  @versions [:skipped]
  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]

  def transform(:skipped, _), do: :skip
end

defmodule DefinitionWithScope do
  use Waffle.Definition
  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]
  def storage_dir(_, {_, scope}), do: "waffle-gcs-test/uploads/with_scopes/#{scope.id}"
end

defmodule DefinitionWithBucket do
  use Waffle.Definition
  def bucket, do: System.fetch_env!("WAFFLE_BUCKET")
end

defmodule DefinitionWithBucketInScope do
  use Waffle.Definition
  # @acl :public_read
  @acl [%{entity: "allUsers", role: "READER"}]
  def bucket({_, scope}), do: scope[:bucket] || bucket() |> IO.inspect(label: :bucket)
  def bucket, do: System.fetch_env!("WAFFLE_BUCKET")
end

defmodule DefinitionWithAssetHost do
  use Waffle.Definition
  def asset_host, do: "https://example.com"
end

defmodule DummyDefBase do
  defmacro __using__(_) do
    quote do
      use Waffle.Definition

      def acl(_, {_, :private}), do: :private

      def filename(_, {file, :private}),
        do: Path.basename(file.file_name, Path.extname(file.file_name))

      def filename(_, {_, name}) when is_binary(name), do: name

      def storage_dir(_, _), do: "waffle-test"

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

defmodule DummyDefinitionBrokenObjectHeaders do
  use DummyDefBase

  def gcs_object_headers(_version, _meta), do: missing_header_function()
end

defmodule DummyDefinitionBrokenOptionalParams do
  use DummyDefBase

  def gcs_optional_params(_version, _meta), do: missing_optional_params_function()
end

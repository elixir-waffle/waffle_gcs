alias Waffle.Storage.Google.Client

defmodule Cleanup do
  @moduledoc """
  After-suite cleanup, registered in `test_helper.exs`.

  Deletes only the objects under this run's prefix (`GCSTest.Run.storage_dir/0`)
  — never the whole bucket, which may be shared with concurrent runs. Skipped
  entirely when the run excluded `:integration` (nothing was uploaded) or when
  credentials are absent (offline runs must not need network or creds).
  """

  def execute(_results) do
    cond do
      :integration in ExUnit.configuration()[:exclude] ->
        :ok

      System.get_env("GCP_CREDENTIALS") in [nil, ""] ->
        :ok

      true ->
        prefix = GCSTest.Run.storage_dir()

        Enum.reduce(buckets(), [], fn bucket, errors ->
          delete_from_bucket(bucket, prefix, errors, nil)
        end)
    end
  end

  # The primary bucket plus, when configured, the second bucket used by the
  # bucket-from-scope test.
  defp buckets do
    ["WAFFLE_BUCKET", "WAFFLE_BUCKET2"]
    |> Enum.map(&System.get_env/1)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  def delete_from_bucket(bucket, prefix, errors, page) do
    query = [prefix: prefix] ++ if page, do: [pageToken: page], else: []

    case Client.list(bucket, query: query) do
      {:ok, listing} -> delete_objects(bucket, prefix, errors, listing)
      {:error, error} -> [error | errors]
    end
  end

  def delete_objects(_bucket, _prefix, errors, %{items: []}), do: errors

  def delete_objects(bucket, prefix, errors, %{items: items, next_page_token: next}) do
    errors =
      Enum.reduce(items, errors, fn %{name: name}, errs ->
        case Client.delete(bucket, name) do
          :ok -> errs
          {:error, err} -> [err | errs]
        end
      end)

    case next do
      nil -> errors
      _ -> delete_from_bucket(bucket, prefix, errors, next)
    end
  end
end

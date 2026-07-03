alias Waffle.Storage.Google.CloudStorage
alias GoogleApi.Storage.V1.Api.Objects

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
        conn = CloudStorage.conn()
        prefix = GCSTest.Run.storage_dir()

        Enum.reduce(buckets(), [], fn bucket, errors ->
          delete_from_bucket(conn, bucket, prefix, errors, nil)
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

  def delete_from_bucket(conn, bucket, prefix, errors, page) do
    case Objects.storage_objects_list(conn, bucket, prefix: prefix, pageToken: page) do
      {:ok, objects} -> delete_objects(conn, bucket, prefix, errors, objects)
      {:error, error} -> [error | errors]
    end
  end

  def delete_objects(_conn, _bucket, _prefix, errors, %{items: []}), do: errors
  def delete_objects(_conn, _bucket, _prefix, errors, %{items: nil}), do: errors

  def delete_objects(conn, bucket, prefix, errors, %{items: items, nextPageToken: next}) do
    errors =
      Enum.reduce(items, errors, fn %{name: name}, errs ->
        case Objects.storage_objects_delete(conn, bucket, name) do
          {:ok, _} -> errs
          {:error, err} -> [err | errs]
        end
      end)

    case next do
      nil -> errors
      _ -> delete_from_bucket(conn, bucket, prefix, errors, next)
    end
  end
end

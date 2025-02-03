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

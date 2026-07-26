# Dependency-version blends for CI/local testing. Deps a blend doesn't pin
# float to the newest versions the requirements allow, so every blend except
# `oldest` also exercises newer-than-locked transitive deps.
#
# Blends resolving goth < 1.3 run the offline units minus the
# :goth_config_swap tests; test_helper.exs excludes those (plus :integration)
# automatically. Removing a blend is just: delete its entry here, run
# `mix blend.get`, delete blend/<name>/, and drop it from any CI matrix.
#
# tesla resolves to 1.18.2 in every blend via the pin in mix.exs.
#
#   oldest        - every direct dep at the floor mix.exs declares. waffle
#                   1.1.0 predates the bucket/1 definition callback (added in
#                   waffle 1.1.7), so this also exercises the bucket/0
#                   fallback for real. goth 1.1 predates the Goth 1.3 API.
#   goth_1_2      - last pre-1.3 goth against otherwise-current deps; compiles
#                   Waffle.Storage.Google.Token.GothTokenFetcher, which the
#                   main lock (goth 1.4) never compiles.
#   waffle_1_1_10 - newest waffle (main lock pins 1.1.8).
#   gcs_0_46      - newest google_api_storage (main lock pins 0.37).
#   mime_2        - the "~> 2.0" half of our mime requirement. Only resolvable
#                   with google_gax 0.4.0 (0.4.1 pins mime ~> 1.0).
%{
  oldest: [
    {:waffle, "1.1.0"},
    {:goth, "1.1.0"},
    {:google_api_storage, "0.34.0"},
    {:mime, "1.2.0"}
  ],
  goth_1_2: [{:goth, "1.2.0"}],
  waffle_1_1_10: [{:waffle, "1.1.10"}],
  gcs_0_46: [{:google_api_storage, "0.46.1"}],
  mime_2: [{:mime, "~> 2.0"}]
}

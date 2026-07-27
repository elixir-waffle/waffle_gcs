import Config

# goth < 1.3 (the old-goth blends in blend.exs) parses :json eagerly at app
# boot and crashes when GCP_CREDENTIALS is unset, so credential-less runs
# (e.g. `BLEND=oldest mix run ...`) get a parseable placeholder identity.
# Delete this block when the goth requirement moves past 1.3.
if System.get_env("GCP_CREDENTIALS") in [nil, ""] do
  config :goth,
    json: """
    {"type":"service_account","project_id":"offline-placeholder",
     "private_key_id":"0","private_key":"","client_id":"0",
     "client_email":"offline-placeholder@example.com",
     "token_uri":"https://oauth2.googleapis.com/token"}
    """
end

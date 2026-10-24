class_name SupabaseConfig
## Central Supabase configuration for SandEE.
##
## This is the ONLY place the project URL and client key are defined. Game code
## must go through the `Supabase` autoload (res://scripts/supabase_client.gd)
## instead of hard-coding endpoints or keys.
##
## Security notes:
##   * `PUBLISHABLE_KEY` is the Supabase *publishable* key. It is safe to ship in
##     the game because every request is constrained by Row Level Security and
##     column grants (see supabase/migrations/*.sql).
##   * Never add a secret/service-role key, JWT signing secret or database
##     password to this file, to any other script, or to an exported build.
##   * `profiles.email` is deliberately not granted to client roles; only the
##     `login-with-username` Edge Function (service role) can read it.
##   * Star totals are only changed by the `claim_reward()` SQL function, never
##     by direct table updates from the client.

const PROJECT_URL := "https://rqwtontlatcxrtimreng.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_b9nOrKvJGbGI2bqTMwUeFg_E2eMGSv-"

## Private, non-deliverable domain for the synthetic Supabase account identifier.
## The game collects only a username + password; Supabase Auth still needs an
## email-shaped identifier, so it is derived from the username as
## `<lowercase username>@users.sandee.invalid`. `.invalid` is reserved by
## RFC 2606 and can never receive mail.
const ACCOUNT_EMAIL_DOMAIN := "users.sandee.invalid"

## Private Storage bucket for cloud saves (objects live at `<user_id>/<slot>.json`).
const CLOUD_SAVE_BUCKET := "cloud-saves"
## Hard limit on cloud-save slots (the UI offers a replacement chooser when full).
const CLOUD_SAVE_LIMIT := 5

## Where the local session (access/refresh token) is cached between launches.
## `user://` is not part of the repository or the exported PCK. The client
## encrypts this file with an AES-256 key derived from the device identity
## (see supabase_client.gd) instead of writing tokens as plaintext JSON.
const SESSION_PATH := "user://supabase_session.bin"

## Legacy plaintext session file, removed on the next launch.
const LEGACY_SESSION_PATH := "user://supabase_session.json"

## Network timeout for a single request, in seconds.
const TIMEOUT_SEC := 20.0

## Short timeout used by the startup connectivity checks.
const PING_TIMEOUT_SEC := 6.0

## Secondary host used to tell "no internet" apart from "Supabase is down".
## Any HTTP response from it means the device has internet access.
const INTERNET_PROBE_URL := "https://www.cloudflare.com/cdn-cgi/trace"

## Refresh the session this many seconds before the access token expires.
const REFRESH_MARGIN_SEC := 60.0

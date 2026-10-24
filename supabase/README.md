# SandEE cloud backend (Supabase)

This folder is the single source of truth for SandEE's Supabase project: schema
migrations, the `login-with-username` Edge Function, and the CLI configuration.
The Godot client talks to it through one autoload, `Supabase`
(`SandEEAlpha/scripts/supabase_client.gd`), configured in
`SandEEAlpha/scripts/supabase_config.gd`.

| | |
|---|---|
| Project ref | `rqwtontlatcxrtimreng` |
| Project URL | `https://rqwtontlatcxrtimreng.supabase.co` |
| Client key | publishable key, stored **only** in `SandEEAlpha/scripts/supabase_config.gd` |
| Storage bucket | `cloud-saves` (private) |
| Edge Function | `login-with-username` (`verify_jwt = false`) |

> **Never** put a service-role/secret key, JWT signing secret or the database
> password in the Godot project, an exported build, this README or a commit.
> The Godot client ships with the publishable key only. Privileged operations
> run in SQL (`SECURITY DEFINER` functions) or in the Edge Function, which gets
> its secret key from the Supabase runtime environment.

## Schema

Applied migrations (remote and local are in sync):

```
20261022130000_sandee_cloud_backend.sql              tables, RLS, storage bucket
20261023180000_cloud_save_identity.sql               cross-platform world UID/revision
20261022132000_fix_claim_reward_ambiguity.sql        rename claim_reward params
20261022133500_touch_updated_at.sql                  server-side updated_at
20261022134500_remove_test_accounts.sql              test-data cleanup (one-off)
20261022135000_remove_leftover_test_account.sql      test-data cleanup (one-off)
20261022140000_username_email_lookup.sql             case-insensitive login
20261022141000_cleanup_integration_test_accounts.sql test-data cleanup (one-off)
20261022150000_leaderboard_test_profiles.sql         is_test + board views
20261022151000_seed_test_profile.sql                 test fixture stars
20261022152000_grant_is_test_read.sql                view filter column grant
20261022153000_cleanup_ui_test_accounts.sql          throwaway UI-test cleanup
20261022154000_cloud_save_world_name.sql             cloud metadata world_name
20261022155000_cleanup_cloud_test_account.sql        test-data cleanup (one-off)
20261022160000_cleanup_logout_test_account.sql       test-data cleanup (one-off)
20261022161000_cleanup_sync_test_account.sql         test-data cleanup (one-off)
20261022162000_cleanup_noemail_test_account.sql      test-data cleanup (one-off)
20261022163000_mission_star_sync.sql                 mission whitelist + guarded claims
20261022164000_cleanup_stars_test_account.sql        test-data cleanup (one-off)
20261022165000_retire_wolf_mission.sql               retire "Defeat 5 wolves" + refund
20261022166000_diamond_equipment_missions.sql         end-game diamond rewards
20261022167000_star_ledger.sql                        auditable star ledger
20261022168000_cloud_save_limit.sql                   5-cloud-save hard limit
20261022169000_cleanup_online_test_account.sql        test-data cleanup (one-off)
```

| Object | Purpose | Client access |
|---|---|---|
| `profiles` | `id`, internal login identifier in `email`, `username`, `blue_stars`, `yellow_stars`, `is_test`, timestamps | read public columns, update own `username`; `email`, stars and `is_test` are not client-readable |
| `saves` | legacy JSON save blob, one row per user | owner-only (RLS) |
| `cloud_saves` | metadata for Storage saves: `slot` 1..10, `object_path`, `world_name`, `world_uid`, `revision`, `size_bytes`, `checksum`, `updated_at` | owner-only (RLS) |
| `reward_claims` | one row per `(user_id, reward_id)`, protects rewards from double-claiming | read own only; written exclusively by `claim_missions()` |
| `mission_rewards` | server whitelist: valid mission/clear reward ids → fixed star kind and amount | none (RPC only) |
| `leaderboard` (view) | `username`, `blue_stars`, `yellow_stars`, `total_stars` | public read, **excludes `is_test` profiles** |
| `leaderboard_test` (view) | same columns, only `is_test` profiles | public read (contains test data only) |
| `username_available(text)` | pre-signup check | public |
| `claim_reward(p_reward_id, p_blue, p_yellow)` | atomically claims a reward and increments stars once | authenticated only |
| `username_email(text)` | resolves a username to its email for the login function | `service_role` only |
| Storage `cloud-saves` | private JSON saves at `<auth.uid()>/<slot>.json` | owner-only (storage policies) |

Security model:

* RLS is enabled on every table; policies live in the migrations.
* Column grants keep `profiles.email` away from `anon`/`authenticated`.
* Stars only change through `claim_missions()`/`claim_reward()`; a trigger on
  `profiles` rejects any direct star update unless the trusted function opted in
  (`sandee.stars_write`). Clients cannot call the arbitrary-amount
  `claim_reward` at all (service-role only). Mission ids are whitelisted in
  `mission_rewards`, and each id is awarded once per account.
* Reward ids are idempotent per player, so retries after a dropped connection
  do not award twice. The awarded amount is fixed server-side by the mission
  whitelist; completion itself is still client-reported (see “Limitations”).
* Storage policies compare the first path segment with `auth.uid()`, so a player
  can never read or overwrite another player's save.

## Edge Function

`functions/login-with-username/index.ts` accepts
`{ "username": "...", "password": "..." }`, resolves the account through the
`username_email()` SQL function (case-insensitive, service role only) and
returns `{ session, user }` from GoTrue. The stored `profiles.email` is the
synthetic `<username>@users.sandee.invalid` identifier for new accounts (older
accounts may have real addresses); it is never returned to game clients.
Invalid credentials always return a generic `400 { "error": "invalid_credentials" }`.

`config.toml` pins `verify_jwt = false` for this function: the caller does not
have a JWT yet, but every request still needs the publishable `apikey` header.

## Godot client and screens

`Supabase` is registered as an autoload in `project.godot`. It never touches
the network in `_ready()` (offline play is unaffected).

| File | Role |
|---|---|
| `scripts/supabase_config.gd` | the only place the project URL/key live |
| `scripts/supabase_client.gd` | auth, profiles, stars, leaderboards, cloud saves, connectivity |
| `scripts/startup_mode.gd` + `scenes/ui/startup_mode.tscn` | launch screen: Offline / Online |
| `scripts/online_account_panel.gd` | reusable login / register / account panel |
| `scripts/main_menu_ver.gd` | title menu, status line, leaderboard/cloud/account overlays |
| `scripts/star_icon.gd` | vector blue/yellow star icons |

Startup flow:

1. Offline is always selectable and never asks for an account.
2. Online is enabled only after the Supabase health endpoint answers. A failed
   health check is split into “Internet connection required.” (network probe
   failed) or “Sandee online is unavailable right now.” (probe worked, backend
   did not). Both can be retried without restarting.
3. Online then restores an existing session (`validate_session()`), or shows the
   login/registration panel. Cancelling returns to the mode choice.
4. After authentication the client fetches the profile, initializes cloud-save
   metadata and warms the leaderboard before entering the menu. If cloud init
   fails, the menu still opens with an **Error** status and a retry path.

Registration collects only a username, password and confirmation. Supabase Auth
still requires an email-shaped identifier, so the client derives
`<lowercase username>@users.sandee.invalid` (`.invalid` is reserved by RFC 2606
and cannot receive mail). It is never shown to the player, never used for
contact, and cannot be used for password recovery. The project must keep
Supabase email autoconfirm enabled because that identifier is non-deliverable.
Existing accounts created earlier with real emails continue to work, and their
emails are not exposed to clients.

Session persistence uses `FileAccess.open_encrypted_with_pass` at
`user://supabase_session.bin`, with a passphrase derived from the device
identity. The file is not plaintext JSON; passwords are never stored. This is
device-bound encryption, **not an OS keychain** — a true Windows DPAPI/Android
Keystore store would need a native plugin.

Main-menu online features (the **Leaderboard · Cloud Saves · Account** row is
hidden in Offline Mode; a **Go Online** button lets an offline player check
connectivity, reuse a valid cached session, or open the normal sign-in form
without restarting the game):

* **Leaderboard** button: Overall (`total_stars`), Dungeon (`blue_stars`) and
  Quests (`yellow_stars`) tabs, live rows with rank, username and star counts,
  loading/empty/error/retry states.
* **Cloud Saves** button: local-world list, cloud-slot list (**hard limit 5**),
  upload, download, world-identity/revision conflict detection (“in sync” / “differs”) with confirmation,
  `.bak` backup before a download replaces a local world, and confirmed delete.
  When the 5th slot cannot be added, a chooser asks which cloud world to
  replace; local worlds are never deleted by that flow.
* **Account** button: username, blue/yellow stars, logout. Logout only
  clears the session (instantly, even offline) and revokes it in the background;
  local worlds are untouched.
* Bottom-left status: `SandEE v0.9.3.2  |  Cloud Save Active` (plus Syncing,
  Synced, Pending, Offline, Error). Offline mode shows only the version. A
  30-second poll while online flips the status to Offline on network loss and
  re-validates the session before claiming Active again.

### Required backend migration

Apply `supabase/migrations/20261023180000_cloud_save_identity.sql` before
shipping clients with cross-platform identity/revision checks. It adds
`cloud_saves.world_uid` and `cloud_saves.revision`; existing RLS and private
Storage policies are reasserted, not weakened. No dashboard secrets are needed
in the game.

## Automatic cloud sync

`scripts/cloud_sync.gd` is a `CloudSync` autoload that pushes saves
automatically:

| Trigger | Hook |
|---|---|
| Game start / sign-in | `startup_mode._enter_online()` and the menu’s account login call `sync_all()` |
| 60 s autosave | `Global.save_game()` emits `game_saved` → `sync_slot()` |
| Quit to menu / window close | the same save path emits `game_saved` before leaving |
| Joining a world | `Global.load_game()` emits `world_loaded` → `sync_slot()` |

Policy:

* Every save records a stable `world_uid` and a monotonic `save_revision`.
  Upload only when this device has a strictly newer revision of the same world;
  identical checksums are a no-op.
* **Never auto-overwrite a different world** that happens to use the same cloud
  slot. A newer cloud revision, equal revisions with different bytes, a
  different UID, or legacy metadata without identity becomes **Pending** and is
  resolved manually from Cloud Saves. Device clocks are not used for conflict
  decisions.
* **Never download automatically.** Download is confirmed and keeps the previous
  local world as a `.bak` file; a checksum mismatch aborts before writing.
* A save that lands while an upload is in flight is marked dirty and synced
  again when the first upload finishes.
* Everything is a no-op outside Online Mode or without a signed-in session.

## Mission stars (local ↔ cloud)

The in-game tracker header now shows the **account's** blue/yellow stars (cloud
values when online, local fallback offline) and a smaller **this world** row.
Blue = dungeon missions + dungeon clear stars; yellow = overworld quests.

`CloudSync` claims missions through the whitelisted `claim_missions()` RPC:

| Trigger | What is claimed |
|---|---|
| World load | every completed mission/clear in that world |
| Mission completed / dungeon cleared | that single reward immediately |
| Startup / sign-in | every completed mission/clear found in **all** saved worlds (`sync_all_progress()`) plus the current session |

A fresh account whose cloud total is **0** but whose local worlds already have
completed missions is filled on the first scan — the requested migration path.
Offline completions are recovered on the next world load or sign-in. Repeats are
ignored by the `(user, reward_id)` unique claim, so scanning every world is safe.

Exploit guards:

* `mission_rewards` is a server-side whitelist (28 quests, 25 dungeon missions,
  25 clear stars); unknown ids are ignored. The retired "Defeat 5 wolves" id was
  removed from the whitelist and its claim/star was refunded by migration
  `20261022165000_retire_wolf_mission.sql`. The final three quests are the
  diamond sword/pickaxe/axe equipment missions.
* Worlds created before **0.9.3.0** are excluded from account/leaderboard stars
  (`Global.world_progress_eligible()`); their local missions still work, and the
  tracker labels them “legacy · not ranked”.
* Every accepted claim writes a row to `star_ledger` for audit/reversal; clients
  can read only their own rows.
* Each reward id is awarded once per account; amounts are fixed server-side.
* A `profiles` trigger rejects star changes unless the transaction explicitly
  sets `sandee.stars_write`, which only the `SECURITY DEFINER` functions do.
* The old arbitrary-amount `claim_reward()` is revoked from client roles.

## Test profile

The leaderboard fixture is **`SandEE_TestPlayer`** (`sandee.testplayer@example.com`),
created through the real signup flow with a random password that was
intentionally discarded (never written to the repo, a log or the game).
`is_test = true`, blue = 42, yellow = 17 (`20261022151000_seed_test_profile.sql`).

* It appears in `leaderboard_test` only; the production `leaderboard` view
  filters it out, so it cannot pollute real rankings.
* To use it interactively, reset its password in the Supabase dashboard
  (Authentication → Users). Do not commit a password.
* Remove it when no longer needed:
  `delete from auth.users where email = 'sandee.testplayer@example.com';`
  (profiles, claims and saves cascade).

No client/admin key is exposed to the game.

## CLI workflow

```powershell
supabase login                       # interactive, once per machine
supabase init                        # only if supabase/ is missing (never rerun)
supabase link --project-ref rqwtontlatcxrtimreng
supabase migration list --linked     # local vs remote
supabase db push --linked            # apply pending migrations
supabase functions deploy login-with-username --project-ref rqwtontlatcxrtimreng
```

Rules:

* Add schema changes as new timestamped migrations; never edit an applied one.
* Do not reset or wipe the remote database. Migrations here are idempotent.
* `supabase db dump` needs Docker (not installed); use
  `supabase gen types typescript --project-id rqwtontlatcxrtimreng` to inspect
  the remote schema instead.
* The DB password is not stored in this repo.

## Crash / diagnostic logs

`scripts/crash_logger.gd` is the first autoload. It registers a `Logger` with
`OS.add_logger()`, writes every print/error/backtrace, and flushes each line:

* Windows/Linux/macOS export: **`<executable folder>/logs/sandee_<time>.log`**
  (falls back to `user://logs` if the install folder is read-only).
* Android/iOS: `user://logs/` (app-private; `adb pull` or logcat).
* Editor/headless: `user://logs/`.

A `session.active` marker is created at startup and removed on a clean exit; if
it is still there on the next launch, the new log begins with
`PREVIOUS SESSION DID NOT EXIT CLEANLY`. Up to 10 logs are kept.

GDScript errors include the engine backtrace. **Native minidumps are not
captured** (that needs a platform crash handler, e.g. Windows DBGHELP or an
Android tombstone); the flushed application log plus the unclean-exit marker is
the current evidence trail.

`CrashLogger.report()` records QA reasons such as a blocked build-mode toggle
(chat/pause/text-focus) with the caller's GDScript stack.

## Verification (2026-10-22)

Live, against `rqwtontlatcxrtimreng`, using the publishable key only:

* Startup screen appears before the menu; Offline opens the existing menu with
  `Global.online_mode == false` and no cloud claim (7/7 flow checks).
* 64/64 headless UI/client checks: connectivity distinction, login/registration
  through the real forms, invalid-credential errors, encrypted session round-trip,
  status transitions (Active/Syncing/Pending/Error/Offline), live leaderboard
  totals, cloud upload/download/conflict/delete, logout keeping local worlds,
  click-blocking overlays, 800x600 and 1920x1080 layouts.
* 7/7 scene-flow checks: startup is the first scene and Offline opens the
  existing main menu with no cloud claim.
* 6/6 cloud-metadata checks: uploaded worlds carry their name and size, and
  download/delete still round-trip exactly.
* 6/6 logout/session checks: logout is instant (0 ms, no network wait), removes
  the encrypted session file, and a later username login still works.
* 20/20 follow-up checks: requesting Online with **no** stored session shows the
  login form immediately (status “Sign in to play online.”, Offline still
  clickable); an invalid stored session is cleared and falls back to the form;
  the online menu row is hidden offline while a Go Online button is shown, and
  the row returns online after a successful switch; startup sync,
  autosave-triggered sync, offline no-op and newer-cloud conflict detection all
  behave as specified.
* 368/368 permanent offline QA checks (`tools/run_qa.ps1`,
  `SandEEAlpha/tests/qa_regression.tscn`): mission registry/order, save/load and
  retired-mission migration, at-goal completion, dungeon-clear/learn/quiz
  triggers, pause/altar teardown, build-mode restore + focus release,
  legacy-version gating, dungeon room margins, trap clearance across seeds,
  quiz-guard cap, camera padding, trap/flare/hitman damage application,
  safe-zone union/overlap/edges, projectile/enemy disintegration, grass
  clearance at dungeon entrances, complete ore-to-bar smelting with atomic
  failure/save-load checks, centralized Escape/Android-Back overlay dismissal,
  portable world UID/revision save migration and cloud conflict classification,
  Android package/renderer/touch configuration, Lua/Python execution, Python
  runtime errors, and crash-log capture/backtrace.
* 15/15 live checks: legacy worlds are skipped while eligible worlds sync, the
  diamond mission is claimable, claims appear in `star_ledger`, five cloud saves
  upload, the sixth returns `cloud_limit`, the DB trigger enforces the limit,
  and the replacement chooser lists all five cloud worlds.
* 23/23 game-side QA checks (2026-10-22): retired wolf mission gone (25
  overworld missions remain), `build_shelter` goal matches its tracker,
  partial mission progress persists/resets correctly, old saves containing the
  wolf mission load safely, `clear_dungeon`/`learn_entry` fire, leaked altar
  pause is released on teardown, dungeon-exit restore clears pause and re-syncs
  build mode, and valid/invalid Lua+Python execution is handled without a crash.
* Crash logging was verified in an exported Windows build: the log was created
  next to the executable, and a killed run produced the
  `PREVIOUS SESSION DID NOT EXIT CLEANLY` banner on the next launch.
* REST/DB: production leaderboard excludes `SandEE_TestPlayer`; the test view
  returns 42/17/59; anonymous `claim_reward` → 401; direct star `PATCH` → 403;
  forged `reward_claims` insert → 403; cross-account storage read → 400.
* Password reset endpoint is no longer part of the game UI: registration
  collects only a username + password, so there is no address to send a link to.
  (The Supabase SMTP-backed endpoint remains available to the project, but the
  synthetic `.invalid` identifier can never receive mail.)
* 12/12 username-only registration checks: three fields (username, password,
  confirmation), masked passwords, successful registration, derived
  `.invalid` identifier, case-insensitive username login, duplicate-username
  rejection and no email/reset controls.
* Throwaway test accounts (`godot.*@example.com`) were removed after the runs.

## Limitations

* **No anti-cheat:** star amounts come from the client. Server-side validation
  (signed run results in an Edge Function) is required before public
  leaderboards are meaningful.
* **Mission completion is still client-reported:** a modified client could claim
  the known mission ids without playing. The server caps this to the whitelist
  and awards each id once, but full anti-cheat needs server-side gameplay
  validation (signed run results in an Edge Function).
* **Cloud sync pushes automatically but never pulls automatically.** An older
  local world is never allowed to overwrite a newer cloud copy; resolve the
  Pending conflict from Cloud Saves.
* **Legacy stars are not retroactively removed:** the 0.9.3.0 gate applies to
  new claims. Stars already claimed before this update (when worlds were not
  filtered) cannot be attributed back to a world and remain on the account. A
  one-time admin reset is possible if a specific account must be cleaned.
* **No account recovery:** because no email is collected, a forgotten password
  cannot be reset by email. A future recovery flow needs an owner-mediated reset
  or a real recovery channel.
* **Supabase email confirmation must stay off** (`mailer_autoconfirm = true`):
  the derived `@users.sandee.invalid` identifier cannot receive a confirmation
  email. If confirmation is enabled, signup returns no session and the game
  reports that sign-in was not completed.
* **Android not device-tested:** the UI uses `LineEdit`/`ScrollContainer` and
  the engine's virtual keyboard, and a 30-second status timer, but no APK was
  run on a phone in this session.
* **Not an OS keystore:** session encryption is device-bound but cannot protect
  against an attacker with full access to the unlocked device.
* Google/Apple sign-in and account recovery UI are not configured.

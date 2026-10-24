-- Development fixture: known stars for the dedicated test profile.
--
-- The account was created through the REAL signup flow with a random password
-- that was intentionally discarded (never written to the repo, the game or a
-- log). If you need to sign in as it for manual UI checks, reset its password in
-- the Supabase dashboard (Authentication -> Users) — do not commit credentials.
--
-- This only touches the exact test address/username. `is_test = true` keeps it
-- out of the public `leaderboard` view; it is visible through
-- `leaderboard_test` for verification.
--
-- Removal (when the fixture is no longer needed):
--   delete from auth.users where email = 'sandee.testplayer@example.com';
-- Profiles/claims/saves cascade from auth.users.

update public.profiles
set is_test      = true,
	blue_stars   = 42,
	yellow_stars = 17
where email = 'sandee.testplayer@example.com'
	and username = 'SandEE_TestPlayer';

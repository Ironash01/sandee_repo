-- Test-profile support for the leaderboard.
--
-- `profiles.is_test` marks accounts that exist only for integration checks.
-- The public `leaderboard` view EXCLUDES them, so test data can never appear in
-- the player-facing rankings. `leaderboard_test` exposes ONLY the test rows so
-- the same query can be verified end to end.
--
-- `is_test` is not part of the client column grants (clients can only read
-- id/username/stars and update their own username), so a player cannot flag
-- themselves as a test account or clear the flag.

alter table public.profiles
	add column if not exists is_test boolean not null default false;

create or replace view public.leaderboard
with (security_invoker = true)
as
select
	id,
	username,
	blue_stars,
	yellow_stars,
	(blue_stars + yellow_stars) as total_stars,
	updated_at
from public.profiles
where not is_test;

create or replace view public.leaderboard_test
with (security_invoker = true)
as
select
	id,
	username,
	blue_stars,
	yellow_stars,
	(blue_stars + yellow_stars) as total_stars,
	updated_at
from public.profiles
where is_test;

grant select on public.leaderboard to anon, authenticated;
grant select on public.leaderboard_test to anon, authenticated;

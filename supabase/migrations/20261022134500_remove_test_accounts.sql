-- One-off cleanup of the temporary accounts created while verifying the live
-- Supabase integration (2026-10-22). These were end-to-end test users with
-- clearly-labelled @example.com addresses; removing them keeps the star
-- leaderboard limited to real players.
--
-- Safe to apply on any environment: only these exact addresses are touched, and
-- the statement is a no-op if they do not exist. Profiles, saves, cloud-save
-- metadata and reward claims are removed by the existing ON DELETE CASCADE
-- foreign keys.

delete from auth.users
where email in (
	'sandee.e2e.1792673702@example.com',
	'sandee.e2e2.1792673702@example.com',
	'godot.1792674063@example.com',
	'godot.1792674083@example.com'
);

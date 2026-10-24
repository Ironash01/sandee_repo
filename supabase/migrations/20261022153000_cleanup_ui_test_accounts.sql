-- Cleanup for the throwaway accounts created by the headless UI tests
-- (all use `godot.*@example.com` addresses and are deleted after each run).
-- The dedicated fixture `SandEE_TestPlayer` (sandee.testplayer@example.com) is
-- deliberately NOT touched: it lives only in `leaderboard_test`.

delete from auth.users
where email like 'godot.%@example.com'
   or email like 'sandee.e2e%@example.com';

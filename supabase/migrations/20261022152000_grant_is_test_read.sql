-- The leaderboard views filter on `profiles.is_test` and run with
-- `security_invoker = true`, so the invoking role needs SELECT on that column
-- even though it is only used in the WHERE clause (it is not exposed by the
-- views). Reading the flag is harmless; clients still cannot change it.

grant select (is_test) on public.profiles to anon, authenticated;

-- Removes the last leftover account from the live integration checks
-- (an earlier Godot test run that stopped before its own cleanup step).
-- Same rules as the previous cleanup migration: exact address, no-op if absent.

delete from auth.users
where email = 'godot.1792674043@example.com';

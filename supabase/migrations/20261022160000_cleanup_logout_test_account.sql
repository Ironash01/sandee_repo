-- Removes the throwaway account created by the logout/session test.
-- Same test-only addresses as the earlier cleanup migrations.

delete from auth.users
where email like 'godot.%@example.com'
   or email like 'sandee.e2e%@example.com';

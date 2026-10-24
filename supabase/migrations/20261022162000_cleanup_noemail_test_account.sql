-- Removes the throwaway account created by the username-only registration test.
-- Scoped to the test prefix so real synthetic-email accounts are never touched.

delete from auth.users
where email like 'gd_noemail_%@users.sandee.invalid';

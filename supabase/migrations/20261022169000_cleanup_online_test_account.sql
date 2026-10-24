-- Removes the throwaway account created by the live cloud-limit/ledger test.

delete from auth.users
where email like 'godot.online.%@users.sandee.invalid';

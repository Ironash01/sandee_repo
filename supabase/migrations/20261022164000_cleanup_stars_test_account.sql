-- Removes the throwaway account created by the mission/star sync test.
-- Test emails use a dotted `godot.*` local part; real synthetic account emails
-- are `<username>@users.sandee.invalid` and usernames cannot contain a dot, so
-- this cannot match a real player.

delete from auth.users
where email like 'godot.%@users.sandee.invalid';

-- Three-star dungeon clears.
--
-- Every dungeon already has a mission reward (1 blue star) and a clear reward
-- (1 blue star). This adds the third, perfect-clear star. The client claims it
-- only when the quiz altar was completed with zero hints; one hint leaves the
-- mission + normal clear (2 stars), and two or more hints leave only the
-- mission star (1 star).
--
-- Existing cleared dungeons have no hint history. The client treats them as
-- perfect clears so previously completed content remains worth the new maximum
-- of three blue stars.

insert into public.mission_rewards (reward_id, kind, amount, label)
select
	'dungeon_clear_bonus:' || i,
	'blue',
	1,
	'perfect dungeon clear ' || i
from generate_series(1, 40) as i
where (i between 1 and 11) or (i between 26 and 40)
on conflict (reward_id) do nothing;

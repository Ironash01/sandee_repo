-- End-game diamond equipment missions (the calls already existed in the crafting
-- UI, but no mission definitions/whitelist rows existed).

insert into public.mission_rewards (reward_id, kind, amount, label) values
	('mission:craft_diamond_sword', 'yellow', 1, 'quest: craft_diamond_sword'),
	('mission:craft_diamond_pickaxe', 'yellow', 1, 'quest: craft_diamond_pickaxe'),
	('mission:craft_diamond_axe', 'yellow', 1, 'quest: craft_diamond_axe')
on conflict (reward_id) do nothing;

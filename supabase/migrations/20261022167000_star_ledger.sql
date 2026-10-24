-- Auditable star ledger. Every claim/refund writes one row so future content
-- retirements or corrections can be explained and reversed safely.
--
-- Clients may read their own rows; only SECURITY DEFINER functions write here.

create table if not exists public.star_ledger (
	id          bigint generated always as identity primary key,
	user_id     uuid not null references auth.users (id) on delete cascade,
	reward_id   text not null default '',
	blue_delta  integer not null default 0,
	yellow_delta integer not null default 0,
	reason      text not null default 'mission_claim',
	created_at  timestamptz not null default now()
);

create index if not exists star_ledger_user_created_idx
	on public.star_ledger (user_id, created_at desc);

alter table public.star_ledger enable row level security;

drop policy if exists "star ledger read own" on public.star_ledger;
create policy "star ledger read own" on public.star_ledger
	for select to authenticated using (auth.uid() = user_id);

revoke all on public.star_ledger from public, anon, authenticated;
grant select on public.star_ledger to authenticated;

-- Batch mission claims: write a ledger row for each newly inserted claim.
create or replace function public.claim_missions(p_reward_ids text[])
returns table (claimed integer, blue_total integer, yellow_total integer)
language plpgsql
security definer
set search_path = public
as $$
declare
	inc_blue integer := 0;
	inc_yellow integer := 0;
	inserted_count integer := 0;
	entry record;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;
	if coalesce(array_length(p_reward_ids, 1), 0) > 200 then
		raise exception 'too many rewards in one request' using errcode = '22023';
	end if;

	for entry in
		with valid as (
			select v.reward_id, v.kind, v.amount
			from public.mission_rewards v
			where v.reward_id = any(coalesce(p_reward_ids, '{}'::text[]))
		), ins as (
			insert into public.reward_claims (user_id, reward_id, blue_stars, yellow_stars)
			select auth.uid(), v.reward_id,
				case when v.kind = 'blue' then v.amount else 0 end,
				case when v.kind = 'yellow' then v.amount else 0 end
			from valid v
			on conflict (user_id, reward_id) do nothing
			returning reward_id
		)
		select v.reward_id, v.kind, v.amount
		from ins i join valid v on v.reward_id = i.reward_id
	loop
		insert into public.star_ledger
			(user_id, reward_id, blue_delta, yellow_delta, reason)
		values (
			auth.uid(), entry.reward_id,
			case when entry.kind = 'blue' then entry.amount else 0 end,
			case when entry.kind = 'yellow' then entry.amount else 0 end,
			'mission_claim');
		if entry.kind = 'blue' then
			inc_blue := inc_blue + entry.amount;
		else
			inc_yellow := inc_yellow + entry.amount;
		end if;
		inserted_count := inserted_count + 1;
	end loop;

	if inserted_count > 0 then
		perform set_config('sandee.stars_write', 'on', true);
		update public.profiles as p
		set blue_stars   = p.blue_stars   + inc_blue,
			yellow_stars = p.yellow_stars + inc_yellow,
			updated_at   = now()
		where p.id = auth.uid();
	end if;

	return query
		select inserted_count, p.blue_stars, p.yellow_stars
		from public.profiles p where p.id = auth.uid();
end;
$$;

revoke all on function public.claim_missions(text[]) from public, anon;
grant execute on function public.claim_missions(text[]) to authenticated;

-- Admin/legacy arbitrary claim: keep the audit trail too.
create or replace function public.claim_reward(
	p_reward_id text,
	p_blue integer default 0,
	p_yellow integer default 0
)
returns table (claimed boolean, blue_stars integer, yellow_stars integer)
language plpgsql
security definer
set search_path = public
as $$
declare
	inserted boolean := false;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;

	with ins as (
		insert into public.reward_claims as rc (user_id, reward_id, blue_stars, yellow_stars)
		values (auth.uid(), p_reward_id, greatest(p_blue, 0), greatest(p_yellow, 0))
		on conflict (user_id, reward_id) do nothing
		returning 1
	)
	select exists(select 1 from ins) into inserted;

	if inserted then
		insert into public.star_ledger
			(user_id, reward_id, blue_delta, yellow_delta, reason)
		values (auth.uid(), p_reward_id, greatest(p_blue, 0), greatest(p_yellow, 0), 'claim_reward');
		perform set_config('sandee.stars_write', 'on', true);
		update public.profiles as p
		set blue_stars   = p.blue_stars   + greatest(p_blue, 0),
			yellow_stars = p.yellow_stars + greatest(p_yellow, 0),
			updated_at   = now()
		where p.id = auth.uid();
	end if;

	return query
		select inserted, p.blue_stars, p.yellow_stars
		from public.profiles p where p.id = auth.uid();
end;
$$;

revoke all on function public.claim_reward(text, integer, integer) from public, anon, authenticated;
grant execute on function public.claim_reward(text, integer, integer) to service_role;

-- Adds recurring goal schedules, challenge-specific badge designs, and repeat-win history.
-- Run after supabase_reading_goals.sql. Safe to run more than once.

alter table public.reading_challenges
  add column if not exists cadence text not null default 'annual',
  add column if not exists badge_style text not null default 'classic';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reading_challenges_cadence_check'
      and conrelid = 'public.reading_challenges'::regclass
  ) then
    alter table public.reading_challenges
      add constraint reading_challenges_cadence_check
      check (cadence in ('annual', 'monthly', 'weekly'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'reading_challenges_badge_style_check'
      and conrelid = 'public.reading_challenges'::regclass
  ) then
    alter table public.reading_challenges
      add constraint reading_challenges_badge_style_check
      check (badge_style in ('classic', 'book', 'moon', 'spark', 'bolt', 'feather', 'mountain', 'compass', 'crown', 'laurel', 'flame', 'wave'));
  end if;
end;
$$;

-- Upgrade the original built-in cadence examples to their recurring versions.
update public.reading_challenges
set name = 'The Monthly Reader', challenge_type = 'custom', cadence = 'monthly', target_value = 1
where name = 'The One-Book-a-Month Year'
  and challenge_type = 'annual_books' and cadence = 'annual' and target_value = 12;

update public.reading_challenges
set challenge_type = 'custom', cadence = 'monthly', target_value = 2
where name = 'Two Dozen Stories'
  and challenge_type = 'annual_books' and cadence = 'annual' and target_value = 24;

update public.reading_challenges
set challenge_type = 'custom', cadence = 'weekly', target_value = 1
where name = 'The Weekly Reader'
  and challenge_type = 'annual_books' and cadence = 'annual' and target_value = 52;

-- Give existing challenges distinct badge designs, while remaining stable on reruns.
with ranked as (
  select id, row_number() over (partition by user_id order by created_at, id) as badge_number
  from public.reading_challenges
  where badge_style = 'classic'
)
update public.reading_challenges as challenge
set badge_style = case ((ranked.badge_number - 1) % 11)
  when 0 then 'book'
  when 1 then 'moon'
  when 2 then 'spark'
  when 3 then 'bolt'
  when 4 then 'feather'
  when 5 then 'mountain'
  when 6 then 'compass'
  when 7 then 'crown'
  when 8 then 'laurel'
  when 9 then 'flame'
  else 'wave'
end
from ranked
where challenge.id = ranked.id;

create table if not exists public.reading_challenge_wins (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.reading_challenges(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  cadence text not null default 'annual',
  progress_value integer not null,
  earned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint reading_challenge_wins_period_check check (period_end >= period_start),
  constraint reading_challenge_wins_progress_check check (progress_value > 0),
  constraint reading_challenge_wins_cadence_check check (cadence in ('annual', 'monthly', 'weekly')),
  constraint reading_challenge_wins_challenge_cadence_period_unique unique (challenge_id, cadence, period_start)
);

alter table public.reading_challenge_wins
  add column if not exists cadence text not null default 'annual';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reading_challenge_wins_cadence_check'
      and conrelid = 'public.reading_challenge_wins'::regclass
  ) then
    alter table public.reading_challenge_wins
      add constraint reading_challenge_wins_cadence_check
      check (cadence in ('annual', 'monthly', 'weekly'));
  end if;
end;
$$;

alter table public.reading_challenge_wins
  alter column user_id set default auth.uid();

alter table public.reading_challenge_wins enable row level security;

drop policy if exists "Users can read their own challenge wins" on public.reading_challenge_wins;
create policy "Users can read their own challenge wins"
  on public.reading_challenge_wins for select
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.reading_challenges challenge
      where challenge.id = reading_challenge_wins.challenge_id and challenge.user_id = auth.uid()
    )
  );

drop policy if exists "Users can record their own challenge wins" on public.reading_challenge_wins;
create policy "Users can record their own challenge wins"
  on public.reading_challenge_wins for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.reading_challenges challenge
      where challenge.id = reading_challenge_wins.challenge_id and challenge.user_id = auth.uid()
    )
  );

drop policy if exists "Users can delete their own challenge wins" on public.reading_challenge_wins;
create policy "Users can delete their own challenge wins"
  on public.reading_challenge_wins for delete
  using (auth.uid() = user_id);

create index if not exists reading_challenge_wins_user_period_idx
  on public.reading_challenge_wins (user_id, period_start desc);

grant select, insert, delete on public.reading_challenge_wins to authenticated;

-- Preserve existing annual completion badges in the new win-history table.
insert into public.reading_challenge_wins
  (challenge_id, user_id, period_start, period_end, progress_value, earned_at)
select
  id,
  user_id,
  make_date(year, 1, 1),
  make_date(year, 12, 31),
  target_value,
  completed_at
from public.reading_challenges
where completed_at is not null
on conflict (challenge_id, cadence, period_start) do nothing;

comment on table public.reading_challenge_wins is
  'One earned Reading Goals badge per qualifying challenge period, allowing repeat awards over time.';

notify pgrst, 'reload schema';

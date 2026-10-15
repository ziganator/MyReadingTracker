-- Stores Reading Goals and their permanent earned-badge timestamps per user.
-- Safe to run more than once.

create table if not exists public.reading_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  challenge_type text not null default 'custom',
  metric text not null default 'books',
  target_value integer not null,
  year integer not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reading_challenges_name_not_blank check (length(trim(name)) > 0),
  constraint reading_challenges_type_check check (challenge_type in ('annual_books', 'custom')),
  constraint reading_challenges_metric_check check (metric in ('books', 'pages')),
  constraint reading_challenges_target_check check (target_value between 1 and 1000000),
  constraint reading_challenges_year_check check (year between 1900 and 2200),
  constraint reading_challenges_annual_metric_check check (challenge_type <> 'annual_books' or metric = 'books')
);

alter table public.reading_challenges
  alter column user_id set default auth.uid();

alter table public.reading_challenges enable row level security;

drop policy if exists "Users can read their own reading challenges" on public.reading_challenges;
create policy "Users can read their own reading challenges"
  on public.reading_challenges for select
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own reading challenges" on public.reading_challenges;
create policy "Users can create their own reading challenges"
  on public.reading_challenges for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own reading challenges" on public.reading_challenges;
create policy "Users can update their own reading challenges"
  on public.reading_challenges for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own reading challenges" on public.reading_challenges;
create policy "Users can delete their own reading challenges"
  on public.reading_challenges for delete
  using (auth.uid() = user_id);

create index if not exists reading_challenges_user_year_idx
  on public.reading_challenges (user_id, year desc, created_at desc);

create or replace function public.touch_reading_challenges_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_reading_challenges_updated_at on public.reading_challenges;
create trigger touch_reading_challenges_updated_at
before update on public.reading_challenges
for each row execute function public.touch_reading_challenges_updated_at();

grant select, insert, update, delete on public.reading_challenges to authenticated;

comment on table public.reading_challenges is
  'User-owned annual reading challenges. completed_at records when the associated achievement badge was earned.';

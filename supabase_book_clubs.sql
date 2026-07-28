-- Creates user-owned book clubs and lets each book be assigned to one club.
-- Safe to run more than once.

create table if not exists public.book_clubs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_clubs_name_not_blank check (length(trim(name)) > 0)
);

alter table public.book_clubs
  alter column user_id set default auth.uid();

alter table public.book_clubs
  add column if not exists meeting_format text not null default 'In Person',
  add column if not exists usual_location text,
  add column if not exists online_url text,
  add column if not exists cadence text,
  add column if not exists usual_meeting_day text,
  add column if not exists usual_meeting_time time,
  add column if not exists timezone text not null default 'America/Los_Angeles';

alter table public.book_clubs
  drop constraint if exists book_clubs_meeting_format_check;

alter table public.book_clubs
  add constraint book_clubs_meeting_format_check
  check (meeting_format in ('Online', 'In Person', 'Hybrid'));

create unique index if not exists book_clubs_user_name_unique
  on public.book_clubs (user_id, lower(trim(name)));

alter table public.book_clubs enable row level security;

drop policy if exists "Users can read their own book clubs" on public.book_clubs;
drop policy if exists "Owners and members can read book clubs" on public.book_clubs;
create policy "Users can read their own book clubs"
  on public.book_clubs for select
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own book clubs" on public.book_clubs;
create policy "Users can create their own book clubs"
  on public.book_clubs for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own book clubs" on public.book_clubs;
create policy "Users can update their own book clubs"
  on public.book_clubs for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own book clubs" on public.book_clubs;
create policy "Users can delete their own book clubs"
  on public.book_clubs for delete
  using (auth.uid() = user_id);

create or replace function public.touch_book_clubs_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_book_clubs_updated_at on public.book_clubs;
create trigger touch_book_clubs_updated_at
before update on public.book_clubs
for each row execute function public.touch_book_clubs_updated_at();

alter table public.books
  add column if not exists book_club_id uuid references public.book_clubs(id) on delete set null;

create index if not exists books_book_club_id_idx
  on public.books (book_club_id)
  where book_club_id is not null;

create or replace function public.validate_book_club_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.book_club_id is not null and not exists (
    select 1
    from public.book_clubs
    where id = new.book_club_id
      and user_id = new.user_id
  ) then
    raise exception 'The selected book club does not belong to this user.';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_book_club_assignment on public.books;
create trigger validate_book_club_assignment
before insert or update of book_club_id, user_id on public.books
for each row execute function public.validate_book_club_assignment();

comment on table public.book_clubs is
  'Book clubs owned by one Reading Tracker user; setup and chat features can extend these rows later.';

comment on column public.books.book_club_id is
  'Optional book club associated with this book.';

create table if not exists public.book_club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.book_clubs(id) on delete cascade,
  account_user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  email text,
  role text not null default 'Member',
  timezone text,
  joined_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_club_members_name_not_blank check (length(trim(display_name)) > 0),
  constraint book_club_members_role_check check (role in ('Organizer', 'Moderator', 'Member', 'Guest'))
);

alter table public.book_club_members
  add column if not exists timezone text;

create unique index if not exists book_club_members_account_unique
  on public.book_club_members (club_id, account_user_id)
  where account_user_id is not null;

create unique index if not exists book_club_members_email_unique
  on public.book_club_members (club_id, lower(trim(email)))
  where email is not null and length(trim(email)) > 0;

create table if not exists public.book_club_reads (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.book_clubs(id) on delete cascade,
  book_id uuid references public.books(id) on delete set null,
  title text not null,
  author text,
  cover_url text,
  status text not null default 'Upcoming',
  start_date date,
  end_date date,
  meeting_at timestamptz,
  meeting_format text,
  location text,
  online_url text,
  discussion_prompt text,
  notes text,
  rating numeric(4,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_club_reads_title_not_blank check (length(trim(title)) > 0),
  constraint book_club_reads_status_check check (status in ('Current', 'Upcoming', 'Completed')),
  constraint book_club_reads_meeting_format_check check (meeting_format is null or meeting_format in ('Online', 'In Person', 'Hybrid')),
  constraint book_club_reads_dates_check check (end_date is null or start_date is null or end_date >= start_date),
  constraint book_club_reads_rating_check check (rating is null or (rating >= 0 and rating <= 10))
);

create index if not exists book_club_members_club_id_idx
  on public.book_club_members (club_id);

create index if not exists book_club_reads_club_status_idx
  on public.book_club_reads (club_id, status, start_date);

create or replace function public.touch_book_club_workspace_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_book_club_members_updated_at on public.book_club_members;
create trigger touch_book_club_members_updated_at
before update on public.book_club_members
for each row execute function public.touch_book_club_workspace_updated_at();

drop trigger if exists touch_book_club_reads_updated_at on public.book_club_reads;
create trigger touch_book_club_reads_updated_at
before update on public.book_club_reads
for each row execute function public.touch_book_club_workspace_updated_at();

create or replace function public.owns_book_club(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.book_clubs
    where id = target_club_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.can_view_book_club(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.owns_book_club(target_club_id)
    or exists (
      select 1
      from public.book_club_members
      where club_id = target_club_id
        and account_user_id = auth.uid()
    );
$$;

alter table public.book_club_members enable row level security;
alter table public.book_club_reads enable row level security;

drop policy if exists "Users can read their own book clubs" on public.book_clubs;
drop policy if exists "Owners and members can read book clubs" on public.book_clubs;
create policy "Owners and members can read book clubs"
  on public.book_clubs for select
  using (public.can_view_book_club(id));

drop policy if exists "Club members can read the roster" on public.book_club_members;
create policy "Club members can read the roster"
  on public.book_club_members for select
  using (public.can_view_book_club(club_id));

drop policy if exists "Club owners can add members" on public.book_club_members;
create policy "Club owners can add members"
  on public.book_club_members for insert
  with check (public.owns_book_club(club_id));

drop policy if exists "Club owners can update members" on public.book_club_members;
create policy "Club owners can update members"
  on public.book_club_members for update
  using (public.owns_book_club(club_id))
  with check (public.owns_book_club(club_id));

drop policy if exists "Club owners can remove members" on public.book_club_members;
create policy "Club owners can remove members"
  on public.book_club_members for delete
  using (public.owns_book_club(club_id));

drop policy if exists "Club members can read selections" on public.book_club_reads;
create policy "Club members can read selections"
  on public.book_club_reads for select
  using (public.can_view_book_club(club_id));

drop policy if exists "Club owners can add selections" on public.book_club_reads;
create policy "Club owners can add selections"
  on public.book_club_reads for insert
  with check (public.owns_book_club(club_id));

drop policy if exists "Club owners can update selections" on public.book_club_reads;
create policy "Club owners can update selections"
  on public.book_club_reads for update
  using (public.owns_book_club(club_id))
  with check (public.owns_book_club(club_id));

drop policy if exists "Club owners can remove selections" on public.book_club_reads;
create policy "Club owners can remove selections"
  on public.book_club_reads for delete
  using (public.owns_book_club(club_id));

grant select, insert, update, delete on public.book_clubs to authenticated;
grant select, insert, update, delete on public.book_club_members to authenticated;
grant select, insert, update, delete on public.book_club_reads to authenticated;
grant execute on function public.owns_book_club(uuid) to authenticated;
grant execute on function public.can_view_book_club(uuid) to authenticated;

comment on table public.book_club_members is
  'Roster entries for a book club. account_user_id links a roster entry to a Reading Tracker account when invitations are added.';

comment on column public.book_club_members.timezone is
  'The member IANA time zone used to present club meeting times across locations.';

comment on table public.book_club_reads is
  'Current, upcoming, and completed club selections with reading and meeting details.';

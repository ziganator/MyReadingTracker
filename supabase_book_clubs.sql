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
  add column if not exists timezone text not null default 'America/Los_Angeles',
  add column if not exists open_enrollment boolean not null default false;

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

create table if not exists public.book_club_invitations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.book_clubs(id) on delete cascade,
  token uuid not null default gen_random_uuid(),
  email text not null,
  invitee_name text,
  role text not null default 'Member',
  status text not null default 'Pending',
  expires_at timestamptz,
  invited_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_club_invitations_email_not_blank check (length(trim(email)) > 0),
  constraint book_club_invitations_role_check check (role in ('Moderator', 'Member', 'Guest')),
  constraint book_club_invitations_status_check check (status in ('Pending', 'Accepted', 'Revoked', 'Expired'))
);

create unique index if not exists book_club_invitations_token_unique
  on public.book_club_invitations (token);

create unique index if not exists book_club_invitations_pending_email_unique
  on public.book_club_invitations (club_id, lower(trim(email)))
  where status = 'Pending';

create index if not exists book_club_members_club_id_idx
  on public.book_club_members (club_id);

create index if not exists book_club_reads_club_status_idx
  on public.book_club_reads (club_id, status, start_date);

create index if not exists book_club_invitations_club_status_idx
  on public.book_club_invitations (club_id, status, created_at desc);

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

drop trigger if exists touch_book_club_invitations_updated_at on public.book_club_invitations;
create trigger touch_book_club_invitations_updated_at
before update on public.book_club_invitations
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

create or replace function public.is_book_club_moderator(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.book_club_members
    where club_id = target_club_id
      and account_user_id = auth.uid()
      and role = 'Moderator'
  );
$$;

create or replace function public.can_moderate_book_club(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.owns_book_club(target_club_id)
    or public.is_book_club_moderator(target_club_id);
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

create or replace function public.protect_book_club_moderator_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.owns_book_club(old.id) then
    return new;
  end if;
  if public.is_book_club_moderator(old.id) then
    if new.user_id is distinct from old.user_id then
      raise exception 'Only the Organizer can change club ownership.' using errcode = '42501';
    end if;
    if new.open_enrollment is distinct from old.open_enrollment then
      raise exception 'Only the Organizer can change open enrollment.' using errcode = '42501';
    end if;
    return new;
  end if;
  raise exception 'Only an Organizer or Moderator can update this club.' using errcode = '42501';
end;
$$;

drop trigger if exists protect_book_club_moderator_update on public.book_clubs;
create trigger protect_book_club_moderator_update
before update on public.book_clubs
for each row execute function public.protect_book_club_moderator_update();

create or replace function public.protect_book_club_member_management()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_club_id uuid;
begin
  target_club_id := case when tg_op = 'DELETE' then old.club_id else new.club_id end;
  if public.owns_book_club(target_club_id) then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.role = 'Organizer' then
      raise exception 'Only the Organizer can assign the Organizer role.' using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' then
    if old.role = 'Organizer' or new.role = 'Organizer' then
      raise exception 'Only the Organizer can manage Organizer roster entries.' using errcode = '42501';
    end if;
  elsif old.role = 'Organizer' then
    raise exception 'Only the Organizer can remove an Organizer roster entry.' using errcode = '42501';
  end if;
  if public.is_book_club_moderator(target_club_id) then
    if tg_op = 'INSERT' then
      if new.account_user_id is not null then
        raise exception 'Moderators cannot link roster entries to user accounts.' using errcode = '42501';
      end if;
    elsif tg_op = 'UPDATE' then
      if new.account_user_id is distinct from old.account_user_id then
        raise exception 'Moderators cannot change linked user accounts.' using errcode = '42501';
      end if;
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists protect_book_club_member_management on public.book_club_members;
create trigger protect_book_club_member_management
before insert or update or delete on public.book_club_members
for each row execute function public.protect_book_club_member_management();

create or replace function public.can_join_book_club(target_club_id uuid, requested_role text)
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
      and open_enrollment = true
      and requested_role = 'Member'
  ) or exists (
    select 1
    from public.book_club_invitations
    where club_id = target_club_id
      and lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and role = requested_role
      and status = 'Pending'
      and (expires_at is null or expires_at > now())
  );
$$;

create or replace function public.has_book_club_invitation(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.book_club_invitations
    where club_id = target_club_id
      and lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and status = 'Pending'
      and (expires_at is null or expires_at > now())
  );
$$;

alter table public.book_club_members enable row level security;
alter table public.book_club_reads enable row level security;
alter table public.book_club_invitations enable row level security;

drop policy if exists "Users can read their own book clubs" on public.book_clubs;
drop policy if exists "Owners and members can read book clubs" on public.book_clubs;
create policy "Owners and members can read book clubs"
  on public.book_clubs for select
  using (open_enrollment = true or public.can_view_book_club(id) or public.has_book_club_invitation(id));

drop policy if exists "Users can update their own book clubs" on public.book_clubs;
drop policy if exists "Owners and moderators can update book clubs" on public.book_clubs;
create policy "Owners and moderators can update book clubs"
  on public.book_clubs for update
  using (public.can_moderate_book_club(id))
  with check (public.can_moderate_book_club(id));

drop policy if exists "Club members can read the roster" on public.book_club_members;
create policy "Club members can read the roster"
  on public.book_club_members for select
  using (public.can_view_book_club(club_id));

drop policy if exists "Club owners can add members" on public.book_club_members;
drop policy if exists "Club managers can add members" on public.book_club_members;
create policy "Club managers can add members"
  on public.book_club_members for insert
  with check (public.can_moderate_book_club(club_id));

drop policy if exists "Users can join open or invited clubs" on public.book_club_members;
create policy "Users can join open or invited clubs"
  on public.book_club_members for insert
  with check (
    account_user_id = auth.uid()
    and lower(trim(coalesce(email, ''))) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and public.can_join_book_club(club_id, role)
  );

drop policy if exists "Club owners can update members" on public.book_club_members;
drop policy if exists "Club managers can update members" on public.book_club_members;
create policy "Club managers can update members"
  on public.book_club_members for update
  using (public.can_moderate_book_club(club_id))
  with check (public.can_moderate_book_club(club_id));

drop policy if exists "Club owners can remove members" on public.book_club_members;
drop policy if exists "Club managers can remove members" on public.book_club_members;
create policy "Club managers can remove members"
  on public.book_club_members for delete
  using (public.can_moderate_book_club(club_id));

drop policy if exists "Club members can read selections" on public.book_club_reads;
create policy "Club members can read selections"
  on public.book_club_reads for select
  using (public.can_view_book_club(club_id));

drop policy if exists "Club owners can add selections" on public.book_club_reads;
drop policy if exists "Club managers can add selections" on public.book_club_reads;
create policy "Club managers can add selections"
  on public.book_club_reads for insert
  with check (public.can_moderate_book_club(club_id));

drop policy if exists "Club owners can update selections" on public.book_club_reads;
drop policy if exists "Club managers can update selections" on public.book_club_reads;
create policy "Club managers can update selections"
  on public.book_club_reads for update
  using (public.can_moderate_book_club(club_id))
  with check (public.can_moderate_book_club(club_id));

drop policy if exists "Club owners can remove selections" on public.book_club_reads;
drop policy if exists "Club managers can remove selections" on public.book_club_reads;
create policy "Club managers can remove selections"
  on public.book_club_reads for delete
  using (public.can_moderate_book_club(club_id));

drop policy if exists "Club owners can read invitations" on public.book_club_invitations;
create policy "Club owners can read invitations"
  on public.book_club_invitations for select
  using (public.owns_book_club(club_id));

drop policy if exists "Invitees can read their invitations" on public.book_club_invitations;
create policy "Invitees can read their invitations"
  on public.book_club_invitations for select
  using (
    lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and status = 'Pending'
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "Club owners can create invitations" on public.book_club_invitations;
create policy "Club owners can create invitations"
  on public.book_club_invitations for insert
  with check (public.owns_book_club(club_id) and invited_by = auth.uid());

drop policy if exists "Club owners can update invitations" on public.book_club_invitations;
create policy "Club owners can update invitations"
  on public.book_club_invitations for update
  using (public.owns_book_club(club_id))
  with check (public.owns_book_club(club_id));

drop policy if exists "Invitees can accept invitations" on public.book_club_invitations;
create policy "Invitees can accept invitations"
  on public.book_club_invitations for update
  using (
    lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and status = 'Pending'
    and (expires_at is null or expires_at > now())
  )
  with check (
    lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and status = 'Accepted'
    and accepted_by = auth.uid()
  );

drop policy if exists "Club owners can delete invitations" on public.book_club_invitations;
create policy "Club owners can delete invitations"
  on public.book_club_invitations for delete
  using (public.owns_book_club(club_id));

grant select, insert, update, delete on public.book_clubs to authenticated;
grant select, insert, update, delete on public.book_club_members to authenticated;
grant select, insert, update, delete on public.book_club_reads to authenticated;
grant select, insert, update, delete on public.book_club_invitations to authenticated;
grant execute on function public.owns_book_club(uuid) to authenticated;
grant execute on function public.is_book_club_moderator(uuid) to authenticated;
grant execute on function public.can_moderate_book_club(uuid) to authenticated;
grant execute on function public.can_view_book_club(uuid) to authenticated;
grant execute on function public.can_join_book_club(uuid, text) to authenticated;
grant execute on function public.has_book_club_invitation(uuid) to authenticated;

comment on table public.book_club_members is
  'Roster entries for a book club. account_user_id links a roster entry to a Reading Tracker account when invitations are added.';

comment on column public.book_club_members.timezone is
  'The member IANA time zone used to present club meeting times across locations.';

comment on table public.book_club_reads is
  'Current, upcoming, and completed club selections with reading and meeting details.';

comment on table public.book_club_invitations is
  'Email invitations with shareable tokens for joining private book clubs.';

comment on function public.can_moderate_book_club(uuid) is
  'Allows the club owner or an account-linked Moderator to manage club details, roster entries, selections, meetings, and discussions.';

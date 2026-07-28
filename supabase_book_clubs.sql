-- Creates user-owned book clubs and lets each book be assigned to one club.
-- Safe to run more than once.

create table if not exists public.book_clubs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_clubs_name_not_blank check (length(trim(name)) > 0)
);

create unique index if not exists book_clubs_user_name_unique
  on public.book_clubs (user_id, lower(trim(name)));

alter table public.book_clubs enable row level security;

drop policy if exists "Users can read their own book clubs" on public.book_clubs;
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

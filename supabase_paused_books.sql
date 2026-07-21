-- Adds a database-backed Paused status and records where reading stopped.
-- Safe to run more than once.

alter table public.books
  add column if not exists paused_page integer;

alter table public.books
  drop constraint if exists books_paused_page_check;

alter table public.books
  add constraint books_paused_page_check
  check (paused_page is null or paused_page > 0);

-- Keep existing On Hold books, but use the clearer Paused label everywhere.
update public.books
set status = 'Paused'
where status = 'On Hold';

update public.reading_sessions
set status = 'Paused'
where status = 'On Hold';

-- Preserve the existing system collection slug so saved routes and filters keep working.
update public.collections
set name = 'Paused'
where slug = 'on-hold'
  and is_system = true;

comment on column public.books.paused_page is
  'The one-based page where the reader paused this book; used when status is Paused.';

-- Add pause/resume history dates used by the reading calendars.
-- Safe to run more than once in the Supabase SQL Editor.

alter table public.books
  add column if not exists paused_on date,
  add column if not exists resumed_on date;

alter table public.books
  drop constraint if exists books_pause_dates_check;

alter table public.books
  add constraint books_pause_dates_check
  check (
    resumed_on is null
    or paused_on is null
    or resumed_on >= paused_on
  );

comment on column public.books.paused_on is
  'Date reading stopped for the current or most recent paused attempt.';

comment on column public.books.resumed_on is
  'Date reading resumed after the current or most recent pause.';

notify pgrst, 'reload schema';

-- Store audiobook length as whole minutes so the app can display it as hours and minutes.
alter table public.books
  add column if not exists duration_minutes integer;

alter table public.books
  drop constraint if exists books_duration_minutes_check;

alter table public.books
  add constraint books_duration_minutes_check
  check (duration_minutes is null or duration_minutes > 0);

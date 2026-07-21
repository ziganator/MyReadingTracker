-- Adds the three user-managed series statuses and keeps them in sync with book activity.
-- Safe to run more than once.

alter table public.series
  add column if not exists status text;

alter table public.series
  drop constraint if exists series_status_check;

update public.series as series_row
set status = case
  when lower(trim(coalesce(series_row.status, ''))) in ('abandoned', 'temporarily suspended', 'temp suspended', 'suspended')
    then 'Abandoned'
  when lower(trim(coalesce(series_row.status, ''))) in ('in progress', 'progress', 'completed')
    then 'In Progress'
  when lower(trim(coalesce(series_row.status, ''))) in ('not started', 'not-started')
    then 'Not Started'
  when exists (
    select 1
    from public.books as book_row
    where book_row.series_id = series_row.id
      and book_row.status in ('Currently Reading', 'Read')
  ) then 'In Progress'
  else 'Not Started'
end;

alter table public.series
  alter column status set default 'Not Started';

alter table public.series
  alter column status set not null;

alter table public.series
  add constraint series_status_check
  check (status in ('Not Started', 'In Progress', 'Abandoned'));

create or replace function public.promote_series_status_from_book()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.series_id is null or new.status not in ('Currently Reading', 'Read') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    update public.series
    set status = 'In Progress'
    where id = new.series_id
      and user_id = new.user_id
      and status in ('Not Started', 'Abandoned');
  elsif old.status is distinct from new.status
     or old.series_id is distinct from new.series_id then
    update public.series
    set status = 'In Progress'
    where id = new.series_id
      and user_id = new.user_id
      and status in ('Not Started', 'Abandoned');
  end if;
  return new;
end;
$$;

drop trigger if exists promote_series_status_from_book on public.books;

create trigger promote_series_status_from_book
after insert or update of status, series_id on public.books
for each row
execute function public.promote_series_status_from_book();

comment on column public.series.status is
  'User-managed series state: Not Started, In Progress, or Abandoned.';

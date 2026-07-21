-- Adds the four user-managed series statuses and keeps them in sync with book activity.
-- Safe to run more than once.

alter table public.series
  add column if not exists status text;

alter table public.series
  drop constraint if exists series_status_check;

update public.series as series_row
set status = case
  when lower(trim(coalesce(series_row.status, ''))) in ('abandoned', 'temporarily suspended', 'temp suspended', 'suspended')
    then 'Abandoned'
  when lower(trim(coalesce(series_row.status, ''))) = 'completed'
    then 'Completed'
  when lower(trim(coalesce(series_row.status, ''))) in ('in progress', 'progress')
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
  check (status in ('Not Started', 'In Progress', 'Completed', 'Abandoned'));

create or replace function public.refresh_series_status_from_books(
  target_series_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tracked_count integer := 0;
  read_count integer := 0;
  active_count integer := 0;
  planned_count integer := 0;
  current_status text;
begin
  if target_series_id is null then
    return;
  end if;

  select
    count(*),
    count(*) filter (where status = 'Read'),
    count(*) filter (where status in ('Currently Reading', 'Read'))
  into tracked_count, read_count, active_count
  from public.books
  where series_id = target_series_id
    and user_id = target_user_id
    and deleted_at is null;

  select coalesce(books_planned, 0), status
  into planned_count, current_status
  from public.series
  where id = target_series_id
    and user_id = target_user_id;

  if not found then
    return;
  end if;

  if tracked_count > 0
     and read_count = tracked_count
     and read_count >= greatest(1, planned_count) then
    update public.series
    set status = 'Completed'
    where id = target_series_id
      and user_id = target_user_id
      and status <> 'Completed';
  elsif active_count > 0
     and current_status in ('Not Started', 'Abandoned', 'Completed') then
    update public.series
    set status = 'In Progress'
    where id = target_series_id
      and user_id = target_user_id;
  elsif current_status = 'Completed' then
    update public.series
    set status = 'Not Started'
    where id = target_series_id
      and user_id = target_user_id;
  end if;
end;
$$;

create or replace function public.promote_series_status_from_book()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.series_id is not null then
      perform public.refresh_series_status_from_books(old.series_id, old.user_id);
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE'
     and old.series_id is distinct from new.series_id
     and old.series_id is not null then
    perform public.refresh_series_status_from_books(old.series_id, old.user_id);
  end if;

  if new.series_id is not null then
    perform public.refresh_series_status_from_books(new.series_id, new.user_id);
  end if;

  return new;
end;
$$;

drop trigger if exists promote_series_status_from_book on public.books;

create trigger promote_series_status_from_book
after insert or update of status, series_id, deleted_at or delete on public.books
for each row
execute function public.promote_series_status_from_book();

do $$
declare
  series_row record;
begin
  for series_row in
    select id, user_id
    from public.series
  loop
    perform public.refresh_series_status_from_books(series_row.id, series_row.user_id);
  end loop;
end;
$$;

comment on column public.series.status is
  'User-managed series state: Not Started, In Progress, Completed, or Abandoned.';

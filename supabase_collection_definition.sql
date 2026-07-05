alter table public.collections
  add column if not exists description text not null default '';

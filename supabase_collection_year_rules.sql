alter table public.collections
  add column if not exists publication_year_from integer,
  add column if not exists publication_year_to integer;


alter table public.books
  add column if not exists publisher text,
  add column if not exists publication_date date,
  add column if not exists page_count integer,
  add column if not exists language text;

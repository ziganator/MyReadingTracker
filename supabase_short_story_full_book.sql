alter table public.books
  add column if not exists full_book_read boolean not null default false;

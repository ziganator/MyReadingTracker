create table if not exists public.editions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete cascade,
  isbn_10 text,
  isbn_13 text,
  publisher text,
  binding text,
  page_count integer,
  language text,
  publication_date date,
  cover_url text,
  cover_small_url text,
  open_library_edition_id text,
  open_library_work_id text,
  google_books_volume_id text,
  provider_data jsonb not null default '{}'::jsonb,
  is_selected boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.books
  add column if not exists selected_edition_id uuid references public.editions(id) on delete set null;

create index if not exists editions_user_id_idx on public.editions(user_id);
create index if not exists editions_book_id_idx on public.editions(book_id);
create index if not exists editions_isbn_10_idx on public.editions(isbn_10);
create index if not exists editions_isbn_13_idx on public.editions(isbn_13);
create unique index if not exists editions_one_selected_per_book_idx
  on public.editions(book_id)
  where is_selected;

alter table public.editions enable row level security;

drop policy if exists "Users can read their editions" on public.editions;
create policy "Users can read their editions"
  on public.editions for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their editions" on public.editions;
create policy "Users can insert their editions"
  on public.editions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their editions" on public.editions;
create policy "Users can update their editions"
  on public.editions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their editions" on public.editions;
create policy "Users can delete their editions"
  on public.editions for delete
  using (auth.uid() = user_id);

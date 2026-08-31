-- Separate the kind of work from the format of its edition.
-- Format: Book, E-Book, Audiobook, Graphic Novel
-- Type: Novel, Novella, Short Stories, Biography, Memoir, and so on.
alter table public.books
  add column if not exists work_type text;

-- Preserve the meaning of records created before Type existed.
update public.books
set work_type = case lower(trim(coalesce(format, '')))
  when 'novella' then 'Novella'
  when 'short story collection' then 'Short Stories'
  when 'short stories' then 'Short Stories'
  when 'short story' then 'Short Stories'
  when 'non-fiction' then 'General Nonfiction'
  when 'nonfiction' then 'General Nonfiction'
  else work_type
end
where work_type is null
  and lower(trim(coalesce(format, ''))) in ('novella', 'short story collection', 'short stories', 'short story', 'non-fiction', 'nonfiction');

-- Move those legacy work types out of the format field.
update public.books
set format = 'Book'
where lower(trim(coalesce(format, ''))) in ('novella', 'short story collection', 'short stories', 'short story', 'non-fiction', 'nonfiction');

-- Use one consistent spelling for the audiobook format.
update public.books
set format = 'Audiobook'
where lower(replace(trim(coalesce(format, '')), '-', '')) in ('audiobook', 'audio book');

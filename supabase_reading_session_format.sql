-- Stores the format used for each individual reading session.
-- Safe to run more than once.

alter table public.reading_sessions
  add column if not exists format text;

comment on column public.reading_sessions.format is
  'The format used for this reading attempt, such as Book, E-Book, or AudioBook.';

-- Existing sessions inherit the book format so historical reading statistics
-- continue to reflect the format that was previously recorded on the book.
update public.reading_sessions as session
set format = book.format
from public.books as book
where session.book_id = book.id
  and session.format is null
  and book.format is not null;

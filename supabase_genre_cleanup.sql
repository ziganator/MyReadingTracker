update public.books
set genre = 'Techno Thriller'
where user_id = auth.uid()
  and regexp_replace(lower(coalesce(genre, '')), '[^a-z0-9]+', '', 'g') in (
    'technothriller',
    'techthriller'
  );

update public.books
set genre = 'Sci-Fi'
where user_id = auth.uid()
  and regexp_replace(lower(coalesce(genre, '')), '[^a-z0-9]+', '', 'g') in (
    'scifi',
    'sciencefiction'
  );

update public.books
set genre = trim(regexp_replace(replace(genre, chr(160), ' '), '\s+', ' ', 'g'))
where user_id = auth.uid()
  and genre is not null
  and genre <> trim(regexp_replace(replace(genre, chr(160), ' '), '\s+', ' ', 'g'));

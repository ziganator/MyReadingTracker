-- Store each user's Reading Picker category choices with their account.
-- Run once in the Supabase SQL editor after supabase_user_settings.sql.

alter table public.user_settings
  add column if not exists picker_categories jsonb not null default '[]'::jsonb;


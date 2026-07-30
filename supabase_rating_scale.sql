-- Adds the per-account rating display scale.
-- Safe to run more than once.

alter table public.user_settings
  add column if not exists rating_scale smallint not null default 10;

alter table public.user_settings
  drop constraint if exists user_settings_rating_scale_check;

alter table public.user_settings
  add constraint user_settings_rating_scale_check
  check (rating_scale in (5, 10));

comment on column public.user_settings.rating_scale is
  'The rating scale shown to the user. Stored book ratings remain normalized to 10.';

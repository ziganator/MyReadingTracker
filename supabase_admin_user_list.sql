-- Allow the site administrator to view the registered tracker accounts.
-- The function deliberately returns only basic account/profile metadata and is
-- guarded by the signed-in JWT email; ordinary authenticated users get no rows.
create or replace function public.admin_list_tracker_users()
returns table (
  user_id uuid,
  email text,
  display_name text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  discoverable boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    u.id,
    u.email::text,
    coalesce(
      nullif(trim(sp.display_name), ''),
      nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
      nullif(split_part(u.email, '@', 1), '')
    ),
    u.created_at,
    u.last_sign_in_at,
    coalesce(sp.discoverable, false)
  from auth.users as u
  left join public.social_profiles as sp on sp.user_id = u.id
  where lower(trim(coalesce(auth.jwt() ->> 'email', ''))) = 'ziganator@gmail.com'
  order by u.created_at desc, u.email asc;
$$;

revoke all on function public.admin_list_tracker_users() from public, anon;
grant execute on function public.admin_list_tracker_users() to authenticated;

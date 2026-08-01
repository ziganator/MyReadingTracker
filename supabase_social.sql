-- Social profiles, friendships, feed posts, and likes for My Reading Tracker.
-- Safe to run more than once in the Supabase SQL editor.

create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  bio text,
  avatar_url text,
  discoverable boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint social_profiles_name_not_blank check (length(trim(display_name)) > 0)
);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'Pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  constraint friendships_different_people check (requester_id <> addressee_id),
  constraint friendships_status_check check (status in ('Pending', 'Accepted'))
);

create unique index if not exists friendships_unique_pair
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create index if not exists friendships_requester_status_idx
  on public.friendships (requester_id, status, created_at desc);

create index if not exists friendships_addressee_status_idx
  on public.friendships (addressee_id, status, created_at desc);

create table if not exists public.social_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  book_id uuid references public.books(id) on delete set null,
  book_title text,
  book_author text,
  cover_url text,
  rating numeric(4,2),
  thoughts text,
  visibility text not null default 'Friends',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint social_posts_content_check check (
    length(trim(coalesce(thoughts, ''))) > 0
    or length(trim(coalesce(book_title, ''))) > 0
  ),
  constraint social_posts_visibility_check check (visibility in ('Friends', 'Public')),
  constraint social_posts_rating_check check (rating is null or (rating >= 0 and rating <= 10))
);

create index if not exists social_posts_user_created_idx
  on public.social_posts (user_id, created_at desc);

create index if not exists social_posts_created_idx
  on public.social_posts (created_at desc);

create table if not exists public.social_post_likes (
  post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists social_post_likes_user_idx
  on public.social_post_likes (user_id, created_at desc);

create or replace function public.are_friends(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select left_user is not null
    and right_user is not null
    and auth.uid() in (left_user, right_user)
    and exists (
      select 1
      from public.friendships
      where status = 'Accepted'
        and (
          (requester_id = left_user and addressee_id = right_user)
          or (requester_id = right_user and addressee_id = left_user)
        )
    );
$$;

create or replace function public.has_social_connection(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select left_user is not null
    and right_user is not null
    and auth.uid() in (left_user, right_user)
    and exists (
      select 1
      from public.friendships
      where (requester_id = left_user and addressee_id = right_user)
         or (requester_id = right_user and addressee_id = left_user)
    );
$$;

create or replace function public.can_view_social_post(target_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.social_posts
    where id = target_post_id
      and (
        visibility = 'Public'
        or user_id = auth.uid()
        or public.are_friends(auth.uid(), user_id)
      )
  );
$$;

create or replace function public.touch_social_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_social_profiles_updated_at on public.social_profiles;
create trigger touch_social_profiles_updated_at
before update on public.social_profiles
for each row execute function public.touch_social_updated_at();

drop trigger if exists touch_social_posts_updated_at on public.social_posts;
create trigger touch_social_posts_updated_at
before update on public.social_posts
for each row execute function public.touch_social_updated_at();

create or replace function public.protect_friendship_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.requester_id is distinct from old.requester_id
     or new.addressee_id is distinct from old.addressee_id then
    raise exception 'Friendship participants cannot be changed.' using errcode = '42501';
  end if;
  if old.status <> 'Pending' or new.status <> 'Accepted' then
    raise exception 'A pending friend request can only be accepted.' using errcode = '42501';
  end if;
  new.accepted_at = coalesce(new.accepted_at, now());
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists protect_friendship_update on public.friendships;
create trigger protect_friendship_update
before update on public.friendships
for each row execute function public.protect_friendship_update();

create or replace function public.handle_new_social_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.social_profiles (user_id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      'Reader'
    )
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_social_profile_on_signup on auth.users;
create trigger create_social_profile_on_signup
after insert on auth.users
for each row execute function public.handle_new_social_user();

insert into public.social_profiles (user_id, display_name)
select
  id,
  coalesce(
    nullif(trim(raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(raw_user_meta_data ->> 'full_name'), ''),
    'Reader'
  )
from auth.users
on conflict (user_id) do nothing;

alter table public.social_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.social_posts enable row level security;
alter table public.social_post_likes enable row level security;

drop policy if exists "Readers can view social profiles" on public.social_profiles;
create policy "Readers can view social profiles"
  on public.social_profiles for select
  using (
    discoverable = true
    or user_id = auth.uid()
    or public.has_social_connection(auth.uid(), user_id)
  );

drop policy if exists "Readers can create their social profile" on public.social_profiles;
create policy "Readers can create their social profile"
  on public.social_profiles for insert
  with check (user_id = auth.uid());

drop policy if exists "Readers can update their social profile" on public.social_profiles;
create policy "Readers can update their social profile"
  on public.social_profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Readers can view their friendships" on public.friendships;
create policy "Readers can view their friendships"
  on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "Readers can send friend requests" on public.friendships;
create policy "Readers can send friend requests"
  on public.friendships for insert
  with check (
    requester_id = auth.uid()
    and status = 'Pending'
    and exists (
      select 1
      from public.social_profiles
      where user_id = addressee_id
        and discoverable = true
    )
  );

drop policy if exists "Readers can accept friend requests" on public.friendships;
create policy "Readers can accept friend requests"
  on public.friendships for update
  using (addressee_id = auth.uid() and status = 'Pending')
  with check (addressee_id = auth.uid() and status = 'Accepted');

drop policy if exists "Readers can remove their friendships" on public.friendships;
create policy "Readers can remove their friendships"
  on public.friendships for delete
  using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "Readers can view social posts" on public.social_posts;
create policy "Readers can view social posts"
  on public.social_posts for select
  using (
    visibility = 'Public'
    or user_id = auth.uid()
    or public.are_friends(auth.uid(), user_id)
  );

drop policy if exists "Readers can create social posts" on public.social_posts;
create policy "Readers can create social posts"
  on public.social_posts for insert
  with check (user_id = auth.uid());

drop policy if exists "Readers can update their social posts" on public.social_posts;
create policy "Readers can update their social posts"
  on public.social_posts for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Readers can delete their social posts" on public.social_posts;
create policy "Readers can delete their social posts"
  on public.social_posts for delete
  using (user_id = auth.uid());

drop policy if exists "Readers can view likes on visible posts" on public.social_post_likes;
create policy "Readers can view likes on visible posts"
  on public.social_post_likes for select
  using (public.can_view_social_post(post_id));

drop policy if exists "Readers can like visible posts" on public.social_post_likes;
create policy "Readers can like visible posts"
  on public.social_post_likes for insert
  with check (user_id = auth.uid() and public.can_view_social_post(post_id));

drop policy if exists "Readers can remove their likes" on public.social_post_likes;
create policy "Readers can remove their likes"
  on public.social_post_likes for delete
  using (user_id = auth.uid());

grant select, insert, update on public.social_profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert, update, delete on public.social_posts to authenticated;
grant select, insert, delete on public.social_post_likes to authenticated;
grant execute on function public.are_friends(uuid, uuid) to authenticated;
grant execute on function public.has_social_connection(uuid, uuid) to authenticated;
grant execute on function public.can_view_social_post(uuid) to authenticated;

comment on table public.social_profiles is
  'Public-facing Reading Tracker profiles. Email addresses remain private in auth.users.';

comment on table public.friendships is
  'Pending and accepted friendships between Reading Tracker accounts.';

comment on table public.social_posts is
  'Friends-only or public feed posts that can reference a book and include reading thoughts.';

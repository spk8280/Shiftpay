-- ShiftPay master admin: run once in Supabase → SQL Editor → New query → Run
-- Then make yourself admin (last line) with your ShiftPay username.

create table if not exists public.shiftpay_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.shiftpay_admins enable row level security; -- no policies: only the functions below can touch it

-- Announcement banner shown to everyone (replaces notice.json)
create table if not exists public.shiftpay_notice (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.shiftpay_notice enable row level security;
drop policy if exists "notice read" on public.shiftpay_notice;
create policy "notice read" on public.shiftpay_notice for select using (true);
grant select on public.shiftpay_notice to anon, authenticated;
insert into public.shiftpay_notice (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.shiftpay_admins where user_id = auth.uid());
$$;

create or replace function public.admin_users()
returns table (user_id uuid, username text, nickname text, created_at timestamptz, last_sign_in timestamptz,
  updated_at timestamptz, lang text, state text, pay_type text, freq text, pattern text, admin boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  return query
    select u.id, split_part(u.email::text, '@', 1), (u.raw_user_meta_data->>'nickname')::text,
      u.created_at, u.last_sign_in_at, s.updated_at,
      s.data->>'lang', s.data->>'state', s.data->>'payType', s.data->>'freq', s.data->>'pattern',
      exists (select 1 from public.shiftpay_admins a where a.user_id = u.id)
    from auth.users u left join public.shiftpay_state s on s.user_id = u.id
    order by u.created_at desc;
end; $$;

create or replace function public.admin_delete_user(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  if target = auth.uid() then raise exception 'cannot delete yourself here'; end if;
  delete from auth.users where id = target;
end; $$;

create or replace function public.admin_reset_password(target uuid, new_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  if length(new_password) < 6 then raise exception 'password too short'; end if;
  update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now()
    where id = target;
end; $$;

create or replace function public.admin_set_admin(target uuid, make boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  if target = auth.uid() and not make then raise exception 'cannot remove yourself'; end if;
  if make then insert into public.shiftpay_admins values (target) on conflict do nothing;
  else delete from public.shiftpay_admins where user_id = target; end if;
end; $$;

create or replace function public.admin_set_notice(d jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  insert into public.shiftpay_notice (id, data, updated_at) values (1, coalesce(d, '{}'::jsonb), now())
    on conflict (id) do update set data = excluded.data, updated_at = now();
end; $$;

revoke all on function public.is_admin(), public.admin_users(), public.admin_delete_user(uuid),
  public.admin_reset_password(uuid, text), public.admin_set_admin(uuid, boolean), public.admin_set_notice(jsonb) from public, anon;
grant execute on function public.is_admin(), public.admin_users(), public.admin_delete_user(uuid),
  public.admin_reset_password(uuid, text), public.admin_set_admin(uuid, boolean), public.admin_set_notice(jsonb) to authenticated;

-- Make yourself the master admin (replace YOUR_USERNAME):
-- insert into public.shiftpay_admins select id from auth.users where email = 'your_username@users.shiftpay.app' on conflict do nothing;

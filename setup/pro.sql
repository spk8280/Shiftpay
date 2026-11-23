-- ShiftPay Pro: who has Pro, and whether Pro features are locked yet. Run after admin.sql.

create table if not exists public.shiftpay_pro (
  user_id uuid primary key references auth.users(id) on delete cascade,
  until timestamptz,              -- null = forever (lifetime / comp)
  source text not null default 'admin',  -- admin, appstore, play, web
  updated_at timestamptz not null default now()
);
alter table public.shiftpay_pro enable row level security;
drop policy if exists "own pro read" on public.shiftpay_pro;
create policy "own pro read" on public.shiftpay_pro for select using (auth.uid() = user_id);
grant select on public.shiftpay_pro to authenticated;

-- App-wide switches anyone can read (pro_enforced=false: everything stays free)
create table if not exists public.shiftpay_config (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{"pro_enforced": false}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.shiftpay_config enable row level security;
drop policy if exists "config read" on public.shiftpay_config;
create policy "config read" on public.shiftpay_config for select using (true);
grant select on public.shiftpay_config to anon, authenticated;
insert into public.shiftpay_config (id) values (1) on conflict (id) do nothing;

create or replace function public.my_pro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.shiftpay_pro where user_id = auth.uid() and (until is null or until > now()))
      or public.is_admin();
$$;

create or replace function public.admin_set_pro(target uuid, make boolean, days int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  if make then
    insert into public.shiftpay_pro (user_id, until, source, updated_at)
      values (target, case when days is null then null else now() + make_interval(days => days) end, 'admin', now())
      on conflict (user_id) do update set until = excluded.until, source = 'admin', updated_at = now();
  else delete from public.shiftpay_pro where user_id = target; end if;
end; $$;

create or replace function public.admin_set_config(d jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  update public.shiftpay_config set data = data || coalesce(d, '{}'::jsonb), updated_at = now() where id = 1;
end; $$;

-- member list now also returns Pro status
drop function if exists public.admin_users();
create function public.admin_users()
returns table (user_id uuid, username text, nickname text, created_at timestamptz, last_sign_in timestamptz,
  updated_at timestamptz, lang text, state text, pay_type text, freq text, pattern text, admin boolean, pro_until timestamptz, pro boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  return query
    select u.id, split_part(u.email::text, '@', 1), (u.raw_user_meta_data->>'nickname')::text,
      u.created_at, u.last_sign_in_at, s.updated_at,
      s.data->>'lang', s.data->>'state', s.data->>'payType', s.data->>'freq', s.data->>'pattern',
      exists (select 1 from public.shiftpay_admins a where a.user_id = u.id),
      p.until, (p.user_id is not null and (p.until is null or p.until > now()))
    from auth.users u left join public.shiftpay_state s on s.user_id = u.id left join public.shiftpay_pro p on p.user_id = u.id
    order by u.created_at desc;
end; $$;

revoke all on function public.my_pro(), public.admin_set_pro(uuid, boolean, int), public.admin_set_config(jsonb), public.admin_users() from public, anon;
grant execute on function public.my_pro(), public.admin_set_pro(uuid, boolean, int), public.admin_set_config(jsonb), public.admin_users() to authenticated;

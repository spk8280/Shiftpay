-- ShiftPay accounts: run once in Supabase → SQL Editor → New query → Run

-- One row of app data per user
create table if not exists public.shiftpay_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

-- Each person can only see and change their own row
alter table public.shiftpay_state enable row level security;

drop policy if exists "own row read" on public.shiftpay_state;
drop policy if exists "own row insert" on public.shiftpay_state;
drop policy if exists "own row update" on public.shiftpay_state;
drop policy if exists "own row delete" on public.shiftpay_state;
create policy "own row read"   on public.shiftpay_state for select using (auth.uid() = user_id);
create policy "own row insert" on public.shiftpay_state for insert with check (auth.uid() = user_id);
create policy "own row update" on public.shiftpay_state for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own row delete" on public.shiftpay_state for delete using (auth.uid() = user_id);

-- "Delete account" button in the app (required by the App Store)
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

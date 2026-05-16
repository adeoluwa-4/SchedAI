create extension if not exists pgcrypto;

create table if not exists public.launch_list_signups (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  full_name text not null check (char_length(trim(full_name)) > 0),
  email text not null unique,
  phone_number text,
  source_page text not null default 'launch-list',
  status text not null default 'subscribed' check (status in ('subscribed', 'bounced', 'unsubscribed')),
  confirmation_email_sent_at timestamptz
);

create or replace function public.set_launch_list_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists launch_list_signups_set_updated_at on public.launch_list_signups;
create trigger launch_list_signups_set_updated_at
before update on public.launch_list_signups
for each row
execute function public.set_launch_list_updated_at();

revoke all on public.launch_list_signups from anon, authenticated;
alter table public.launch_list_signups enable row level security;

-- Sripadha Infrawish — investor portal
-- One profile row per auth user. Row Level Security ensures an investor can
-- only read/write their own row; staff view data via the Supabase dashboard.

create table if not exists public.investor_profiles (
  id                        uuid primary key references auth.users(id) on delete cascade,
  email                     text,
  full_name                 text,
  mobile                    text,
  aadhaar_number            text,
  pan_number                text,
  emergency_contact_name    text,
  emergency_contact_number  text,
  date_of_birth             date,
  anniversary_date          date,
  spouse_name               text,
  spouse_birthday           date,
  number_of_kids            integer not null default 0,
  kids                      jsonb   not null default '[]'::jsonb,   -- [{ "name": "...", "birthday": "YYYY-MM-DD" }]
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint pan_format     check (pan_number is null or pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  constraint aadhaar_format check (aadhaar_number is null or aadhaar_number ~ '^[0-9]{12}$'),
  constraint kids_count     check (number_of_kids between 0 and 12)
);

comment on table public.investor_profiles is 'Investor self-service profile (KYC + family details). Contains PII; access only via RLS.';

alter table public.investor_profiles enable row level security;

drop policy if exists "Investors can view own profile"   on public.investor_profiles;
drop policy if exists "Investors can insert own profile" on public.investor_profiles;
drop policy if exists "Investors can update own profile" on public.investor_profiles;

create policy "Investors can view own profile"
  on public.investor_profiles for select to authenticated
  using (auth.uid() = id);

create policy "Investors can insert own profile"
  on public.investor_profiles for insert to authenticated
  with check (auth.uid() = id);

create policy "Investors can update own profile"
  on public.investor_profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists investor_profiles_set_updated_at on public.investor_profiles;
create trigger investor_profiles_set_updated_at
  before update on public.investor_profiles
  for each row execute function public.set_updated_at();

-- create an empty profile the moment an investor signs up
create or replace function public.handle_new_investor()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.investor_profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', null))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created_investor on auth.users;
create trigger on_auth_user_created_investor
  after insert on auth.users
  for each row execute function public.handle_new_investor();

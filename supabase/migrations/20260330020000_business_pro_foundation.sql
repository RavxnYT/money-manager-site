alter table if exists public.profiles
add column if not exists business_mode_enabled boolean not null default false;

alter table if exists public.profiles
add column if not exists business_pro_status text not null default 'inactive';

alter table if exists public.profiles
add column if not exists business_pro_updated_at timestamptz;

alter table if exists public.profiles
add column if not exists business_pro_latest_expiration timestamptz;

alter table if exists public.profiles
add column if not exists business_pro_platform text;

alter table if exists public.profiles
add column if not exists active_workspace_kind text not null default 'personal';

alter table if exists public.profiles
drop constraint if exists profiles_active_workspace_kind_check;
alter table if exists public.profiles
add constraint profiles_active_workspace_kind_check check (
  active_workspace_kind in ('personal', 'organization')
);

create table if not exists public.organizations (
  id uuid primary key default uuid_generate_v4(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  slug text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_organizations_owner on public.organizations(owner_user_id);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index if not exists idx_organization_members_user on public.organization_members(user_id);

alter table if exists public.profiles
add column if not exists active_workspace_organization_id uuid references public.organizations(id) on delete set null;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

create or replace function public.is_organization_owner(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organizations o
    where o.id = p_organization_id
      and o.owner_user_id = p_user_id
  );
$$;

create or replace function public.is_organization_member(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.is_organization_owner(p_organization_id, p_user_id)
    or exists (
      select 1
      from public.organization_members m
      where m.organization_id = p_organization_id
        and m.user_id = p_user_id
    );
$$;

grant execute on function public.is_organization_owner(uuid, uuid) to authenticated;
grant execute on function public.is_organization_member(uuid, uuid) to authenticated;

drop policy if exists organizations_select_member on public.organizations;
drop policy if exists organizations_insert_owner on public.organizations;
drop policy if exists organizations_update_owner on public.organizations;
drop policy if exists organizations_delete_owner on public.organizations;
create policy organizations_select_member on public.organizations
for select using (
  public.is_organization_member(id, auth.uid())
);
create policy organizations_insert_owner on public.organizations
for insert with check (auth.uid() = owner_user_id);
create policy organizations_update_owner on public.organizations
for update using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy organizations_delete_owner on public.organizations
for delete using (auth.uid() = owner_user_id);

drop policy if exists organization_members_select_visible on public.organization_members;
drop policy if exists organization_members_insert_owner on public.organization_members;
drop policy if exists organization_members_update_owner on public.organization_members;
drop policy if exists organization_members_delete_owner on public.organization_members;
create policy organization_members_select_visible on public.organization_members
for select using (
  auth.uid() = user_id
  or public.is_organization_owner(organization_id, auth.uid())
);
create policy organization_members_insert_owner on public.organization_members
for insert with check (public.is_organization_owner(organization_id, auth.uid()));
create policy organization_members_update_owner on public.organization_members
for update using (public.is_organization_owner(organization_id, auth.uid()))
with check (public.is_organization_owner(organization_id, auth.uid()));
create policy organization_members_delete_owner on public.organization_members
for delete using (public.is_organization_owner(organization_id, auth.uid()));

-- Team collaboration (frozen v1): invites, co_owner role, seat caps, access on Pro lapse.
-- See docs/team-collaboration-v1.md. After apply, run 20260402103100_team_collaboration_rpcs.sql.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Invitations (accept token = row id)
-- ---------------------------------------------------------------------------
create table if not exists public.organization_invitations (
  id uuid primary key default gen_random_uuid (),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email_normalized text not null,
  invite_role text not null default 'member' check (invite_role in ('member', 'co_owner')),
  invited_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now (),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

create index if not exists idx_org_invites_org on public.organization_invitations (organization_id);
create index if not exists idx_org_invites_email on public.organization_invitations (organization_id, email_normalized);

alter table public.organization_invitations enable row level security;

-- ---------------------------------------------------------------------------
-- organization_members roles
-- ---------------------------------------------------------------------------
alter table public.organization_members
drop constraint if exists organization_members_role_check;

alter table public.organization_members
add constraint organization_members_role_check check (
  role in ('owner', 'co_owner', 'member', 'viewer', 'admin')
);

-- At most one co_owner row per organization (owner role is separate).
create or replace function public.enforce_organization_co_owner_cap ()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role = 'co_owner' or new.role = 'admin' then
    if exists (
      select 1
      from public.organization_members m
      where m.organization_id = new.organization_id
        and m.user_id <> new.user_id
        and m.role in ('co_owner', 'admin')
    ) then
      raise exception 'Only one co-owner is allowed per organization';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_org_members_co_owner on public.organization_members;
create trigger trg_org_members_co_owner
before insert or update of role on public.organization_members
for each row execute function public.enforce_organization_co_owner_cap ();

-- ---------------------------------------------------------------------------
-- Access: none | read | write
-- ---------------------------------------------------------------------------
create or replace function public.organization_billing_owner_subscription_writable (
  p_organization_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.organizations o
    join public.profiles p on p.id = o.owner_user_id
    where o.id = p_organization_id
      and lower(trim(coalesce(p.business_pro_status, 'inactive'))) in (
        'active', 'trial', 'lifetime', 'billing_issue', 'grace_period'
      )
  );
$$;

create or replace function public.organization_actor_role (
  p_organization_id uuid,
  p_actor_id uuid
)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_owner uuid;
  v_role text;
begin
  if p_organization_id is null or p_actor_id is null then
    return null;
  end if;

  select o.owner_user_id into v_owner
  from public.organizations o
  where o.id = p_organization_id;

  if v_owner is null then
    return null;
  end if;

  if v_owner = p_actor_id then
    return 'owner';
  end if;

  select m.role into v_role
  from public.organization_members m
  where m.organization_id = p_organization_id
    and m.user_id = p_actor_id;

  if v_role = 'admin' then
    return 'co_owner';
  end if;

  return v_role;
end;
$$;

create or replace function public.org_workspace_access_mode (
  p_organization_id uuid,
  p_actor_id uuid
)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_role text;
  v_pro_ok boolean;
begin
  if p_organization_id is null or p_actor_id is null then
    return 'none';
  end if;

  if not public.is_organization_member (p_organization_id, p_actor_id) then
    return 'none';
  end if;

  v_role := public.organization_actor_role (p_organization_id, p_actor_id);
  if v_role is null then
    return 'none';
  end if;

  v_pro_ok := public.organization_billing_owner_subscription_writable (p_organization_id);

  if v_pro_ok then
    return 'write';
  end if;

  if v_role in ('owner', 'co_owner') then
    return 'read';
  end if;

  return 'none';
end;
$$;

-- Ledger primary key user_id for org rows = organizations.owner_user_id
create or replace function public.workspace_row_subject_user_id (
  p_request_user_id uuid,
  p_organization_id uuid default null
)
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_organization_id is null then p_request_user_id
    else (
      select o.owner_user_id
      from public.organizations o
      where o.id = p_organization_id
    )
  end;
$$;

create or replace function public.assert_workspace_access (
  p_user_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid () is null then
    raise exception 'Unauthorized';
  end if;

  if p_organization_id is null then
    if auth.uid () <> p_user_id then
      raise exception 'Unauthorized';
    end if;
    return;
  end if;

  if public.org_workspace_access_mode (p_organization_id, auth.uid ()) <> 'write' then
    raise exception 'Workspace not found';
  end if;
end;
$$;

create or replace function public.assert_workspace_read (
  p_user_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
begin
  if auth.uid () is null then
    raise exception 'Unauthorized';
  end if;

  if p_organization_id is null then
    if auth.uid () <> p_user_id then
      raise exception 'Unauthorized';
    end if;
    return;
  end if;

  v_mode := public.org_workspace_access_mode (p_organization_id, auth.uid ());
  if v_mode not in ('read', 'write') then
    raise exception 'Workspace not found';
  end if;
end;
$$;

grant execute on function public.organization_billing_owner_subscription_writable (uuid) to authenticated;
grant execute on function public.organization_actor_role (uuid, uuid) to authenticated;
grant execute on function public.org_workspace_access_mode (uuid, uuid) to authenticated;
grant execute on function public.workspace_row_subject_user_id (uuid, uuid) to authenticated;
grant execute on function public.assert_workspace_read (uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Profile: block activating org when access level is none (e.g. member after lapse)
-- ---------------------------------------------------------------------------
create or replace function public.validate_profile_workspace_selection ()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.active_workspace_kind = 'organization' then
    if new.active_workspace_organization_id is null then
      raise exception 'Organization workspace requires an organization';
    end if;

    if not public.is_organization_member (new.active_workspace_organization_id, new.id) then
      raise exception 'Workspace not found';
    end if;

    if public.org_workspace_access_mode (new.active_workspace_organization_id, new.id) = 'none' then
      raise exception 'Workspace not available';
    end if;
  else
    new.active_workspace_organization_id := null;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS row helpers (replace can_manage_workspace_row)
-- ---------------------------------------------------------------------------
create or replace function public.workspace_row_is_org_owner_fk (
  p_row_user_id uuid,
  p_row_organization_id uuid
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_row_organization_id is not null
    and exists (
      select 1
      from public.organizations o
      where o.id = p_row_organization_id
        and o.owner_user_id = p_row_user_id
    );
$$;

create or replace function public.can_select_workspace_row (
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_row_organization_id is null then p_row_user_id = p_actor_id
    else public.workspace_row_is_org_owner_fk (p_row_user_id, p_row_organization_id)
      and public.org_workspace_access_mode (p_row_organization_id, p_actor_id) <> 'none'
  end;
$$;

create or replace function public.can_insert_workspace_row (
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_row_organization_id is null then p_row_user_id = p_actor_id
    else public.workspace_row_is_org_owner_fk (p_row_user_id, p_row_organization_id)
      and public.org_workspace_access_mode (p_row_organization_id, p_actor_id) = 'write'
  end;
$$;

create or replace function public.can_update_workspace_row (
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.can_insert_workspace_row (p_row_user_id, p_row_organization_id, p_actor_id);
$$;

create or replace function public.can_delete_workspace_row (
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_row_organization_id is null then p_row_user_id = p_actor_id
    else public.workspace_row_is_org_owner_fk (p_row_user_id, p_row_organization_id)
      and public.org_workspace_access_mode (p_row_organization_id, p_actor_id) = 'write'
      and public.organization_actor_role (p_row_organization_id, p_actor_id) in (
        'owner',
        'co_owner'
      )
  end;
$$;

grant execute on function public.can_select_workspace_row (uuid, uuid, uuid) to authenticated;
grant execute on function public.can_insert_workspace_row (uuid, uuid, uuid) to authenticated;
grant execute on function public.can_update_workspace_row (uuid, uuid, uuid) to authenticated;
grant execute on function public.can_delete_workspace_row (uuid, uuid, uuid) to authenticated;

create or replace function public.can_manage_workspace_row (
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.can_select_workspace_row (p_row_user_id, p_row_organization_id, p_actor_id)
    and (
      p_row_organization_id is null
      or public.org_workspace_access_mode (p_row_organization_id, p_actor_id) = 'write'
    );
$$;

-- ---------------------------------------------------------------------------
-- Table policies: split ALL into select / insert / update / delete
-- ---------------------------------------------------------------------------
drop policy if exists accounts_own_all on public.accounts;
create policy accounts_select on public.accounts for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy accounts_insert on public.accounts for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy accounts_update on public.accounts for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy accounts_delete on public.accounts for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists categories_own_all on public.categories;
create policy categories_select on public.categories for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy categories_insert on public.categories for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy categories_update on public.categories for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy categories_delete on public.categories for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists transactions_own_all on public.transactions;
drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select on public.transactions for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy transactions_insert on public.transactions for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy transactions_update on public.transactions for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy transactions_delete on public.transactions for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists budgets_own_all on public.budgets;
create policy budgets_select on public.budgets for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy budgets_insert on public.budgets for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy budgets_update on public.budgets for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy budgets_delete on public.budgets for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists savings_own_all on public.savings_goals;
create policy savings_select on public.savings_goals for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_insert on public.savings_goals for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_update on public.savings_goals for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_delete on public.savings_goals for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists recurring_own_all on public.recurring_transactions;
create policy recurring_select on public.recurring_transactions for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy recurring_insert on public.recurring_transactions for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy recurring_update on public.recurring_transactions for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy recurring_delete on public.recurring_transactions for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists bills_own_all on public.bill_reminders;
create policy bills_select on public.bill_reminders for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy bills_insert on public.bill_reminders for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy bills_update on public.bill_reminders for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy bills_delete on public.bill_reminders for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists savings_contrib_own_all on public.savings_goal_contributions;
create policy savings_contrib_select on public.savings_goal_contributions for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_contrib_insert on public.savings_goal_contributions for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_contrib_update on public.savings_goal_contributions for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy savings_contrib_delete on public.savings_goal_contributions for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists loans_own_all on public.loans;
create policy loans_select on public.loans for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy loans_insert on public.loans for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy loans_update on public.loans for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy loans_delete on public.loans for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists loan_payments_own_all on public.loan_payments;
create policy loan_payments_select on public.loan_payments for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy loan_payments_insert on public.loan_payments for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy loan_payments_update on public.loan_payments for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy loan_payments_delete on public.loan_payments for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

drop policy if exists support_events_own_all on public.support_events;
create policy support_events_select on public.support_events for select using (public.can_select_workspace_row (user_id, organization_id, auth.uid ()));
create policy support_events_insert on public.support_events for insert with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy support_events_update on public.support_events for update using (public.can_update_workspace_row (user_id, organization_id, auth.uid ())) with check (public.can_insert_workspace_row (user_id, organization_id, auth.uid ()));
create policy support_events_delete on public.support_events for delete using (public.can_delete_workspace_row (user_id, organization_id, auth.uid ()));

-- ---------------------------------------------------------------------------
-- organizations + organization_members policies
-- ---------------------------------------------------------------------------
drop policy if exists organizations_update_owner on public.organizations;
create policy organizations_update_managers on public.organizations for update using (
  public.is_organization_owner (id, auth.uid ())
  or public.organization_actor_role (id, auth.uid ()) in ('co_owner', 'admin')
) with check (
  public.is_organization_owner (id, auth.uid ())
  or public.organization_actor_role (id, auth.uid ()) in ('co_owner', 'admin')
);

drop policy if exists organization_members_select_visible on public.organization_members;
drop policy if exists organization_members_insert_owner on public.organization_members;
drop policy if exists organization_members_update_owner on public.organization_members;
drop policy if exists organization_members_delete_owner on public.organization_members;

create policy organization_members_select on public.organization_members for select using (public.is_organization_member (organization_id, auth.uid ()));

create policy organization_members_insert on public.organization_members for insert with check (
  public.is_organization_owner (organization_id, auth.uid ())
  or public.organization_actor_role (organization_id, auth.uid ()) in ('co_owner', 'admin')
);

create policy organization_members_update on public.organization_members for update using (
  public.is_organization_owner (organization_id, auth.uid ())
  or public.organization_actor_role (organization_id, auth.uid ()) in ('co_owner', 'admin')
) with check (
  public.is_organization_owner (organization_id, auth.uid ())
  or public.organization_actor_role (organization_id, auth.uid ()) in ('co_owner', 'admin')
);

-- Only billing owner may remove members (co_owner cannot remove owner)
create policy organization_members_delete on public.organization_members for delete using (
  public.is_organization_owner (organization_id, auth.uid ())
  or (
    public.organization_actor_role (organization_id, auth.uid ()) in ('co_owner', 'admin')
    and user_id <> (select o.owner_user_id from public.organizations o where o.id = organization_id)
  )
);

-- ---------------------------------------------------------------------------
-- Seat + invite RPCs
-- ---------------------------------------------------------------------------
create or replace function public._org_invite_member_slots_used (p_organization_id uuid)
returns integer
language sql
security definer
stable
set search_path = public
as $$
  select (
      (
        select count(*)::integer
        from public.organization_members m
        where m.organization_id = p_organization_id
          and m.role = 'member'
      )
      + (
        select count(*)::integer
        from public.organization_invitations i
        where i.organization_id = p_organization_id
          and i.invite_role = 'member'
          and i.revoked_at is null
          and i.expires_at > now ()
      )
    );
$$;

create or replace function public._org_invite_co_owner_slot_taken (p_organization_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.role in ('co_owner', 'admin')
  )
  or exists (
    select 1
    from public.organization_invitations i
    where i.organization_id = p_organization_id
      and i.invite_role = 'co_owner'
      and i.revoked_at is null
      and i.expires_at > now ()
  );
$$;

create or replace function public.create_organization_invitation (
  p_organization_id uuid,
  p_email text,
  p_invite_role text default 'member'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid ();
  v_norm text;
  v_role text;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'Unauthorized';
  end if;

  if not public.organization_billing_owner_subscription_writable (p_organization_id) then
    raise exception 'Subscription required to manage team';
  end if;

  if public.organization_actor_role (p_organization_id, v_actor) not in ('owner', 'co_owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  v_norm := lower(trim (coalesce (p_email, '')));
  if v_norm = '' then
    raise exception 'Email is required';
  end if;

  v_role := lower(trim (coalesce (p_invite_role, 'member')));
  if v_role not in ('member', 'co_owner') then
    raise exception 'Invalid invite role';
  end if;

  if v_role = 'member' then
    if public._org_invite_member_slots_used (p_organization_id) >= 5 then
      raise exception 'Member invite limit reached';
    end if;
  else
    if public._org_invite_co_owner_slot_taken (p_organization_id) then
      raise exception 'Co-owner slot is already filled or pending';
    end if;
  end if;

  insert into public.organization_invitations (
    organization_id,
    email_normalized,
    invite_role,
    invited_by,
    expires_at
  )
  values (
    p_organization_id,
    v_norm,
    v_role,
    v_actor,
    now () + interval '14 days'
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.revoke_organization_invitation (p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid ();
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'Unauthorized';
  end if;

  select organization_id into v_org
  from public.organization_invitations
  where id = p_invitation_id;

  if v_org is null then
    raise exception 'Invitation not found';
  end if;

  if public.organization_actor_role (v_org, v_actor) not in ('owner', 'co_owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  update public.organization_invitations
  set revoked_at = now ()
  where id = p_invitation_id;
end;
$$;

create or replace function public.accept_organization_invitation (p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid ();
  v_email text;
  r record;
begin
  if v_actor is null then
    raise exception 'Unauthorized';
  end if;

  select u.email::text into v_email
  from auth.users u
  where u.id = v_actor;

  if v_email is null or length(trim (v_email)) = 0 then
    raise exception 'No email on account';
  end if;

  select * into strict r
  from public.organization_invitations i
  where i.id = p_invitation_id;

  if r.revoked_at is not null then
    raise exception 'Invitation revoked';
  end if;

  if r.expires_at <= now () then
    raise exception 'Invitation expired';
  end if;

  if r.email_normalized <> lower(trim (v_email)) then
    raise exception 'This invite is for a different email address';
  end if;

  insert into public.organization_members (organization_id, user_id, role)
  values (r.organization_id, v_actor, r.invite_role)
  on conflict (organization_id, user_id) do update
    set role = excluded.role,
        updated_at = now ();

  update public.organization_invitations
  set revoked_at = coalesce (revoked_at, now ())
  where id = p_invitation_id;
end;
$$;

create or replace function public.update_organization_member_role (
  p_organization_id uuid,
  p_member_user_id uuid,
  p_new_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid ();
  v_role text;
  v_owner uuid;
begin
  if v_actor is null then
    raise exception 'Unauthorized';
  end if;

  if public.organization_actor_role (p_organization_id, v_actor) not in ('owner', 'co_owner', 'admin') then
    raise exception 'Forbidden';
  end if;

  select owner_user_id into v_owner
  from public.organizations
  where id = p_organization_id;

  if v_owner = p_member_user_id then
    raise exception 'Cannot change organization owner role';
  end if;

  v_role := lower(trim (coalesce (p_new_role, '')));
  if v_role not in ('member', 'co_owner') then
    raise exception 'Invalid role';
  end if;

  if v_role = 'co_owner' then
    if public._org_invite_co_owner_slot_taken (p_organization_id)
      and not exists (
        select 1
        from public.organization_members m
        where m.organization_id = p_organization_id
          and m.user_id = p_member_user_id
          and m.role in ('co_owner', 'admin')
      ) then
      raise exception 'Co-owner slot is already filled';
    end if;
  end if;

  update public.organization_members
  set role = v_role,
      updated_at = now ()
  where organization_id = p_organization_id
    and user_id = p_member_user_id;

  if not found then
    raise exception 'Member not found';
  end if;
end;
$$;

create or replace function public.organization_workspace_access_for_actor (
  p_organization_id uuid
)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when auth.uid () is null then 'none'
    else public.org_workspace_access_mode (p_organization_id, auth.uid ())
  end;
$$;

grant execute on function public.create_organization_invitation (uuid, text, text) to authenticated;
grant execute on function public.revoke_organization_invitation (uuid) to authenticated;
grant execute on function public.accept_organization_invitation (uuid) to authenticated;
grant execute on function public.update_organization_member_role (uuid, uuid, text) to authenticated;
grant execute on function public.organization_workspace_access_for_actor (uuid) to authenticated;

grant execute on function public.assert_workspace_access (uuid, uuid) to authenticated;

create or replace function public.assert_org_owner_or_co_owner_may_delete (
  p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_organization_id is null then
    return;
  end if;
  if public.organization_actor_role (p_organization_id, auth.uid ()) not in (
    'owner',
    'co_owner',
    'admin'
  ) then
    raise exception 'Forbidden';
  end if;
end;
$$;

grant execute on function public.assert_org_owner_or_co_owner_may_delete (uuid) to authenticated;

-- Invitation rows: managers can list; inserts/updates only via SECURITY DEFINER RPCs.
drop policy if exists organization_invitations_none on public.organization_invitations;
drop policy if exists organization_invitations_select_managers on public.organization_invitations;
create policy organization_invitations_select_managers on public.organization_invitations for select using (
  public.is_organization_owner (organization_id, auth.uid ())
  or public.organization_actor_role (organization_id, auth.uid ()) in ('co_owner', 'admin')
);


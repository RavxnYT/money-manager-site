-- Normalize organization roles so org_workspace_access_mode treats Owner/OWNER like owner.
-- Also treat billing user as owner if organizations.owner_user_id matches even when
-- organization_members.role is missing or odd (repair paths).

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
  v_norm text;
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

  if v_role is null then
    return null;
  end if;

  v_norm := lower(trim(v_role));

  if v_norm = 'admin' then
    return 'co_owner';
  end if;

  if v_norm in ('co-owner', 'coowner') then
    return 'co_owner';
  end if;

  return v_norm;
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
  if v_role is null or length(trim(v_role)) = 0 then
    return 'none';
  end if;

  v_pro_ok := public.organization_billing_owner_subscription_writable (p_organization_id);

  if v_pro_ok then
    return 'write';
  end if;

  if v_role in ('owner', 'co_owner', 'admin') then
    return 'read';
  end if;

  return 'none';
end;
$$;

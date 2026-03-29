-- Per-business default currency, member sort order for workspace list, reorder RPC.

alter table public.organizations
  add column if not exists currency_code text not null default 'USD',
  add column if not exists has_selected_currency boolean not null default false;

alter table public.organization_members
  add column if not exists sort_order integer not null default 0;

update public.organization_members om
set sort_order = sub.rn
from (
  select
    organization_id,
    user_id,
    row_number() over (
      partition by user_id
      order by created_at asc nulls last, organization_id asc
    ) as rn
  from public.organization_members
) sub
where om.organization_id = sub.organization_id
  and om.user_id = sub.user_id;

create or replace function public.reorder_my_workspace_organizations(p_ordered_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  i int;
  n int;
  oid uuid;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'Unauthorized';
  end if;
  n := coalesce(array_length(p_ordered_ids, 1), 0);
  for i in 1..n loop
    oid := p_ordered_ids[i];
    if not exists (
      select 1 from public.organizations o
      where o.id = oid and o.owner_user_id = uid
    ) then
      raise exception 'Unauthorized';
    end if;
    update public.organization_members
    set sort_order = i,
        updated_at = now()
    where organization_id = oid
      and user_id = uid;
  end loop;
end;
$$;

grant execute on function public.reorder_my_workspace_organizations(uuid[]) to authenticated;

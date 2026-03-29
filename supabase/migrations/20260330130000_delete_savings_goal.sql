-- Delete a savings goal only when current_amount is zero (contributions cascade).
-- When the goal still holds funds, the client refunds via refund_savings_progress first.

create or replace function public.delete_savings_goal(
  p_user_id uuid,
  p_goal_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current numeric;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select current_amount
  into v_current
  from public.savings_goals
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_current is null then
    raise exception 'Savings goal not found';
  end if;

  if coalesce(v_current, 0) > 0 then
    raise exception 'Savings goal still has a balance; refund it to an account first';
  end if;

  delete from public.savings_goals
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if not found then
    raise exception 'Savings goal not found';
  end if;
end;
$$;

grant execute on function public.delete_savings_goal(uuid, uuid, uuid) to authenticated;

-- Undo one recorded loan payment: delete its ledger transaction (reverting the
-- account balance) and remove the loan_payments row.

create or replace function public.reverse_loan_payment(
  p_user_id uuid,
  p_loan_payment_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select lp.transaction_id
  into v_tx_id
  from public.loan_payments lp
  where lp.id = p_loan_payment_id
    and lp.user_id = p_user_id
    and public.workspace_matches(lp.organization_id, p_organization_id);

  if not found then
    raise exception 'Loan payment not found';
  end if;

  if v_tx_id is null then
    raise exception
      'This payment cannot be reversed (missing ledger link). Try recording a new adjustment or contact support.';
  end if;

  if exists (
    select 1
    from public.transactions t
    where t.id = v_tx_id
      and t.user_id = p_user_id
      and public.workspace_matches(t.organization_id, p_organization_id)
  ) then
    perform public.delete_transaction_internal(
      p_user_id,
      v_tx_id,
      true,
      p_organization_id
    );
  end if;

  delete from public.loan_payments lp
  where lp.id = p_loan_payment_id
    and lp.user_id = p_user_id
    and public.workspace_matches(lp.organization_id, p_organization_id);
end;
$$;

grant execute on function public.reverse_loan_payment(uuid, uuid, uuid) to authenticated;

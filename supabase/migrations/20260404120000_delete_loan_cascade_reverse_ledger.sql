-- Deleting a loan must reverse every linked ledger row. Previously we only
-- deleted transactions reachable via loan_payments.transaction_id; when that
-- link was null (FK on delete set null, legacy imports, etc.) payment ledger
-- rows were skipped so balances were not refunded while history disappeared.

drop function if exists public.delete_loan_cascade(uuid);
drop function if exists public.delete_loan_cascade(uuid, uuid);

create or replace function public.delete_loan_cascade(
  p_loan_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_tx_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if not exists (
    select 1
    from public.loans l
    where l.id = p_loan_id
      and l.user_id = v_user_id
      and public.workspace_matches(l.organization_id, p_organization_id)
  ) then
    raise exception 'Loan not found';
  end if;

  for v_tx_id in
    select distinct x.id
    from (
      select lp.transaction_id as id
      from public.loan_payments lp
      where lp.loan_id = p_loan_id
        and lp.user_id = v_user_id
        and public.workspace_matches(lp.organization_id, p_organization_id)
        and lp.transaction_id is not null
      union all
      select t.id
      from public.transactions t
      where t.user_id = v_user_id
        and t.source_type = 'loan_payment'
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.source_ref_id in (
          select lp2.id
          from public.loan_payments lp2
          where lp2.loan_id = p_loan_id
            and lp2.user_id = v_user_id
            and public.workspace_matches(lp2.organization_id, p_organization_id)
        )
      union all
      select l.principal_transaction_id
      from public.loans l
      where l.id = p_loan_id
        and l.user_id = v_user_id
        and public.workspace_matches(l.organization_id, p_organization_id)
        and l.principal_transaction_id is not null
      union all
      select t.id
      from public.transactions t
      where t.user_id = v_user_id
        and t.source_type = 'loan_principal'
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.source_ref_id = p_loan_id
    ) x
    where x.id is not null
  loop
    if exists (
      select 1
      from public.transactions tr
      where tr.id = v_tx_id
        and tr.user_id = v_user_id
        and public.workspace_matches(tr.organization_id, p_organization_id)
    ) then
      perform public.delete_transaction_internal(
        v_user_id,
        v_tx_id,
        true,
        p_organization_id
      );
    end if;
  end loop;

  delete from public.loan_payments
  where loan_id = p_loan_id
    and user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  delete from public.loans
  where id = p_loan_id
    and user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

grant execute on function public.delete_loan_cascade(uuid, uuid) to authenticated;

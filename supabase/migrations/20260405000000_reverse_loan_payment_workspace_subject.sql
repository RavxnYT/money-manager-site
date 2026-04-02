-- Collaborators call reverse_loan_payment with p_user_id = auth.uid(); ledger rows use billing owner user_id.
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
  v_account_id uuid;
  v_amount numeric;
  v_payment_date date;
  v_lp_created timestamptz;
  v_direction text;
  v_expected_kind text;
  v_match_count bigint;
  v_sub uuid;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  if auth.uid() is distinct from p_user_id then
    raise exception 'Unauthorized';
  end if;

  v_sub := public.workspace_row_subject_user_id(auth.uid(), p_organization_id);
  perform public.assert_workspace_access(v_sub, p_organization_id);

  select
    lp.transaction_id,
    lp.account_id,
    lp.amount,
    lp.payment_date,
    lp.created_at,
    l.direction
  into
    v_tx_id,
    v_account_id,
    v_amount,
    v_payment_date,
    v_lp_created,
    v_direction
  from public.loan_payments lp
  inner join public.loans l
    on l.id = lp.loan_id
    and l.user_id = lp.user_id
    and public.workspace_matches(l.organization_id, lp.organization_id)
  where lp.id = p_loan_payment_id
    and lp.user_id = v_sub
    and public.workspace_matches(lp.organization_id, p_organization_id);

  if not found then
    raise exception 'Loan payment not found';
  end if;

  if v_tx_id is null then
    select t.id
    into v_tx_id
    from public.transactions t
    where t.user_id = v_sub
      and public.workspace_matches(t.organization_id, p_organization_id)
      and t.source_type = 'loan_payment'
      and t.source_ref_id = p_loan_payment_id
    order by t.created_at desc nulls last
    limit 1;
  end if;

  if v_tx_id is null and v_account_id is not null then
    v_expected_kind := case
      when v_direction = 'owed_to_me' then 'income'
      else 'expense'
    end;
    select count(*) into v_match_count
    from public.transactions t
    where t.user_id = v_sub
      and public.workspace_matches(t.organization_id, p_organization_id)
      and t.account_id = v_account_id
      and t.kind = v_expected_kind
      and t.amount = v_amount
      and t.source_type is null
      and t.category_id is null
      and t.transfer_account_id is null
      and (t.transaction_date at time zone 'utc')::date = v_payment_date;

    if v_match_count = 1 then
      select t.id
      into v_tx_id
      from public.transactions t
      where t.user_id = v_sub
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.account_id = v_account_id
        and t.kind = v_expected_kind
        and t.amount = v_amount
        and t.source_type is null
        and t.category_id is null
        and t.transfer_account_id is null
        and (t.transaction_date at time zone 'utc')::date = v_payment_date
      limit 1;
    elsif v_match_count > 1 then
      select t.id
      into v_tx_id
      from public.transactions t
      where t.user_id = v_sub
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.account_id = v_account_id
        and t.kind = v_expected_kind
        and t.amount = v_amount
        and t.source_type is null
        and t.category_id is null
        and t.transfer_account_id is null
        and (t.transaction_date at time zone 'utc')::date = v_payment_date
      order by abs(
        extract(
          epoch from (
                coalesce(t.created_at, t.transaction_date)
              - coalesce(v_lp_created, t.created_at, t.transaction_date)
          )
        )
      ) nulls last,
        t.created_at asc
      limit 1;
    end if;
  end if;

  if v_tx_id is null then
    raise exception
      'Could not find the account transaction for this payment. If it was recorded before ledger links existed, try adjusting the account balance manually or contact support.';
  end if;

  if exists (
    select 1
    from public.transactions t
    where t.id = v_tx_id
      and t.user_id = v_sub
      and public.workspace_matches(t.organization_id, p_organization_id)
  ) then
    perform public.delete_transaction_internal(
      v_sub,
      v_tx_id,
      true,
      p_organization_id
    );
  end if;

  delete from public.loan_payments lp
  where lp.id = p_loan_payment_id
    and lp.user_id = v_sub
    and public.workspace_matches(lp.organization_id, p_organization_id);
end;
$$;

grant execute on function public.reverse_loan_payment(uuid, uuid, uuid) to authenticated;

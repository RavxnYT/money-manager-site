-- When a loan principal (total_amount) is edited, keep the linked account balance
-- in sync: balance += old_total - new_total for both "they owe me" and "I owe them".
-- (Reducing principal adds back to the account; increasing principal removes from it.)

create or replace function public.update_loan(
  p_user_id uuid,
  p_loan_id uuid,
  p_person_name text,
  p_total_amount numeric,
  p_direction text,
  p_currency_code text,
  p_due_date date default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paid_so_far numeric;
  v_existing_direction text;
  v_existing_currency text;
  v_old_total numeric;
  v_principal_tx_id uuid;
  v_principal_account_id uuid;
  v_balance numeric;
  v_delta numeric;
  v_src text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_total_amount <= 0 then
    raise exception 'Total amount must be greater than zero';
  end if;

  select
    l.direction,
    upper(trim(coalesce(l.currency_code, ''))),
    l.total_amount,
    l.principal_transaction_id,
    l.principal_account_id
  into
    v_existing_direction,
    v_existing_currency,
    v_old_total,
    v_principal_tx_id,
    v_principal_account_id
  from public.loans l
  where l.id = p_loan_id and l.user_id = p_user_id;

  if v_existing_direction is null then
    raise exception 'Loan not found';
  end if;

  if p_direction <> v_existing_direction then
    raise exception 'Loan direction cannot be changed after creation';
  end if;

  if upper(trim(coalesce(p_currency_code, ''))) <> v_existing_currency then
    raise exception 'Loan currency cannot be changed after creation';
  end if;

  select coalesce(sum(lp.amount), 0)
  into v_paid_so_far
  from public.loan_payments lp
  where lp.loan_id = p_loan_id and lp.user_id = p_user_id;

  if p_total_amount < v_paid_so_far then
    raise exception 'Total amount cannot be lower than paid amount';
  end if;

  if v_principal_tx_id is not null
     and v_principal_account_id is not null
     and coalesce(v_old_total, 0) <> p_total_amount then
    v_delta := v_old_total - p_total_amount;

    select a.current_balance
    into v_balance
    from public.accounts a
    where a.id = v_principal_account_id and a.user_id = p_user_id;

    if v_balance is null then
      raise exception 'Principal account not found';
    end if;

    if coalesce(v_balance, 0) + v_delta < 0 then
      raise exception 'Insufficient balance in the principal account for this change';
    end if;

    select t.source_type
    into v_src
    from public.transactions t
    where t.id = v_principal_tx_id and t.user_id = p_user_id;

    if v_src is distinct from 'loan_principal' then
      raise exception 'Principal transaction is not linked correctly';
    end if;

    update public.transactions
    set amount = p_total_amount
    where id = v_principal_tx_id and user_id = p_user_id;

    update public.accounts
    set current_balance = current_balance + v_delta
    where id = v_principal_account_id and user_id = p_user_id;
  end if;

  update public.loans
  set person_name = p_person_name,
      total_amount = p_total_amount,
      due_date = p_due_date,
      note = p_note
  where id = p_loan_id and user_id = p_user_id;

  if not found then
    raise exception 'Loan not found';
  end if;
end;
$$;

create or replace function public.update_loan(
  p_user_id uuid,
  p_loan_id uuid,
  p_person_name text,
  p_total_amount numeric,
  p_direction text,
  p_currency_code text,
  p_due_date date default null,
  p_note text default null,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paid_so_far numeric;
  v_existing_direction text;
  v_existing_currency text;
  v_old_total numeric;
  v_principal_tx_id uuid;
  v_principal_account_id uuid;
  v_balance numeric;
  v_delta numeric;
  v_src text;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  if p_total_amount <= 0 then
    raise exception 'Total amount must be greater than zero';
  end if;

  select
    l.direction,
    upper(trim(coalesce(l.currency_code, ''))),
    l.total_amount,
    l.principal_transaction_id,
    l.principal_account_id
  into
    v_existing_direction,
    v_existing_currency,
    v_old_total,
    v_principal_tx_id,
    v_principal_account_id
  from public.loans l
  where l.id = p_loan_id
    and l.user_id = p_user_id
    and public.workspace_matches(l.organization_id, p_organization_id);

  if v_existing_direction is null then
    raise exception 'Loan not found';
  end if;

  if p_direction <> v_existing_direction then
    raise exception 'Loan direction cannot be changed after creation';
  end if;

  if upper(trim(coalesce(p_currency_code, ''))) <> v_existing_currency then
    raise exception 'Loan currency cannot be changed after creation';
  end if;

  select coalesce(sum(lp.amount), 0)
  into v_paid_so_far
  from public.loan_payments lp
  where lp.loan_id = p_loan_id
    and lp.user_id = p_user_id
    and public.workspace_matches(lp.organization_id, p_organization_id);

  if p_total_amount < v_paid_so_far then
    raise exception 'Total amount cannot be lower than paid amount';
  end if;

  if v_principal_tx_id is not null
     and v_principal_account_id is not null
     and coalesce(v_old_total, 0) <> p_total_amount then
    v_delta := v_old_total - p_total_amount;

    select a.current_balance
    into v_balance
    from public.accounts a
    where a.id = v_principal_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);

    if v_balance is null then
      raise exception 'Principal account not found';
    end if;

    if coalesce(v_balance, 0) + v_delta < 0 then
      raise exception 'Insufficient balance in the principal account for this change';
    end if;

    select t.source_type
    into v_src
    from public.transactions t
    where t.id = v_principal_tx_id
      and t.user_id = p_user_id
      and public.workspace_matches(t.organization_id, p_organization_id);

    if v_src is distinct from 'loan_principal' then
      raise exception 'Principal transaction is not linked correctly';
    end if;

    update public.transactions t
    set amount = p_total_amount
    where t.id = v_principal_tx_id
      and t.user_id = p_user_id
      and public.workspace_matches(t.organization_id, p_organization_id);

    update public.accounts a
    set current_balance = current_balance + v_delta
    where a.id = v_principal_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);
  end if;

  update public.loans
  set person_name = p_person_name,
      total_amount = p_total_amount,
      due_date = p_due_date,
      note = p_note
  where id = p_loan_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if not found then
    raise exception 'Loan not found';
  end if;
end;
$$;

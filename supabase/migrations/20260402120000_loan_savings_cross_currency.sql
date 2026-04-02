-- Allow loan payments and savings contributions from any account by applying
-- a separate book-keeping amount on the account (account currency) while
-- keeping loan_payments.amount / goal increments in loan / goal currency.

-- PG cannot add parameters with CREATE OR REPLACE; drop prior signatures first.
drop function if exists public.record_loan_payment(uuid, uuid, uuid, numeric, timestamptz, text);
drop function if exists public.record_loan_payment(uuid, uuid, uuid, numeric, timestamptz, text, uuid);
drop function if exists public.add_savings_progress(uuid, uuid, numeric, uuid, text);
drop function if exists public.add_savings_progress(uuid, uuid, numeric, uuid, text, uuid);

create or replace function public.add_savings_progress(
  p_user_id uuid,
  p_goal_id uuid,
  p_amount numeric,
  p_account_id uuid,
  p_note text default null,
  p_organization_id uuid default null,
  p_account_amount numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_balance numeric;
  v_account_currency text;
  v_goal_name text;
  v_goal_current numeric;
  v_goal_target numeric;
  v_goal_currency text;
  v_contribution_id uuid;
  v_tx_id uuid;
  v_account_debit numeric;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select current_balance, currency_code
  into v_current_balance, v_account_currency
  from public.accounts
  where id = p_account_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_current_balance is null then
    raise exception 'Account not found';
  end if;

  select name, current_amount, target_amount, currency_code
  into v_goal_name, v_goal_current, v_goal_target, v_goal_currency
  from public.savings_goals
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_goal_name is null then
    raise exception 'Savings goal not found';
  end if;

  v_account_debit := coalesce(p_account_amount, p_amount);

  if p_account_amount is null then
    if upper(coalesce(v_account_currency, '')) <> upper(coalesce(v_goal_currency, '')) then
      raise exception 'Selected account currency must match savings goal currency';
    end if;
  end if;

  if v_account_debit is null or v_account_debit <= 0 then
    raise exception 'Account debit amount must be positive';
  end if;

  if v_current_balance < v_account_debit then
    raise exception 'Insufficient balance in selected account';
  end if;

  if (v_goal_current + p_amount) > v_goal_target then
    raise exception 'Amount exceeds remaining savings goal';
  end if;

  update public.accounts
  set current_balance = current_balance - v_account_debit
  where id = p_account_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  update public.savings_goals
  set current_amount = current_amount + p_amount,
      is_completed = (current_amount + p_amount) >= target_amount
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  insert into public.savings_goal_contributions (
    user_id, organization_id, goal_id, account_id, amount, note
  ) values (
    p_user_id, p_organization_id, p_goal_id, p_account_id, p_amount, p_note
  ) returning id into v_contribution_id;

  insert into public.transactions (
    user_id,
    organization_id,
    account_id,
    category_id,
    kind,
    amount,
    source_type,
    source_ref_id,
    note,
    transaction_date,
    transfer_account_id
  ) values (
    p_user_id,
    p_organization_id,
    p_account_id,
    null,
    'expense',
    v_account_debit,
    'savings_contribution',
    v_contribution_id,
    coalesce(p_note, 'Savings contribution: ' || v_goal_name),
    now(),
    null
  ) returning id into v_tx_id;

  update public.savings_goal_contributions
  set transaction_id = v_tx_id
  where id = v_contribution_id;
end;
$$;

create or replace function public.record_loan_payment(
  p_user_id uuid,
  p_loan_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_payment_date timestamptz default now(),
  p_note text default null,
  p_organization_id uuid default null,
  p_account_amount numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_direction text;
  v_person_name text;
  v_total_amount numeric;
  v_paid_so_far numeric;
  v_kind text;
  v_note text;
  v_payment_id uuid;
  v_tx_id uuid;
  v_tx_amount numeric;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select l.direction, l.person_name, l.total_amount
  into v_direction, v_person_name, v_total_amount
  from public.loans l
  where l.id = p_loan_id
    and l.user_id = p_user_id
    and public.workspace_matches(l.organization_id, p_organization_id);

  if v_direction is null then
    raise exception 'Loan not found';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id = p_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id)
  ) then
    raise exception 'Account not found';
  end if;

  select coalesce(sum(lp.amount), 0)
  into v_paid_so_far
  from public.loan_payments lp
  where lp.loan_id = p_loan_id
    and lp.user_id = p_user_id
    and public.workspace_matches(lp.organization_id, p_organization_id);

  if p_amount > (v_total_amount - v_paid_so_far) then
    raise exception 'Amount exceeds remaining loan balance';
  end if;

  v_tx_amount := coalesce(p_account_amount, p_amount);
  if v_tx_amount is null or v_tx_amount <= 0 then
    raise exception 'Transaction amount must be positive';
  end if;

  insert into public.loan_payments (
    user_id, organization_id, loan_id, account_id, amount, payment_date, note
  ) values (
    p_user_id,
    p_organization_id,
    p_loan_id,
    p_account_id,
    p_amount,
    (coalesce(p_payment_date, now()) at time zone 'utc')::date,
    p_note
  ) returning id into v_payment_id;

  v_kind := case when v_direction = 'owed_to_me' then 'income' else 'expense' end;
  v_note := coalesce(
    p_note,
    case
      when v_direction = 'owed_to_me' then 'Loan payment received from ' || v_person_name
      else 'Loan payment sent to ' || v_person_name
    end
  );

  v_tx_id := public.create_transaction_internal(
    p_user_id,
    p_account_id,
    null,
    v_kind,
    v_tx_amount,
    coalesce(p_payment_date, now()),
    v_note,
    null,
    null,
    'loan_payment',
    v_payment_id,
    p_organization_id
  );

  update public.loan_payments
  set transaction_id = v_tx_id
  where id = v_payment_id;
end;
$$;

grant execute on function public.add_savings_progress(uuid, uuid, numeric, uuid, text, uuid, numeric) to authenticated;
grant execute on function public.record_loan_payment(uuid, uuid, uuid, numeric, timestamptz, text, uuid, numeric) to authenticated;

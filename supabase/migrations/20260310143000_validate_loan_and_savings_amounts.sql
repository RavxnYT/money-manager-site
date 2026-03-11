-- Enforce remaining-amount validations and loan editing constraints.

create or replace function public.add_savings_progress(
  p_user_id uuid,
  p_goal_id uuid,
  p_amount numeric,
  p_account_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_balance numeric;
  v_goal_name text;
  v_goal_current numeric;
  v_goal_target numeric;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select current_balance into v_current_balance
  from public.accounts
  where id = p_account_id and user_id = p_user_id;

  if v_current_balance is null then
    raise exception 'Account not found';
  end if;

  if v_current_balance < p_amount then
    raise exception 'Insufficient balance in selected account';
  end if;

  select name, current_amount, target_amount
  into v_goal_name, v_goal_current, v_goal_target
  from public.savings_goals
  where id = p_goal_id and user_id = p_user_id;

  if v_goal_name is null then
    raise exception 'Savings goal not found';
  end if;

  if (v_goal_current + p_amount) > v_goal_target then
    raise exception 'Amount exceeds remaining savings goal';
  end if;

  update public.accounts
  set current_balance = current_balance - p_amount
  where id = p_account_id and user_id = p_user_id;

  update public.savings_goals
  set current_amount = current_amount + p_amount,
      is_completed = (current_amount + p_amount) >= target_amount
  where id = p_goal_id and user_id = p_user_id;

  insert into public.savings_goal_contributions (
    user_id, goal_id, account_id, amount, note
  ) values (
    p_user_id, p_goal_id, p_account_id, p_amount, p_note
  );

  insert into public.transactions (
    user_id, account_id, category_id, kind, amount, note, transaction_date, transfer_account_id
  ) values (
    p_user_id,
    p_account_id,
    null,
    'expense',
    p_amount,
    coalesce(p_note, 'Savings contribution: ' || v_goal_name),
    current_date,
    null
  );
end;
$$;

create or replace function public.record_loan_payment(
  p_user_id uuid,
  p_loan_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_payment_date date default current_date,
  p_note text default null
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
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select l.direction, l.person_name, l.total_amount
  into v_direction, v_person_name, v_total_amount
  from public.loans l
  where l.id = p_loan_id and l.user_id = p_user_id;

  if v_direction is null then
    raise exception 'Loan not found';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id = p_account_id and a.user_id = p_user_id
  ) then
    raise exception 'Account not found';
  end if;

  select coalesce(sum(lp.amount), 0)
  into v_paid_so_far
  from public.loan_payments lp
  where lp.loan_id = p_loan_id and lp.user_id = p_user_id;

  if p_amount > (v_total_amount - v_paid_so_far) then
    raise exception 'Amount exceeds remaining loan balance';
  end if;

  insert into public.loan_payments (
    user_id, loan_id, account_id, amount, payment_date, note
  ) values (
    p_user_id, p_loan_id, p_account_id, p_amount, p_payment_date, p_note
  );

  v_kind := case when v_direction = 'owed_to_me' then 'income' else 'expense' end;
  v_note := coalesce(
    p_note,
    case
      when v_direction = 'owed_to_me' then 'Loan payment received from ' || v_person_name
      else 'Loan payment sent to ' || v_person_name
    end
  );

  perform public.create_transaction(
    p_user_id,
    p_account_id,
    null,
    v_kind,
    p_amount,
    p_payment_date::timestamptz,
    v_note,
    null
  );
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
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paid_so_far numeric;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_total_amount <= 0 then
    raise exception 'Total amount must be greater than zero';
  end if;

  select coalesce(sum(lp.amount), 0)
  into v_paid_so_far
  from public.loan_payments lp
  where lp.loan_id = p_loan_id and lp.user_id = p_user_id;

  if p_total_amount < v_paid_so_far then
    raise exception 'Total amount cannot be lower than paid amount';
  end if;

  update public.loans
  set person_name = p_person_name,
      total_amount = p_total_amount,
      direction = p_direction,
      currency_code = p_currency_code,
      due_date = p_due_date,
      note = p_note
  where id = p_loan_id and user_id = p_user_id;

  if not found then
    raise exception 'Loan not found';
  end if;
end;
$$;

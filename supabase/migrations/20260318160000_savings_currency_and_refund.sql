alter table if exists public.savings_goals
add column if not exists currency_code text not null default 'USD';

alter table if exists public.savings_goal_contributions
drop constraint if exists savings_goal_contributions_amount_check;
alter table if exists public.savings_goal_contributions
add constraint savings_goal_contributions_amount_check check (amount <> 0);

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
  v_account_currency text;
  v_goal_name text;
  v_goal_current numeric;
  v_goal_target numeric;
  v_goal_currency text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select current_balance, currency_code into v_current_balance, v_account_currency
  from public.accounts
  where id = p_account_id and user_id = p_user_id;

  if v_current_balance is null then
    raise exception 'Account not found';
  end if;

  if v_current_balance < p_amount then
    raise exception 'Insufficient balance in selected account';
  end if;

  select name, current_amount, target_amount, currency_code
  into v_goal_name, v_goal_current, v_goal_target, v_goal_currency
  from public.savings_goals
  where id = p_goal_id and user_id = p_user_id;

  if v_goal_name is null then
    raise exception 'Savings goal not found';
  end if;

  if upper(coalesce(v_account_currency, '')) <> upper(coalesce(v_goal_currency, '')) then
    raise exception 'Selected account currency must match savings goal currency';
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

create or replace function public.update_savings_goal(
  p_user_id uuid,
  p_goal_id uuid,
  p_name text,
  p_target_amount numeric,
  p_currency_code text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_amount numeric;
  v_existing_currency text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select current_amount, currency_code
  into v_current_amount, v_existing_currency
  from public.savings_goals
  where id = p_goal_id and user_id = p_user_id;

  if v_current_amount is null then
    raise exception 'Savings goal not found';
  end if;

  if p_target_amount <= 0 then
    raise exception 'Target amount must be greater than 0';
  end if;

  if p_target_amount < v_current_amount then
    raise exception 'Target amount cannot be lower than current savings';
  end if;

  if upper(coalesce(v_existing_currency, '')) <> upper(coalesce(p_currency_code, ''))
     and v_current_amount > 0 then
    raise exception 'Cannot change currency for a goal that already has saved funds';
  end if;

  update public.savings_goals
  set name = p_name,
      target_amount = p_target_amount,
      currency_code = upper(p_currency_code),
      is_completed = current_amount >= p_target_amount
  where id = p_goal_id and user_id = p_user_id;
end;
$$;

create or replace function public.refund_savings_progress(
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
  v_goal_name text;
  v_goal_current numeric;
  v_goal_currency text;
  v_account_currency text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_amount <= 0 then
    raise exception 'Refund amount must be greater than 0';
  end if;

  select name, current_amount, currency_code
  into v_goal_name, v_goal_current, v_goal_currency
  from public.savings_goals
  where id = p_goal_id and user_id = p_user_id;

  if v_goal_name is null then
    raise exception 'Savings goal not found';
  end if;

  if v_goal_current < p_amount then
    raise exception 'Refund amount exceeds current savings';
  end if;

  select currency_code into v_account_currency
  from public.accounts
  where id = p_account_id and user_id = p_user_id;

  if v_account_currency is null then
    raise exception 'Account not found';
  end if;

  if upper(coalesce(v_account_currency, '')) <> upper(coalesce(v_goal_currency, '')) then
    raise exception 'Selected account currency must match savings goal currency';
  end if;

  update public.savings_goals
  set current_amount = current_amount - p_amount,
      is_completed = (current_amount - p_amount) >= target_amount
  where id = p_goal_id and user_id = p_user_id;

  update public.accounts
  set current_balance = current_balance + p_amount
  where id = p_account_id and user_id = p_user_id;

  insert into public.savings_goal_contributions (
    user_id, goal_id, account_id, amount, note
  ) values (
    p_user_id, p_goal_id, p_account_id, -p_amount, coalesce(p_note, 'Savings refund')
  );

  insert into public.transactions (
    user_id, account_id, category_id, kind, amount, note, transaction_date, transfer_account_id
  ) values (
    p_user_id,
    p_account_id,
    null,
    'income',
    p_amount,
    coalesce(p_note, 'Savings refund: ' || v_goal_name),
    current_date,
    null
  );
end;
$$;

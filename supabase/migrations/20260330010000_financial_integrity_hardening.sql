-- Harden financial integrity for derived transactions, loans, and edge-case transfers.

alter table public.transactions
  add column if not exists source_type text;

alter table public.transactions
  add column if not exists source_ref_id uuid;

create index if not exists idx_transactions_source
  on public.transactions (user_id, source_type, source_ref_id);

alter table public.transactions
  drop constraint if exists transactions_source_type_check;

alter table public.transactions
  add constraint transactions_source_type_check check (
    source_type is null
    or source_type in ('savings_contribution', 'savings_refund', 'loan_principal', 'loan_payment')
  );

alter table public.savings_goal_contributions
  add column if not exists transaction_id uuid references public.transactions(id) on delete set null;

alter table public.loans
  add column if not exists principal_transaction_id uuid references public.transactions(id) on delete set null;

alter table public.loan_payments
  add column if not exists transaction_id uuid references public.transactions(id) on delete set null;

drop function if exists public.record_loan_payment(uuid, uuid, uuid, numeric, date, text);
drop function if exists public.execute_entity_transfer(uuid, text, uuid, text, uuid, numeric, uuid, numeric, date, text);

create or replace function public.create_transaction_internal(
  p_user_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_kind text,
  p_amount numeric,
  p_transaction_date timestamptz,
  p_note text,
  p_transfer_account_id uuid,
  p_transfer_credit_amount numeric default null,
  p_source_type text default null,
  p_source_ref_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_credit numeric;
  v_category_type text;
  v_source_currency text;
  v_source_balance numeric;
  v_dest_currency text;
  v_dest_balance numeric;
  v_normalized_source_type text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;

  if p_kind not in ('income', 'expense', 'transfer') then
    raise exception 'Invalid transaction kind';
  end if;

  select upper(trim(coalesce(a.currency_code, ''))), a.current_balance
  into v_source_currency, v_source_balance
  from public.accounts a
  where a.id = p_account_id and a.user_id = p_user_id;

  if v_source_currency is null or v_source_currency = '' then
    raise exception 'Account not found';
  end if;

  v_normalized_source_type := nullif(lower(trim(coalesce(p_source_type, ''))), '');
  if v_normalized_source_type is not null
     and v_normalized_source_type not in (
       'savings_contribution',
       'savings_refund',
       'loan_principal',
       'loan_payment'
     ) then
    raise exception 'Invalid transaction source';
  end if;

  if (v_normalized_source_type is null and p_source_ref_id is not null)
     or (v_normalized_source_type is not null and p_source_ref_id is null) then
    raise exception 'Transaction source reference mismatch';
  end if;

  if p_kind = 'transfer' then
    if p_transfer_account_id is null or p_transfer_account_id = p_account_id then
      raise exception 'Invalid transfer accounts';
    end if;

    if p_category_id is not null then
      raise exception 'Transfers cannot use categories';
    end if;

    select upper(trim(coalesce(a.currency_code, '')))
    into v_dest_currency
    from public.accounts a
    where a.id = p_transfer_account_id and a.user_id = p_user_id;

    if v_dest_currency is null or v_dest_currency = '' then
      raise exception 'Transfer account not found';
    end if;

    if v_source_currency <> v_dest_currency then
      if p_transfer_credit_amount is null or p_transfer_credit_amount <= 0 then
        raise exception 'Cross-currency transfer requires a converted destination amount';
      end if;
    end if;

    v_credit := coalesce(p_transfer_credit_amount, p_amount);
    if v_credit <= 0 then
      raise exception 'Invalid transfer credit amount';
    end if;

    if coalesce(v_source_balance, 0) < p_amount then
      raise exception 'Insufficient balance in source account';
    end if;
  else
    if p_category_id is not null then
      select c.type
      into v_category_type
      from public.categories c
      where c.id = p_category_id and c.user_id = p_user_id;

      if v_category_type is null then
        raise exception 'Category not found';
      end if;

      if v_category_type <> p_kind then
        raise exception 'Category type must match transaction kind';
      end if;
    end if;

    v_credit := null;

    if p_kind = 'expense' and coalesce(v_source_balance, 0) < p_amount then
      raise exception 'Insufficient balance in account';
    end if;
  end if;

  insert into public.transactions (
    user_id,
    account_id,
    category_id,
    kind,
    amount,
    transfer_credit_amount,
    source_type,
    source_ref_id,
    note,
    transaction_date,
    transfer_account_id
  ) values (
    p_user_id,
    p_account_id,
    case when p_kind = 'transfer' then null else p_category_id end,
    p_kind,
    p_amount,
    case when p_kind = 'transfer' then v_credit else null end,
    v_normalized_source_type,
    p_source_ref_id,
    p_note,
    coalesce(p_transaction_date, now()),
    p_transfer_account_id
  ) returning id into v_id;

  if p_kind = 'expense' then
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_account_id and user_id = p_user_id;
  elsif p_kind = 'income' then
    update public.accounts
    set current_balance = current_balance + p_amount
    where id = p_account_id and user_id = p_user_id;
  else
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_account_id and user_id = p_user_id;

    update public.accounts
    set current_balance = current_balance + v_credit
    where id = p_transfer_account_id and user_id = p_user_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.create_transaction(
  p_user_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_kind text,
  p_amount numeric,
  p_transaction_date timestamptz,
  p_note text,
  p_transfer_account_id uuid,
  p_transfer_credit_amount numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.create_transaction_internal(
    p_user_id,
    p_account_id,
    p_category_id,
    p_kind,
    p_amount,
    p_transaction_date,
    p_note,
    p_transfer_account_id,
    p_transfer_credit_amount,
    null,
    null
  );
end;
$$;

create or replace function public.delete_transaction_internal(
  p_user_id uuid,
  p_transaction_id uuid,
  p_allow_linked boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_credit numeric;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select * into r
  from public.transactions
  where id = p_transaction_id and user_id = p_user_id;

  if not found then
    raise exception 'Transaction not found';
  end if;

  if not p_allow_linked and r.source_type is not null then
    raise exception 'This transaction is managed from its original feature and cannot be deleted here';
  end if;

  if r.kind = 'expense' then
    update public.accounts set current_balance = current_balance + r.amount
    where id = r.account_id and user_id = p_user_id;
  elsif r.kind = 'income' then
    update public.accounts set current_balance = current_balance - r.amount
    where id = r.account_id and user_id = p_user_id;
  elsif r.kind = 'transfer' then
    v_credit := coalesce(r.transfer_credit_amount, r.amount);
    update public.accounts set current_balance = current_balance + r.amount
    where id = r.account_id and user_id = p_user_id;
    update public.accounts set current_balance = current_balance - v_credit
    where id = r.transfer_account_id and user_id = p_user_id;
  end if;

  delete from public.transactions where id = p_transaction_id and user_id = p_user_id;
end;
$$;

create or replace function public.delete_transaction(
  p_user_id uuid,
  p_transaction_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_transaction_internal(p_user_id, p_transaction_id, false);
end;
$$;

create or replace function public.delete_account_cascade(p_account_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid;
  r record;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select a.user_id
  into v_user_id
  from public.accounts a
  where a.id = p_account_id;

  if v_user_id is null then
    raise exception 'Account not found';
  end if;

  if v_user_id <> auth.uid() then
    raise exception 'Forbidden';
  end if;

  for r in
    select t.id
    from public.transactions t
    where t.user_id = v_user_id
      and (t.account_id = p_account_id or t.transfer_account_id = p_account_id)
  loop
    perform public.delete_transaction_internal(v_user_id, r.id, true);
  end loop;

  delete from public.recurring_transactions
  where user_id = v_user_id and account_id = p_account_id;

  delete from public.bill_reminders
  where user_id = v_user_id and account_id = p_account_id;

  with del_contrib as (
    delete from public.savings_goal_contributions c
    where c.user_id = v_user_id and c.account_id = p_account_id
    returning c.goal_id
  ),
  goals_to_fix as (
    select distinct goal_id from del_contrib
  )
  update public.savings_goals g
  set
    current_amount = coalesce((
      select sum(c2.amount)
      from public.savings_goal_contributions c2
      where c2.goal_id = g.id
    ), 0),
    is_completed = coalesce((
      select sum(c2.amount)
      from public.savings_goal_contributions c2
      where c2.goal_id = g.id
    ), 0) >= g.target_amount
  where g.user_id = v_user_id
    and g.id in (select goal_id from goals_to_fix);

  delete from public.loan_payments
  where user_id = v_user_id and account_id = p_account_id;

  update public.loans
  set principal_account_id = null
  where user_id = v_user_id and principal_account_id = p_account_id;

  delete from public.accounts
  where id = p_account_id and user_id = v_user_id;
end;
$$;

create or replace function public.update_transaction(
  p_user_id uuid,
  p_transaction_id uuid,
  p_amount numeric,
  p_category_id uuid,
  p_note text,
  p_transfer_credit_amount numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_old_credit numeric;
  v_new_credit numeric;
  v_bal numeric;
  v_dest_bal numeric;
  v_cat text;
  v_src_cur text;
  v_dst_cur text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select * into r
  from public.transactions
  where id = p_transaction_id and user_id = p_user_id;

  if not found then
    raise exception 'Transaction not found';
  end if;

  if r.source_type is not null then
    raise exception 'This transaction is managed from its original feature and cannot be edited here';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;

  if r.kind <> 'transfer' then
    if p_category_id is not null then
      select c.type into v_cat
      from public.categories c
      where c.id = p_category_id and c.user_id = p_user_id;
      if v_cat is null then
        raise exception 'Category not found';
      end if;
      if v_cat <> r.kind then
        raise exception 'Category type must match transaction kind';
      end if;
    end if;
  end if;

  if r.kind = 'expense' then
    select a.current_balance into v_bal
    from public.accounts a
    where a.id = r.account_id and a.user_id = p_user_id;
    if coalesce(v_bal, 0) + r.amount - p_amount < 0 then
      raise exception 'Insufficient balance in account';
    end if;
    update public.accounts
    set current_balance = current_balance + r.amount - p_amount
    where id = r.account_id and user_id = p_user_id;

  elsif r.kind = 'income' then
    update public.accounts
    set current_balance = current_balance + p_amount - r.amount
    where id = r.account_id and user_id = p_user_id;

  elsif r.kind = 'transfer' then
    select upper(trim(coalesce(a.currency_code, '')))
    into v_src_cur
    from public.accounts a
    where a.id = r.account_id and a.user_id = p_user_id;

    select upper(trim(coalesce(a.currency_code, '')))
    into v_dst_cur
    from public.accounts a
    where a.id = r.transfer_account_id and a.user_id = p_user_id;

    if v_src_cur is null or v_src_cur = '' or v_dst_cur is null or v_dst_cur = '' then
      raise exception 'Transfer account not found';
    end if;

    if v_src_cur <> v_dst_cur
       and (p_transfer_credit_amount is null or p_transfer_credit_amount <= 0) then
      raise exception 'Cross-currency transfer requires a converted destination amount';
    end if;

    v_old_credit := coalesce(r.transfer_credit_amount, r.amount);
    v_new_credit := coalesce(p_transfer_credit_amount, p_amount);
    if v_new_credit <= 0 then
      raise exception 'Invalid transfer credit amount';
    end if;
    select a.current_balance into v_bal
    from public.accounts a
    where a.id = r.account_id and a.user_id = p_user_id;
    if coalesce(v_bal, 0) + r.amount - p_amount < 0 then
      raise exception 'Insufficient balance in source account';
    end if;
    select a.current_balance into v_dest_bal
    from public.accounts a
    where a.id = r.transfer_account_id and a.user_id = p_user_id;
    if coalesce(v_dest_bal, 0) - v_old_credit + v_new_credit < 0 then
      raise exception 'Insufficient balance in destination account';
    end if;
    update public.accounts
    set current_balance = current_balance + r.amount - p_amount
    where id = r.account_id and user_id = p_user_id;
    update public.accounts
    set current_balance = current_balance - v_old_credit + v_new_credit
    where id = r.transfer_account_id and user_id = p_user_id;
  else
    raise exception 'Invalid transaction kind';
  end if;

  update public.transactions
  set
    amount = p_amount,
    category_id = case when r.kind = 'transfer' then null else p_category_id end,
    note = p_note,
    transfer_credit_amount = case
      when r.kind = 'transfer' then coalesce(p_transfer_credit_amount, p_amount)
      else null
    end
  where id = p_transaction_id and user_id = p_user_id;
end;
$$;

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
  v_contribution_id uuid;
  v_tx_id uuid;
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
  ) returning id into v_contribution_id;

  insert into public.transactions (
    user_id,
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
    p_account_id,
    null,
    'expense',
    p_amount,
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
  v_contribution_id uuid;
  v_tx_id uuid;
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
  ) returning id into v_contribution_id;

  insert into public.transactions (
    user_id,
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
    p_account_id,
    null,
    'income',
    p_amount,
    'savings_refund',
    v_contribution_id,
    coalesce(p_note, 'Savings refund: ' || v_goal_name),
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
  v_payment_id uuid;
  v_tx_id uuid;
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
    p_user_id,
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
    p_amount,
    coalesce(p_payment_date, now()),
    v_note,
    null,
    null,
    'loan_payment',
    v_payment_id
  );

  update public.loan_payments
  set transaction_id = v_tx_id
  where id = v_payment_id;
end;
$$;

create or replace function public.create_loan(
  p_user_id uuid,
  p_person_name text,
  p_total_amount numeric,
  p_direction text,
  p_currency_code text,
  p_principal_account_id uuid,
  p_due_date date default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_acct_currency text;
  v_balance numeric;
  v_tx_note text;
  v_tx_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_total_amount is null or p_total_amount <= 0 then
    raise exception 'Total amount must be positive';
  end if;

  if p_person_name is null or length(trim(p_person_name)) = 0 then
    raise exception 'Person name is required';
  end if;

  if p_direction not in ('owed_to_me', 'owed_by_me') then
    raise exception 'Invalid loan direction';
  end if;

  if p_principal_account_id is null then
    raise exception 'Account is required to record loan principal';
  end if;

  select a.currency_code, a.current_balance
  into v_acct_currency, v_balance
  from public.accounts a
  where a.id = p_principal_account_id and a.user_id = p_user_id;

  if v_acct_currency is null then
    raise exception 'Account not found';
  end if;

  if upper(trim(coalesce(v_acct_currency, ''))) <>
     upper(trim(coalesce(p_currency_code, ''))) then
    raise exception 'Account currency must match loan currency';
  end if;

  insert into public.loans (
    user_id,
    person_name,
    total_amount,
    currency_code,
    direction,
    principal_account_id,
    note,
    due_date
  ) values (
    p_user_id,
    trim(p_person_name),
    p_total_amount,
    upper(trim(coalesce(p_currency_code, 'USD'))),
    p_direction,
    p_principal_account_id,
    nullif(trim(coalesce(p_note, '')), ''),
    p_due_date
  ) returning id into v_id;

  if p_direction = 'owed_by_me' then
    v_tx_note := coalesce(
      nullif(trim(coalesce(p_note, '')), ''),
      'Loan received — I owe ' || trim(p_person_name)
    );
    v_tx_id := public.create_transaction_internal(
      p_user_id,
      p_principal_account_id,
      null,
      'income',
      p_total_amount,
      now(),
      v_tx_note,
      null,
      null,
      'loan_principal',
      v_id
    );
  elsif p_direction = 'owed_to_me' then
    if coalesce(v_balance, 0) < p_total_amount then
      raise exception 'Insufficient balance in selected account for this loan';
    end if;
    v_tx_note := coalesce(
      nullif(trim(coalesce(p_note, '')), ''),
      'Loan given — ' || trim(p_person_name) || ' owes me'
    );
    v_tx_id := public.create_transaction_internal(
      p_user_id,
      p_principal_account_id,
      null,
      'expense',
      p_total_amount,
      now(),
      v_tx_note,
      null,
      null,
      'loan_principal',
      v_id
    );
  end if;

  update public.loans
  set principal_transaction_id = v_tx_id
  where id = v_id;

  return v_id;
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
  v_existing_direction text;
  v_existing_currency text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_total_amount <= 0 then
    raise exception 'Total amount must be greater than zero';
  end if;

  select l.direction, upper(trim(coalesce(l.currency_code, '')))
  into v_existing_direction, v_existing_currency
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

create or replace function public.delete_loan_cascade(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_principal_tx_id uuid;
  r record;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  select l.principal_transaction_id
  into v_principal_tx_id
  from public.loans l
  where l.id = p_loan_id and l.user_id = v_user_id;

  if not found then
    raise exception 'Loan not found';
  end if;

  for r in
    select lp.transaction_id
    from public.loan_payments lp
    where lp.loan_id = p_loan_id
      and lp.user_id = v_user_id
      and lp.transaction_id is not null
  loop
    if exists (
      select 1
      from public.transactions t
      where t.id = r.transaction_id and t.user_id = v_user_id
    ) then
      perform public.delete_transaction_internal(v_user_id, r.transaction_id, true);
    end if;
  end loop;

  delete from public.loan_payments
  where loan_id = p_loan_id and user_id = v_user_id;

  if v_principal_tx_id is not null
     and exists (
       select 1
       from public.transactions t
       where t.id = v_principal_tx_id and t.user_id = v_user_id
     ) then
    perform public.delete_transaction_internal(v_user_id, v_principal_tx_id, true);
  end if;

  delete from public.loans
  where id = p_loan_id and user_id = v_user_id;
end;
$$;

create or replace function public.execute_entity_transfer(
  p_user_id uuid,
  p_from_kind text,
  p_from_id uuid,
  p_to_kind text,
  p_to_id uuid,
  p_amount numeric,
  p_bridge_account_id uuid default null,
  p_transfer_credit_amount numeric default null,
  p_transaction_date timestamptz default now(),
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fk text := lower(trim(coalesce(p_from_kind, '')));
  v_tk text := lower(trim(coalesce(p_to_kind, '')));
  v_src_cur text;
  v_dst_cur text;
  v_loan_dir text;
  v_loan_cur text;
  v_credit numeric;
  v_g1_cur text;
  v_g2_cur text;
  v_br_cur text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;

  if v_fk not in ('account', 'savings_goal', 'loan')
     or v_tk not in ('account', 'savings_goal', 'loan') then
    raise exception 'Invalid transfer endpoint type';
  end if;

  if v_fk = v_tk and p_from_id = p_to_id then
    raise exception 'Source and destination must differ';
  end if;

  if v_fk = 'account' and v_tk = 'account' then
    if p_from_id = p_to_id then
      raise exception 'Cannot transfer to the same account';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_src_cur
    from accounts where id = p_from_id and user_id = p_user_id;
    select upper(trim(coalesce(currency_code, ''))) into v_dst_cur
    from accounts where id = p_to_id and user_id = p_user_id;
    if v_src_cur is null or v_src_cur = '' or v_dst_cur is null or v_dst_cur = '' then
      raise exception 'Account not found';
    end if;
    v_credit := coalesce(p_transfer_credit_amount, p_amount);
    if v_src_cur <> v_dst_cur then
      if p_transfer_credit_amount is null or p_transfer_credit_amount <= 0 then
        raise exception 'Cross-currency account transfer requires a positive converted amount for the destination';
      end if;
    end if;
    if v_credit <= 0 then
      raise exception 'Invalid transfer credit amount';
    end if;
    perform create_transaction(
      p_user_id,
      p_from_id,
      null,
      'transfer',
      p_amount,
      p_transaction_date,
      p_note,
      p_to_id,
      case when v_src_cur <> v_dst_cur then v_credit else null end
    );
    return;
  end if;

  if v_fk = 'account' and v_tk = 'savings_goal' then
    perform add_savings_progress(
      p_user_id, p_to_id, p_amount, p_from_id, p_note
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'account' then
    perform refund_savings_progress(
      p_user_id, p_from_id, p_amount, p_to_id, p_note
    );
    return;
  end if;

  if v_fk = 'account' and v_tk = 'loan' then
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans where id = p_to_id and user_id = p_user_id;
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_by_me' then
      raise exception 'Use an account payment only for loans you owe (I owe them)';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_src_cur
    from accounts where id = p_from_id and user_id = p_user_id;
    if v_src_cur is null or v_src_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_src_cur <> v_loan_cur then
      raise exception 'Account currency must match the loan currency';
    end if;
    perform record_loan_payment(
      p_user_id, p_to_id, p_from_id, p_amount, p_transaction_date, p_note
    );
    return;
  end if;

  if v_fk = 'loan' and v_tk = 'account' then
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans where id = p_from_id and user_id = p_user_id;
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_to_me' then
      raise exception 'Incoming payments apply only to loans they owe you';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_dst_cur
    from accounts where id = p_to_id and user_id = p_user_id;
    if v_dst_cur is null or v_dst_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_dst_cur <> v_loan_cur then
      raise exception 'Account currency must match the loan currency';
    end if;
    perform record_loan_payment(
      p_user_id, p_from_id, p_to_id, p_amount, p_transaction_date, p_note
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'savings_goal' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to move funds through';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_g1_cur
    from savings_goals where id = p_from_id and user_id = p_user_id;
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals where id = p_to_id and user_id = p_user_id;
    if v_g1_cur is null or v_g1_cur = '' or v_g2_cur is null or v_g2_cur = '' then
      raise exception 'Savings goal not found';
    end if;
    if v_g1_cur <> v_g2_cur then
      raise exception 'Both savings goals must use the same currency';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_br_cur
    from accounts where id = p_bridge_account_id and user_id = p_user_id;
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Bridge account not found';
    end if;
    if v_br_cur <> v_g1_cur then
      raise exception 'The account must match the savings currency';
    end if;
    perform refund_savings_progress(
      p_user_id, p_from_id, p_amount, p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Transfer between savings goals')
    );
    perform add_savings_progress(
      p_user_id, p_to_id, p_amount, p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Transfer between savings goals')
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'loan' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to route this payment through';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_g1_cur
    from savings_goals where id = p_from_id and user_id = p_user_id;
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans where id = p_to_id and user_id = p_user_id;
    if v_g1_cur is null or v_g1_cur = '' then
      raise exception 'Savings goal not found';
    end if;
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_by_me' then
      raise exception 'Pay toward only loans you owe (I owe them)';
    end if;
    if v_g1_cur <> v_loan_cur then
      raise exception 'Savings currency must match the loan currency';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_br_cur
    from accounts where id = p_bridge_account_id and user_id = p_user_id;
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_br_cur <> v_g1_cur then
      raise exception 'The account must match the savings and loan currency';
    end if;
    perform refund_savings_progress(
      p_user_id, p_from_id, p_amount, p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Savings to loan payment')
    );
    perform record_loan_payment(
      p_user_id, p_to_id, p_bridge_account_id, p_amount, p_transaction_date,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Savings to loan payment')
    );
    return;
  end if;

  if v_fk = 'loan' and v_tk = 'savings_goal' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to route this transfer through';
    end if;
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans where id = p_from_id and user_id = p_user_id;
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals where id = p_to_id and user_id = p_user_id;
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_to_me' then
      raise exception 'Only “they owe you” loans can fund savings this way';
    end if;
    if v_g2_cur is null or v_g2_cur = '' then
      raise exception 'Savings goal not found';
    end if;
    if v_loan_cur <> v_g2_cur then
      raise exception 'Loan and savings goal must share the same currency';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_br_cur
    from accounts where id = p_bridge_account_id and user_id = p_user_id;
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_br_cur <> v_loan_cur then
      raise exception 'The account must match the loan and savings currency';
    end if;
    perform record_loan_payment(
      p_user_id, p_from_id, p_bridge_account_id, p_amount, p_transaction_date,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Loan repayment to savings')
    );
    perform add_savings_progress(
      p_user_id, p_to_id, p_amount, p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Loan repayment to savings')
    );
    return;
  end if;

  raise exception 'This transfer combination is not supported';
end;
$$;

grant execute on function public.delete_account_cascade(uuid) to authenticated;
grant execute on function public.delete_loan_cascade(uuid) to authenticated;
grant execute on function public.record_loan_payment(uuid, uuid, uuid, numeric, timestamptz, text) to authenticated;
grant execute on function public.execute_entity_transfer(uuid, text, uuid, text, uuid, numeric, uuid, numeric, timestamptz, text) to authenticated;

with loan_candidates as (
  select
    l.id as loan_id,
    t.id as transaction_id,
    row_number() over (
      partition by l.id
      order by abs(extract(epoch from (t.created_at - l.created_at))), t.created_at, t.id
    ) as loan_rank,
    row_number() over (
      partition by t.id
      order by abs(extract(epoch from (t.created_at - l.created_at))), l.created_at, l.id
    ) as tx_rank
  from public.loans l
  join public.transactions t
    on t.user_id = l.user_id
   and t.account_id = l.principal_account_id
   and t.amount = l.total_amount
   and t.kind = case when l.direction = 'owed_by_me' then 'income' else 'expense' end
   and t.source_type is null
   and t.created_at between l.created_at - interval '30 seconds'
                        and l.created_at + interval '30 seconds'
)
update public.loans l
set principal_transaction_id = c.transaction_id
from loan_candidates c
where c.loan_rank = 1
  and c.tx_rank = 1
  and l.id = c.loan_id
  and l.principal_transaction_id is null;

update public.transactions t
set source_type = 'loan_principal',
    source_ref_id = l.id
from public.loans l
where l.principal_transaction_id = t.id
  and (t.source_type is null or t.source_type = 'loan_principal');

with payment_candidates as (
  select
    lp.id as payment_id,
    t.id as transaction_id,
    row_number() over (
      partition by lp.id
      order by abs(extract(epoch from (t.created_at - lp.created_at))), t.created_at, t.id
    ) as payment_rank,
    row_number() over (
      partition by t.id
      order by abs(extract(epoch from (t.created_at - lp.created_at))), lp.created_at, lp.id
    ) as tx_rank
  from public.loan_payments lp
  join public.transactions t
    on t.user_id = lp.user_id
   and t.account_id = lp.account_id
   and t.amount = lp.amount
   and t.kind in ('income', 'expense')
   and t.source_type is null
   and t.created_at between lp.created_at - interval '30 seconds'
                        and lp.created_at + interval '30 seconds'
)
update public.loan_payments lp
set transaction_id = c.transaction_id
from payment_candidates c
where c.payment_rank = 1
  and c.tx_rank = 1
  and lp.id = c.payment_id
  and lp.transaction_id is null;

update public.transactions t
set source_type = 'loan_payment',
    source_ref_id = lp.id
from public.loan_payments lp
where lp.transaction_id = t.id
  and (t.source_type is null or t.source_type = 'loan_payment');

with savings_candidates as (
  select
    c.id as contribution_id,
    t.id as transaction_id,
    row_number() over (
      partition by c.id
      order by abs(extract(epoch from (t.created_at - c.created_at))), t.created_at, t.id
    ) as contribution_rank,
    row_number() over (
      partition by t.id
      order by abs(extract(epoch from (t.created_at - c.created_at))), c.created_at, c.id
    ) as tx_rank
  from public.savings_goal_contributions c
  join public.transactions t
    on t.user_id = c.user_id
   and t.account_id = c.account_id
   and t.amount = abs(c.amount)
   and t.kind = case when c.amount > 0 then 'expense' else 'income' end
   and t.source_type is null
   and t.created_at between c.created_at - interval '30 seconds'
                        and c.created_at + interval '30 seconds'
)
update public.savings_goal_contributions c
set transaction_id = s.transaction_id
from savings_candidates s
where s.contribution_rank = 1
  and s.tx_rank = 1
  and c.id = s.contribution_id
  and c.transaction_id is null;

update public.transactions t
set source_type = case when c.amount > 0 then 'savings_contribution' else 'savings_refund' end,
    source_ref_id = c.id
from public.savings_goal_contributions c
where c.transaction_id = t.id
  and (t.source_type is null or t.source_type in ('savings_contribution', 'savings_refund'));

drop policy if exists transactions_own_all on public.transactions;
drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select_own on public.transactions
for select using (auth.uid() = user_id);

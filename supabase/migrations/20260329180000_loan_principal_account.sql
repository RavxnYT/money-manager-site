-- Link each loan to the account used for principal cash movement, and record
-- principal as a ledger entry so balances stay correct.

alter table public.loans
  add column if not exists principal_account_id uuid references public.accounts(id) on delete restrict;

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
    -- I borrowed: funds enter the selected account (income / credit).
    v_tx_note := coalesce(
      nullif(trim(coalesce(p_note, '')), ''),
      'Loan received — I owe ' || trim(p_person_name)
    );
    perform public.create_transaction(
      p_user_id,
      p_principal_account_id,
      null,
      'income',
      p_total_amount,
      now(),
      v_tx_note,
      null
    );
  elsif p_direction = 'owed_to_me' then
    -- I lent: funds leave the selected account (expense / debit).
    if coalesce(v_balance, 0) < p_total_amount then
      raise exception 'Insufficient balance in selected account for this loan';
    end if;
    v_tx_note := coalesce(
      nullif(trim(coalesce(p_note, '')), ''),
      'Loan given — ' || trim(p_person_name) || ' owes me'
    );
    perform public.create_transaction(
      p_user_id,
      p_principal_account_id,
      null,
      'expense',
      p_total_amount,
      now(),
      v_tx_note,
      null
    );
  end if;

  return v_id;
end;
$$;

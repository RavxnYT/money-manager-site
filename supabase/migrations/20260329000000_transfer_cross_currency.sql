-- Cross-currency transfers: debit source in source currency, credit destination in destination currency.

alter table public.transactions
  add column if not exists transfer_credit_amount numeric(14, 2) null;

update public.transactions
set transfer_credit_amount = amount
where kind = 'transfer' and transfer_credit_amount is null;

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
declare
  v_id uuid;
  v_credit numeric;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_kind = 'transfer' then
    if p_transfer_account_id is null or p_transfer_account_id = p_account_id then
      raise exception 'Invalid transfer accounts';
    end if;
    if p_amount is null or p_amount <= 0 then
      raise exception 'Invalid transfer amount';
    end if;
    v_credit := coalesce(p_transfer_credit_amount, p_amount);
    if v_credit <= 0 then
      raise exception 'Invalid transfer credit amount';
    end if;
  else
    v_credit := null;
  end if;

  insert into public.transactions (
    user_id,
    account_id,
    category_id,
    kind,
    amount,
    transaction_date,
    note,
    transfer_account_id,
    transfer_credit_amount
  ) values (
    p_user_id,
    p_account_id,
    p_category_id,
    p_kind,
    p_amount,
    coalesce(p_transaction_date, now()),
    p_note,
    p_transfer_account_id,
    case when p_kind = 'transfer' then v_credit else null end
  ) returning id into v_id;

  if p_kind = 'expense' then
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_account_id and user_id = p_user_id;
  elsif p_kind = 'income' then
    update public.accounts
    set current_balance = current_balance + p_amount
    where id = p_account_id and user_id = p_user_id;
  elsif p_kind = 'transfer' then
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_account_id and user_id = p_user_id;

    update public.accounts
    set current_balance = current_balance + v_credit
    where id = p_transfer_account_id and user_id = p_user_id;
  else
    raise exception 'Invalid transaction kind';
  end if;

  return v_id;
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

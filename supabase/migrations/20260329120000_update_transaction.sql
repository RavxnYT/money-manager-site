-- Apply in-place transaction edits with correct balance deltas (income, expense, transfer).

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
  v_cat text;
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

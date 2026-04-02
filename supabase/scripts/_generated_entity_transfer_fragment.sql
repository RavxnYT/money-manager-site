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
  p_note text default null,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub uuid;
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);
  v_sub := public.workspace_row_subject_user_id(p_user_id, p_organization_id);

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
    from accounts
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_dst_cur
    from accounts
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
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
      case when v_src_cur <> v_dst_cur then v_credit else null end,
      p_organization_id
    );
    return;
  end if;

  if v_fk = 'account' and v_tk = 'savings_goal' then
    perform add_savings_progress(
      p_user_id, p_to_id, p_amount, p_from_id, p_note, p_organization_id
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'account' then
    perform refund_savings_progress(
      p_user_id, p_from_id, p_amount, p_to_id, p_note, p_organization_id
    );
    return;
  end if;

  if v_fk = 'account' and v_tk = 'loan' then
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_by_me' then
      raise exception 'Use an account payment only for loans you owe (I owe them)';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_src_cur
    from accounts
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_src_cur is null or v_src_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_src_cur <> v_loan_cur then
      raise exception 'Account currency must match the loan currency';
    end if;
    perform record_loan_payment(
      p_user_id, p_to_id, p_from_id, p_amount, p_transaction_date, p_note, p_organization_id
    );
    return;
  end if;

  if v_fk = 'loan' and v_tk = 'account' then
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_loan_dir is null then
      raise exception 'Loan not found';
    end if;
    if v_loan_dir <> 'owed_to_me' then
      raise exception 'Incoming payments apply only to loans they owe you';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_dst_cur
    from accounts
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_dst_cur is null or v_dst_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_dst_cur <> v_loan_cur then
      raise exception 'Account currency must match the loan currency';
    end if;
    perform record_loan_payment(
      p_user_id, p_from_id, p_to_id, p_amount, p_transaction_date, p_note, p_organization_id
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'savings_goal' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to move funds through';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_g1_cur
    from savings_goals
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_g1_cur is null or v_g1_cur = '' or v_g2_cur is null or v_g2_cur = '' then
      raise exception 'Savings goal not found';
    end if;
    if v_g1_cur <> v_g2_cur then
      raise exception 'Both savings goals must use the same currency';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_br_cur
    from accounts
    where id = p_bridge_account_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Bridge account not found';
    end if;
    if v_br_cur <> v_g1_cur then
      raise exception 'The account must match the savings currency';
    end if;
    perform refund_savings_progress(
      p_user_id,
      p_from_id,
      p_amount,
      p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Transfer between savings goals'),
      p_organization_id
    );
    perform add_savings_progress(
      p_user_id,
      p_to_id,
      p_amount,
      p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Transfer between savings goals'),
      p_organization_id
    );
    return;
  end if;

  if v_fk = 'savings_goal' and v_tk = 'loan' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to route this payment through';
    end if;
    select upper(trim(coalesce(currency_code, ''))) into v_g1_cur
    from savings_goals
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
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
    from accounts
    where id = p_bridge_account_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_br_cur <> v_g1_cur then
      raise exception 'The account must match the savings and loan currency';
    end if;
    perform refund_savings_progress(
      p_user_id,
      p_from_id,
      p_amount,
      p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Savings to loan payment'),
      p_organization_id
    );
    perform record_loan_payment(
      p_user_id,
      p_to_id,
      p_bridge_account_id,
      p_amount,
      p_transaction_date,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Savings to loan payment'),
      p_organization_id
    );
    return;
  end if;

  if v_fk = 'loan' and v_tk = 'savings_goal' then
    if p_bridge_account_id is null then
      raise exception 'Choose an account to route this transfer through';
    end if;
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans
    where id = p_from_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals
    where id = p_to_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
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
    from accounts
    where id = p_bridge_account_id
      and user_id = v_sub
      and public.workspace_matches(organization_id, p_organization_id);
    if v_br_cur is null or v_br_cur = '' then
      raise exception 'Account not found';
    end if;
    if v_br_cur <> v_loan_cur then
      raise exception 'The account must match the loan and savings currency';
    end if;
    perform record_loan_payment(
      p_user_id,
      p_from_id,
      p_bridge_account_id,
      p_amount,
      p_transaction_date,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Loan repayment to savings'),
      p_organization_id
    );
    perform add_savings_progress(
      p_user_id,
      p_to_id,
      p_amount,
      p_bridge_account_id,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Loan repayment to savings'),
      p_organization_id
    );
    return;
  end if;

  raise exception 'This transfer combination is not supported';
end;
$$;

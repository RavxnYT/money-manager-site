

create extension if not exists "uuid-ossp";

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  currency_code text not null default 'USD',
  has_selected_currency boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table if exists public.profiles
add column if not exists has_selected_currency boolean not null default false;

alter table if exists public.profiles
add column if not exists business_mode_enabled boolean not null default false;

alter table if exists public.profiles
add column if not exists business_pro_status text not null default 'inactive';

alter table if exists public.profiles
add column if not exists business_pro_updated_at timestamptz;

alter table if exists public.profiles
add column if not exists business_pro_latest_expiration timestamptz;

alter table if exists public.profiles
add column if not exists business_pro_platform text;

alter table if exists public.profiles
add column if not exists active_workspace_kind text not null default 'personal';

alter table if exists public.profiles
drop constraint if exists profiles_active_workspace_kind_check;
alter table if exists public.profiles
add constraint profiles_active_workspace_kind_check check (
  active_workspace_kind in ('personal', 'organization')
);

create table if not exists public.organizations (
  id uuid primary key default uuid_generate_v4(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  slug text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_organizations_owner on public.organizations(owner_user_id);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index if not exists idx_organization_members_user on public.organization_members(user_id);

alter table if exists public.profiles
add column if not exists active_workspace_organization_id uuid references public.organizations(id) on delete set null;

create table if not exists public.accounts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  type text not null check (type in ('cash', 'bank', 'card', 'ewallet', 'other')),
  currency_code text not null default 'USD',
  opening_balance numeric(14, 2) not null default 0,
  current_balance numeric(14, 2) not null default 0,
  color_hex text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_accounts_user on public.accounts(user_id);

alter table if exists public.accounts
add column if not exists currency_code text not null default 'USD';

create table if not exists public.categories (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  type text not null check (type in ('income', 'expense')),
  icon text,
  color_hex text,
  is_default boolean not null default false,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, name, type)
);
create index if not exists idx_categories_user on public.categories(user_id);

create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  category_id uuid references public.categories(id) on delete set null,
  kind text not null check (kind in ('income', 'expense', 'transfer')),
  amount numeric(14, 2) not null check (amount > 0),
  transfer_credit_amount numeric(14, 2),
  source_type text,
  source_ref_id uuid,
  note text,
  transaction_date timestamptz not null default now(),
  transfer_account_id uuid references public.accounts(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (kind = 'transfer' and transfer_account_id is not null and transfer_account_id <> account_id) or
    (kind <> 'transfer' and transfer_account_id is null)
  )
);
alter table if exists public.transactions
add column if not exists source_type text;
alter table if exists public.transactions
add column if not exists source_ref_id uuid;
create index if not exists idx_transactions_user_date on public.transactions(user_id, transaction_date desc);
create index if not exists idx_transactions_source on public.transactions(user_id, source_type, source_ref_id);

alter table if exists public.transactions
drop constraint if exists transactions_source_type_check;
alter table if exists public.transactions
add constraint transactions_source_type_check check (
  source_type is null
  or source_type in ('savings_contribution', 'savings_refund', 'loan_principal', 'loan_payment')
);

create table if not exists public.budgets (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  month_start date not null,
  amount_limit numeric(14, 2) not null check (amount_limit > 0),
  created_at timestamptz not null default now(),
  unique (user_id, category_id, month_start)
);
create index if not exists idx_budgets_user_month on public.budgets(user_id, month_start);

create table if not exists public.savings_goals (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  target_amount numeric(14, 2) not null check (target_amount > 0),
  current_amount numeric(14, 2) not null default 0 check (current_amount >= 0),
  currency_code text not null default 'USD',
  target_date date,
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_goals_user on public.savings_goals(user_id);
alter table if exists public.savings_goals
add column if not exists currency_code text not null default 'USD';

create table if not exists public.recurring_transactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  category_id uuid references public.categories(id) on delete set null,
  kind text not null check (kind in ('income', 'expense')),
  amount numeric(14, 2) not null check (amount > 0),
  note text,
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  next_run_date date not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.bill_reminders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  amount numeric(14, 2) not null check (amount > 0),
  due_date date not null,
  frequency text not null check (frequency in ('once', 'weekly', 'monthly', 'yearly')),
  account_id uuid not null references public.accounts(id) on delete restrict,
  category_id uuid references public.categories(id) on delete set null,
  is_active boolean not null default true,
  last_paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_bills_user_due on public.bill_reminders(user_id, due_date);

create table if not exists public.savings_goal_contributions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  goal_id uuid not null references public.savings_goals(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  transaction_id uuid references public.transactions(id) on delete set null,
  amount numeric(14, 2) not null check (amount <> 0),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_savings_contrib_user_goal on public.savings_goal_contributions(user_id, goal_id, created_at desc);
alter table if exists public.savings_goal_contributions
drop constraint if exists savings_goal_contributions_amount_check;
alter table if exists public.savings_goal_contributions
add constraint savings_goal_contributions_amount_check check (amount <> 0);
alter table if exists public.savings_goal_contributions
add column if not exists transaction_id uuid references public.transactions(id) on delete set null;

create table if not exists public.loans (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  person_name text not null,
  total_amount numeric(14, 2) not null check (total_amount > 0),
  currency_code text not null default 'USD',
  direction text not null check (direction in ('owed_to_me', 'owed_by_me')),
  note text,
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_loans_user on public.loans(user_id);

alter table if exists public.loans
add column if not exists principal_account_id uuid references public.accounts(id) on delete restrict;
alter table if exists public.loans
add column if not exists principal_transaction_id uuid references public.transactions(id) on delete set null;

create table if not exists public.loan_payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  account_id uuid references public.accounts(id) on delete restrict,
  transaction_id uuid references public.transactions(id) on delete set null,
  amount numeric(14, 2) not null check (amount > 0),
  payment_date date not null default current_date,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_loan_payments_loan on public.loan_payments(loan_id, payment_date desc);

alter table if exists public.loan_payments
add column if not exists account_id uuid references public.accounts(id) on delete restrict;
alter table if exists public.loan_payments
add column if not exists transaction_id uuid references public.transactions(id) on delete set null;

create table if not exists public.support_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_support_events_user_created on public.support_events(user_id, created_at desc);

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.handle_updated_at();

drop trigger if exists trg_accounts_updated_at on public.accounts;
create trigger trg_accounts_updated_at
before update on public.accounts
for each row execute function public.handle_updated_at();

drop trigger if exists trg_transactions_updated_at on public.transactions;
create trigger trg_transactions_updated_at
before update on public.transactions
for each row execute function public.handle_updated_at();

drop trigger if exists trg_savings_updated_at on public.savings_goals;
create trigger trg_savings_updated_at
before update on public.savings_goals
for each row execute function public.handle_updated_at();

drop trigger if exists trg_bills_updated_at on public.bill_reminders;
create trigger trg_bills_updated_at
before update on public.bill_reminders
for each row execute function public.handle_updated_at();

drop trigger if exists trg_loans_updated_at on public.loans;
create trigger trg_loans_updated_at
before update on public.loans
for each row execute function public.handle_updated_at();

create or replace function public.seed_default_categories(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.categories (user_id, name, type, is_default) values
    (p_user_id, 'Salary', 'income', true),
    (p_user_id, 'Business', 'income', true),
    (p_user_id, 'Freelance', 'income', true),
    (p_user_id, 'Investments', 'income', true),
    (p_user_id, 'Interest', 'income', true),
    (p_user_id, 'Dividends', 'income', true),
    (p_user_id, 'Bonus', 'income', true),
    (p_user_id, 'Commission', 'income', true),
    (p_user_id, 'Overtime', 'income', true),
    (p_user_id, 'Rental Income', 'income', true),
    (p_user_id, 'Refund', 'income', true),
    (p_user_id, 'Cashback', 'income', true),
    (p_user_id, 'Gift Received', 'income', true),
    (p_user_id, 'Sale', 'income', true),
    (p_user_id, 'Side Hustle', 'income', true),
    (p_user_id, 'Allowance', 'income', true),
    (p_user_id, 'Pension', 'income', true),
    (p_user_id, 'Scholarship', 'income', true),
    (p_user_id, 'Other', 'income', true),
    (p_user_id, 'Food', 'expense', true),
    (p_user_id, 'Groceries', 'expense', true),
    (p_user_id, 'Dining Out', 'expense', true),
    (p_user_id, 'Coffee', 'expense', true),
    (p_user_id, 'Transport', 'expense', true),
    (p_user_id, 'Fuel', 'expense', true),
    (p_user_id, 'Parking', 'expense', true),
    (p_user_id, 'Taxi', 'expense', true),
    (p_user_id, 'Public Transport', 'expense', true),
    (p_user_id, 'Rent', 'expense', true),
    (p_user_id, 'Bills', 'expense', true),
    (p_user_id, 'Utilities', 'expense', true),
    (p_user_id, 'Mobile & Internet', 'expense', true),
    (p_user_id, 'Health', 'expense', true),
    (p_user_id, 'Pharmacy', 'expense', true),
    (p_user_id, 'Insurance', 'expense', true),
    (p_user_id, 'Education', 'expense', true),
    (p_user_id, 'Childcare', 'expense', true),
    (p_user_id, 'Pets', 'expense', true),
    (p_user_id, 'Home Maintenance', 'expense', true),
    (p_user_id, 'Electronics', 'expense', true),
    (p_user_id, 'Subscriptions', 'expense', true),
    (p_user_id, 'Streaming', 'expense', true),
    (p_user_id, 'Travel', 'expense', true),
    (p_user_id, 'Gifts', 'expense', true),
    (p_user_id, 'Donations', 'expense', true),
    (p_user_id, 'Beauty', 'expense', true),
    (p_user_id, 'Fitness', 'expense', true),
    (p_user_id, 'Sports', 'expense', true),
    (p_user_id, 'Clothing', 'expense', true),
    (p_user_id, 'Shoes', 'expense', true),
    (p_user_id, 'Taxes', 'expense', true),
    (p_user_id, 'Fees', 'expense', true),
    (p_user_id, 'Loan Payment', 'expense', true),
    (p_user_id, 'Debt Payment', 'expense', true),
    (p_user_id, 'Entertainment', 'expense', true),
    (p_user_id, 'Shopping', 'expense', true),
    (p_user_id, 'Other', 'expense', true)
  on conflict (user_id, name, type) do nothing;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));

  perform public.seed_default_categories(new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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

drop function if exists public.create_transaction(
  uuid,
  uuid,
  uuid,
  text,
  numeric,
  timestamptz,
  text,
  uuid
);

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

-- Removes an account and all dependent rows. Uses delete_transaction so balances stay correct.
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

grant execute on function public.delete_account_cascade(uuid) to authenticated;

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
    -- I borrowed: funds enter the selected account (income).
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
    -- I lent: funds leave the selected account (expense).
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

  -- account -> account
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

  -- account -> savings_goal
  if v_fk = 'account' and v_tk = 'savings_goal' then
    perform add_savings_progress(
      p_user_id, p_to_id, p_amount, p_from_id, p_note
    );
    return;
  end if;

  -- savings_goal -> account
  if v_fk = 'savings_goal' and v_tk = 'account' then
    perform refund_savings_progress(
      p_user_id, p_from_id, p_amount, p_to_id, p_note
    );
    return;
  end if;

  -- account -> loan (pay "I owe them")
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

  -- loan -> account (record repayment on "they owe me")
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

  -- savings_goal -> savings_goal
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

  -- savings_goal -> loan
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

  -- loan -> savings_goal
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

create or replace function public.run_due_recurring_transactions(
  p_user_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_next_date date;
  v_count integer := 0;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  for r in
    select *
    from public.recurring_transactions
    where user_id = p_user_id
      and is_active = true
      and next_run_date <= current_date
    order by next_run_date asc
  loop
    perform public.create_transaction(
      p_user_id,
      r.account_id,
      r.category_id,
      r.kind,
      r.amount,
      r.next_run_date::timestamptz,
      coalesce(r.note, 'Recurring transaction'),
      null
    );

    v_next_date :=
      case r.frequency
        when 'daily' then r.next_run_date + interval '1 day'
        when 'weekly' then r.next_run_date + interval '7 day'
        when 'monthly' then r.next_run_date + interval '1 month'
        when 'yearly' then r.next_run_date + interval '1 year'
      end;

    update public.recurring_transactions
    set next_run_date = v_next_date::date
    where id = r.id and user_id = p_user_id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function public.mark_bill_paid(
  p_user_id uuid,
  p_bill_id uuid,
  p_paid_on date default current_date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_next_due date;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select * into r
  from public.bill_reminders
  where id = p_bill_id and user_id = p_user_id;

  if not found then
    raise exception 'Bill reminder not found';
  end if;
  perform public.create_transaction(
    p_user_id,
    r.account_id,
    r.category_id,
    'expense',
    r.amount,
    p_paid_on::timestamptz,
    'Bill paid: ' || r.title,
    null
  );

  if r.frequency = 'once' then
    update public.bill_reminders
    set is_active = false,
        last_paid_at = now()
    where id = p_bill_id and user_id = p_user_id;
  else
    v_next_due :=
      case r.frequency
        when 'weekly' then r.due_date + interval '7 day'
        when 'monthly' then r.due_date + interval '1 month'
        when 'yearly' then r.due_date + interval '1 year'
      end;

    update public.bill_reminders
    set due_date = v_next_due,
        last_paid_at = now()
    where id = p_bill_id and user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.get_dashboard_summary(p_user_id uuid)
returns table (
  total_balance numeric,
  income_month numeric,
  expense_month numeric,
  savings_total numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  return query
  with month_bounds as (
    select date_trunc('month', now())::date as month_start
  )
  select
    coalesce((select sum(a.current_balance) from public.accounts a where a.user_id = p_user_id and a.is_archived = false), 0) as total_balance,
    coalesce((
      select sum(t.amount)
      from public.transactions t, month_bounds m
      where t.user_id = p_user_id and t.kind = 'income' and t.transaction_date >= m.month_start
    ), 0) as income_month,
    coalesce((
      select sum(t.amount)
      from public.transactions t, month_bounds m
      where t.user_id = p_user_id and t.kind = 'expense' and t.transaction_date >= m.month_start
    ), 0) as expense_month,
    coalesce((select sum(s.current_amount) from public.savings_goals s where s.user_id = p_user_id), 0) as savings_total;
end;
$$;

create or replace function public.exchange_account_currency(
  p_user_id uuid,
  p_account_id uuid,
  p_target_currency text,
  p_rate numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_rate is null or p_rate <= 0 then
    raise exception 'Invalid exchange rate';
  end if;

  update public.accounts
  set current_balance = round((current_balance * p_rate)::numeric, 2),
      opening_balance = round((opening_balance * p_rate)::numeric, 2),
      currency_code = p_target_currency
  where id = p_account_id and user_id = p_user_id;
end;
$$;

create or replace function public.delete_my_data(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  delete from public.loan_payments where user_id = p_user_id;
  delete from public.loans where user_id = p_user_id;
  delete from public.savings_goal_contributions where user_id = p_user_id;
  delete from public.transactions where user_id = p_user_id;
  delete from public.budgets where user_id = p_user_id;
  delete from public.recurring_transactions where user_id = p_user_id;
  delete from public.bill_reminders where user_id = p_user_id;
  delete from public.savings_goals where user_id = p_user_id;
  delete from public.support_events where user_id = p_user_id;
  delete from public.categories where user_id = p_user_id;
  delete from public.accounts where user_id = p_user_id;
end;
$$;

grant execute on function public.delete_account_cascade(uuid) to authenticated;
grant execute on function public.delete_loan_cascade(uuid) to authenticated;
grant execute on function public.record_loan_payment(uuid, uuid, uuid, numeric, timestamptz, text) to authenticated;
grant execute on function public.execute_entity_transfer(uuid, text, uuid, text, uuid, numeric, uuid, numeric, timestamptz, text) to authenticated;

-- Backfill links and source metadata for previously created savings/loan transactions.
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

create or replace function public.record_support_event(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  insert into public.support_events (user_id)
  values (p_user_id);
end;
$$;

create or replace function public.get_support_stats(
  p_user_id uuid
)
returns table (
  today_count bigint,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  return query
  select
    coalesce((
      select count(*)
      from public.support_events e
      where e.user_id = p_user_id
        and (e.created_at at time zone 'utc')::date = v_today
    ), 0) as today_count,
    coalesce((
      select count(*)
      from public.support_events e
      where e.user_id = p_user_id
    ), 0) as total_count;
end;
$$;

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.savings_goals enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.bill_reminders enable row level security;
alter table public.savings_goal_contributions enable row level security;
alter table public.loans enable row level security;
alter table public.loan_payments enable row level security;
alter table public.support_events enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

create or replace function public.is_organization_owner(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organizations o
    where o.id = p_organization_id
      and o.owner_user_id = p_user_id
  );
$$;

create or replace function public.is_organization_member(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.is_organization_owner(p_organization_id, p_user_id)
    or exists (
      select 1
      from public.organization_members m
      where m.organization_id = p_organization_id
        and m.user_id = p_user_id
    );
$$;

grant execute on function public.is_organization_owner(uuid, uuid) to authenticated;
grant execute on function public.is_organization_member(uuid, uuid) to authenticated;

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_select_own on public.profiles
for select using (auth.uid() = id);
create policy profiles_insert_own on public.profiles
for insert with check (auth.uid() = id);
create policy profiles_update_own on public.profiles
for update using (auth.uid() = id);

drop policy if exists accounts_own_all on public.accounts;
create policy accounts_own_all on public.accounts
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists categories_own_all on public.categories;
create policy categories_own_all on public.categories
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists transactions_own_all on public.transactions;
drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select_own on public.transactions
for select using (auth.uid() = user_id);

drop policy if exists budgets_own_all on public.budgets;
create policy budgets_own_all on public.budgets
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists savings_own_all on public.savings_goals;
create policy savings_own_all on public.savings_goals
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists recurring_own_all on public.recurring_transactions;
create policy recurring_own_all on public.recurring_transactions
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists bills_own_all on public.bill_reminders;
create policy bills_own_all on public.bill_reminders
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists savings_contrib_own_all on public.savings_goal_contributions;
create policy savings_contrib_own_all on public.savings_goal_contributions
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists loans_own_all on public.loans;
create policy loans_own_all on public.loans
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists loan_payments_own_all on public.loan_payments;
create policy loan_payments_own_all on public.loan_payments
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists support_events_own_all on public.support_events;
create policy support_events_own_all on public.support_events
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists organizations_select_member on public.organizations;
drop policy if exists organizations_insert_owner on public.organizations;
drop policy if exists organizations_update_owner on public.organizations;
drop policy if exists organizations_delete_owner on public.organizations;
create policy organizations_select_member on public.organizations
for select using (
  public.is_organization_member(id, auth.uid())
);
create policy organizations_insert_owner on public.organizations
for insert with check (auth.uid() = owner_user_id);
create policy organizations_update_owner on public.organizations
for update using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy organizations_delete_owner on public.organizations
for delete using (auth.uid() = owner_user_id);

drop policy if exists organization_members_select_visible on public.organization_members;
drop policy if exists organization_members_insert_owner on public.organization_members;
drop policy if exists organization_members_update_owner on public.organization_members;
drop policy if exists organization_members_delete_owner on public.organization_members;
create policy organization_members_select_visible on public.organization_members
for select using (
  auth.uid() = user_id
  or public.is_organization_owner(organization_id, auth.uid())
);
create policy organization_members_insert_owner on public.organization_members
for insert with check (public.is_organization_owner(organization_id, auth.uid()));
create policy organization_members_update_owner on public.organization_members
for update using (public.is_organization_owner(organization_id, auth.uid()))
with check (public.is_organization_owner(organization_id, auth.uid()));
create policy organization_members_delete_owner on public.organization_members
for delete using (public.is_organization_owner(organization_id, auth.uid()));

alter table if exists public.accounts
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.categories
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.transactions
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.budgets
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.savings_goals
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.recurring_transactions
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.bill_reminders
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.savings_goal_contributions
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.loans
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.loan_payments
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

alter table if exists public.support_events
add column if not exists organization_id uuid references public.organizations(id) on delete cascade;

create index if not exists idx_accounts_user_workspace
on public.accounts(user_id, organization_id);

create index if not exists idx_categories_user_workspace
on public.categories(user_id, organization_id);

create index if not exists idx_transactions_user_workspace_date
on public.transactions(user_id, organization_id, transaction_date desc);

create index if not exists idx_transactions_user_workspace_source
on public.transactions(user_id, organization_id, source_type, source_ref_id);

create index if not exists idx_budgets_user_workspace_month
on public.budgets(user_id, organization_id, month_start);

create index if not exists idx_goals_user_workspace
on public.savings_goals(user_id, organization_id);

create index if not exists idx_recurring_user_workspace_next_run
on public.recurring_transactions(user_id, organization_id, next_run_date);

create index if not exists idx_bills_user_workspace_due
on public.bill_reminders(user_id, organization_id, due_date);

create index if not exists idx_savings_contrib_user_workspace_goal
on public.savings_goal_contributions(user_id, organization_id, goal_id, created_at desc);

create index if not exists idx_loans_user_workspace
on public.loans(user_id, organization_id);

create index if not exists idx_loan_payments_user_workspace_date
on public.loan_payments(user_id, organization_id, payment_date desc, created_at desc);

create index if not exists idx_support_events_user_workspace_created
on public.support_events(user_id, organization_id, created_at desc);

alter table if exists public.categories
drop constraint if exists categories_user_id_name_type_key;

alter table if exists public.categories
drop constraint if exists categories_user_id_organization_id_name_type_key;

alter table if exists public.categories
add constraint categories_user_id_organization_id_name_type_key
unique nulls not distinct (user_id, organization_id, name, type);

create or replace function public.workspace_matches(
  p_row_organization_id uuid,
  p_scope_organization_id uuid
)
returns boolean
language sql
immutable
as $$
  select (p_row_organization_id is null and p_scope_organization_id is null)
    or p_row_organization_id = p_scope_organization_id;
$$;

create or replace function public.assert_workspace_access(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  if p_organization_id is not null
     and not public.is_organization_member(p_organization_id, p_user_id) then
    raise exception 'Workspace not found';
  end if;
end;
$$;

create or replace function public.can_manage_workspace_row(
  p_row_user_id uuid,
  p_row_organization_id uuid,
  p_actor_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select p_row_user_id = p_actor_id
    and (
      p_row_organization_id is null
      or public.is_organization_member(p_row_organization_id, p_actor_id)
    );
$$;

grant execute on function public.workspace_matches(uuid, uuid) to authenticated;
grant execute on function public.assert_workspace_access(uuid, uuid) to authenticated;
grant execute on function public.can_manage_workspace_row(uuid, uuid, uuid) to authenticated;

create or replace function public.validate_profile_workspace_selection()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.active_workspace_kind = 'organization' then
    if new.active_workspace_organization_id is null then
      raise exception 'Organization workspace requires an organization';
    end if;

    if not public.is_organization_member(new.active_workspace_organization_id, new.id) then
      raise exception 'Workspace not found';
    end if;
  else
    new.active_workspace_organization_id := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_profiles_validate_workspace on public.profiles;
create trigger trg_profiles_validate_workspace
before insert or update of active_workspace_kind, active_workspace_organization_id
on public.profiles
for each row execute function public.validate_profile_workspace_selection();

create or replace function public.seed_default_categories(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.categories (user_id, organization_id, name, type, is_default) values
    (p_user_id, p_organization_id, 'Salary', 'income', true),
    (p_user_id, p_organization_id, 'Business', 'income', true),
    (p_user_id, p_organization_id, 'Freelance', 'income', true),
    (p_user_id, p_organization_id, 'Investments', 'income', true),
    (p_user_id, p_organization_id, 'Interest', 'income', true),
    (p_user_id, p_organization_id, 'Dividends', 'income', true),
    (p_user_id, p_organization_id, 'Bonus', 'income', true),
    (p_user_id, p_organization_id, 'Commission', 'income', true),
    (p_user_id, p_organization_id, 'Overtime', 'income', true),
    (p_user_id, p_organization_id, 'Rental Income', 'income', true),
    (p_user_id, p_organization_id, 'Refund', 'income', true),
    (p_user_id, p_organization_id, 'Cashback', 'income', true),
    (p_user_id, p_organization_id, 'Gift Received', 'income', true),
    (p_user_id, p_organization_id, 'Sale', 'income', true),
    (p_user_id, p_organization_id, 'Side Hustle', 'income', true),
    (p_user_id, p_organization_id, 'Allowance', 'income', true),
    (p_user_id, p_organization_id, 'Pension', 'income', true),
    (p_user_id, p_organization_id, 'Scholarship', 'income', true),
    (p_user_id, p_organization_id, 'Other', 'income', true),
    (p_user_id, p_organization_id, 'Food', 'expense', true),
    (p_user_id, p_organization_id, 'Groceries', 'expense', true),
    (p_user_id, p_organization_id, 'Dining Out', 'expense', true),
    (p_user_id, p_organization_id, 'Coffee', 'expense', true),
    (p_user_id, p_organization_id, 'Transport', 'expense', true),
    (p_user_id, p_organization_id, 'Fuel', 'expense', true),
    (p_user_id, p_organization_id, 'Parking', 'expense', true),
    (p_user_id, p_organization_id, 'Taxi', 'expense', true),
    (p_user_id, p_organization_id, 'Public Transport', 'expense', true),
    (p_user_id, p_organization_id, 'Rent', 'expense', true),
    (p_user_id, p_organization_id, 'Bills', 'expense', true),
    (p_user_id, p_organization_id, 'Utilities', 'expense', true),
    (p_user_id, p_organization_id, 'Mobile & Internet', 'expense', true),
    (p_user_id, p_organization_id, 'Health', 'expense', true),
    (p_user_id, p_organization_id, 'Pharmacy', 'expense', true),
    (p_user_id, p_organization_id, 'Insurance', 'expense', true),
    (p_user_id, p_organization_id, 'Education', 'expense', true),
    (p_user_id, p_organization_id, 'Childcare', 'expense', true),
    (p_user_id, p_organization_id, 'Pets', 'expense', true),
    (p_user_id, p_organization_id, 'Home Maintenance', 'expense', true),
    (p_user_id, p_organization_id, 'Electronics', 'expense', true),
    (p_user_id, p_organization_id, 'Subscriptions', 'expense', true),
    (p_user_id, p_organization_id, 'Streaming', 'expense', true),
    (p_user_id, p_organization_id, 'Travel', 'expense', true),
    (p_user_id, p_organization_id, 'Gifts', 'expense', true),
    (p_user_id, p_organization_id, 'Donations', 'expense', true),
    (p_user_id, p_organization_id, 'Beauty', 'expense', true),
    (p_user_id, p_organization_id, 'Fitness', 'expense', true),
    (p_user_id, p_organization_id, 'Sports', 'expense', true),
    (p_user_id, p_organization_id, 'Clothing', 'expense', true),
    (p_user_id, p_organization_id, 'Shoes', 'expense', true),
    (p_user_id, p_organization_id, 'Taxes', 'expense', true),
    (p_user_id, p_organization_id, 'Fees', 'expense', true),
    (p_user_id, p_organization_id, 'Loan Payment', 'expense', true),
    (p_user_id, p_organization_id, 'Debt Payment', 'expense', true),
    (p_user_id, p_organization_id, 'Entertainment', 'expense', true),
    (p_user_id, p_organization_id, 'Shopping', 'expense', true),
    (p_user_id, p_organization_id, 'Other', 'expense', true)
  on conflict (user_id, organization_id, name, type) do nothing;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));

  perform public.seed_default_categories(new.id, null);
  return new;
end;
$$;

create or replace function public.create_business_workspace(
  p_user_id uuid,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_base_slug text;
  v_slug text;
  v_organization_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  v_name := nullif(trim(coalesce(p_name, '')), '');
  if v_name is null then
    raise exception 'Business name is required';
  end if;

  v_base_slug := trim(both '-' from regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g'));
  if v_base_slug is null or v_base_slug = '' then
    v_base_slug := 'business';
  end if;

  v_slug := v_base_slug || '-' || substr(
    replace(extensions.gen_random_uuid()::text, '-', ''),
    1,
    8
  );

  insert into public.organizations (
    owner_user_id,
    name,
    slug
  ) values (
    p_user_id,
    v_name,
    v_slug
  ) returning id into v_organization_id;

  insert into public.organization_members (
    organization_id,
    user_id,
    role
  ) values (
    v_organization_id,
    p_user_id,
    'owner'
  ) on conflict do nothing;

  update public.profiles
  set business_mode_enabled = true,
      active_workspace_kind = 'organization',
      active_workspace_organization_id = v_organization_id
  where id = p_user_id;

  perform public.seed_default_categories(p_user_id, v_organization_id);

  return v_organization_id;
end;
$$;

grant execute on function public.create_business_workspace(uuid, text) to authenticated;

create or replace function public.record_support_event(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  insert into public.support_events (user_id, organization_id)
  values (p_user_id, p_organization_id);
end;
$$;

create or replace function public.get_support_stats(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns table (
  today_count bigint,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  return query
  select
    coalesce((
      select count(*)
      from public.support_events e
      where e.user_id = p_user_id
        and public.workspace_matches(e.organization_id, p_organization_id)
        and (e.created_at at time zone 'utc')::date = v_today
    ), 0) as today_count,
    coalesce((
      select count(*)
      from public.support_events e
      where e.user_id = p_user_id
        and public.workspace_matches(e.organization_id, p_organization_id)
    ), 0) as total_count;
end;
$$;

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
  p_source_ref_id uuid default null,
  p_organization_id uuid default null
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
  v_normalized_source_type text;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be positive';
  end if;

  if p_kind not in ('income', 'expense', 'transfer') then
    raise exception 'Invalid transaction kind';
  end if;

  select upper(trim(coalesce(a.currency_code, ''))), a.current_balance
  into v_source_currency, v_source_balance
  from public.accounts a
  where a.id = p_account_id
    and a.user_id = p_user_id
    and public.workspace_matches(a.organization_id, p_organization_id);

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
    where a.id = p_transfer_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);

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
      where c.id = p_category_id
        and c.user_id = p_user_id
        and public.workspace_matches(c.organization_id, p_organization_id);

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
    organization_id,
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
    p_organization_id,
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
    where id = p_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  elsif p_kind = 'income' then
    update public.accounts
    set current_balance = current_balance + p_amount
    where id = p_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  else
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);

    update public.accounts
    set current_balance = current_balance + v_credit
    where id = p_transfer_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
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
  p_transfer_credit_amount numeric default null,
  p_organization_id uuid default null
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
    null,
    p_organization_id
  );
end;
$$;

create or replace function public.delete_transaction_internal(
  p_user_id uuid,
  p_transaction_id uuid,
  p_allow_linked boolean default false,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select *
  into r
  from public.transactions
  where id = p_transaction_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if not found then
    raise exception 'Transaction not found';
  end if;

  if not p_allow_linked and r.source_type is not null then
    raise exception 'This transaction is managed from its original feature and cannot be deleted here';
  end if;

  if r.kind = 'expense' then
    update public.accounts
    set current_balance = current_balance + r.amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  elsif r.kind = 'income' then
    update public.accounts
    set current_balance = current_balance - r.amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  elsif r.kind = 'transfer' then
    v_credit := coalesce(r.transfer_credit_amount, r.amount);
    update public.accounts
    set current_balance = current_balance + r.amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    update public.accounts
    set current_balance = current_balance - v_credit
    where id = r.transfer_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  end if;

  delete from public.transactions
  where id = p_transaction_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

create or replace function public.delete_transaction(
  p_user_id uuid,
  p_transaction_id uuid,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_transaction_internal(
    p_user_id,
    p_transaction_id,
    false,
    p_organization_id
  );
end;
$$;

create or replace function public.delete_account_cascade(
  p_account_id uuid,
  p_organization_id uuid default null
)
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
  where a.id = p_account_id
    and public.workspace_matches(a.organization_id, p_organization_id);

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
      and public.workspace_matches(t.organization_id, p_organization_id)
      and (t.account_id = p_account_id or t.transfer_account_id = p_account_id)
  loop
    perform public.delete_transaction_internal(v_user_id, r.id, true, p_organization_id);
  end loop;

  delete from public.recurring_transactions
  where user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id)
    and account_id = p_account_id;

  delete from public.bill_reminders
  where user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id)
    and account_id = p_account_id;

  with del_contrib as (
    delete from public.savings_goal_contributions c
    where c.user_id = v_user_id
      and public.workspace_matches(c.organization_id, p_organization_id)
      and c.account_id = p_account_id
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
    and public.workspace_matches(g.organization_id, p_organization_id)
    and g.id in (select goal_id from goals_to_fix);

  delete from public.loan_payments
  where user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id)
    and account_id = p_account_id;

  update public.loans
  set principal_account_id = null
  where user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id)
    and principal_account_id = p_account_id;

  delete from public.accounts
  where id = p_account_id
    and user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

create or replace function public.update_transaction(
  p_user_id uuid,
  p_transaction_id uuid,
  p_amount numeric,
  p_category_id uuid,
  p_note text,
  p_transfer_credit_amount numeric default null,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select *
  into r
  from public.transactions
  where id = p_transaction_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

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
      select c.type
      into v_cat
      from public.categories c
      where c.id = p_category_id
        and c.user_id = p_user_id
        and public.workspace_matches(c.organization_id, p_organization_id);
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
    where a.id = r.account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);
    if coalesce(v_bal, 0) + r.amount - p_amount < 0 then
      raise exception 'Insufficient balance in account';
    end if;
    update public.accounts
    set current_balance = current_balance + r.amount - p_amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);

  elsif r.kind = 'income' then
    update public.accounts
    set current_balance = current_balance + p_amount - r.amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);

  elsif r.kind = 'transfer' then
    select upper(trim(coalesce(a.currency_code, '')))
    into v_src_cur
    from public.accounts a
    where a.id = r.account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);

    select upper(trim(coalesce(a.currency_code, '')))
    into v_dst_cur
    from public.accounts a
    where a.id = r.transfer_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);

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
    where a.id = r.account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);
    if coalesce(v_bal, 0) + r.amount - p_amount < 0 then
      raise exception 'Insufficient balance in source account';
    end if;
    select a.current_balance into v_dest_bal
    from public.accounts a
    where a.id = r.transfer_account_id
      and a.user_id = p_user_id
      and public.workspace_matches(a.organization_id, p_organization_id);
    if coalesce(v_dest_bal, 0) - v_old_credit + v_new_credit < 0 then
      raise exception 'Insufficient balance in destination account';
    end if;
    update public.accounts
    set current_balance = current_balance + r.amount - p_amount
    where id = r.account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    update public.accounts
    set current_balance = current_balance - v_old_credit + v_new_credit
    where id = r.transfer_account_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
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
  where id = p_transaction_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

create or replace function public.add_savings_progress(
  p_user_id uuid,
  p_goal_id uuid,
  p_amount numeric,
  p_account_id uuid,
  p_note text default null,
  p_organization_id uuid default null
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

  if v_current_balance < p_amount then
    raise exception 'Insufficient balance in selected account';
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

  if upper(coalesce(v_account_currency, '')) <> upper(coalesce(v_goal_currency, '')) then
    raise exception 'Selected account currency must match savings goal currency';
  end if;

  if (v_goal_current + p_amount) > v_goal_target then
    raise exception 'Amount exceeds remaining savings goal';
  end if;

  update public.accounts
  set current_balance = current_balance - p_amount
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

create or replace function public.update_savings_goal(
  p_user_id uuid,
  p_goal_id uuid,
  p_name text,
  p_target_amount numeric,
  p_currency_code text,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select current_amount, currency_code
  into v_current_amount, v_existing_currency
  from public.savings_goals
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

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
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

create or replace function public.refund_savings_progress(
  p_user_id uuid,
  p_goal_id uuid,
  p_amount numeric,
  p_account_id uuid,
  p_note text default null,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  if p_amount <= 0 then
    raise exception 'Refund amount must be greater than 0';
  end if;

  select name, current_amount, currency_code
  into v_goal_name, v_goal_current, v_goal_currency
  from public.savings_goals
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_goal_name is null then
    raise exception 'Savings goal not found';
  end if;

  if v_goal_current < p_amount then
    raise exception 'Refund amount exceeds current savings';
  end if;

  select currency_code
  into v_account_currency
  from public.accounts
  where id = p_account_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_account_currency is null then
    raise exception 'Account not found';
  end if;

  if upper(coalesce(v_account_currency, '')) <> upper(coalesce(v_goal_currency, '')) then
    raise exception 'Selected account currency must match savings goal currency';
  end if;

  update public.savings_goals
  set current_amount = current_amount - p_amount,
      is_completed = (current_amount - p_amount) >= target_amount
  where id = p_goal_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  update public.accounts
  set current_balance = current_balance + p_amount
  where id = p_account_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  insert into public.savings_goal_contributions (
    user_id, organization_id, goal_id, account_id, amount, note
  ) values (
    p_user_id, p_organization_id, p_goal_id, p_account_id, -p_amount, coalesce(p_note, 'Savings refund')
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
  p_note text default null,
  p_organization_id uuid default null
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
    p_amount,
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

create or replace function public.create_loan(
  p_user_id uuid,
  p_person_name text,
  p_total_amount numeric,
  p_direction text,
  p_currency_code text,
  p_principal_account_id uuid,
  p_due_date date default null,
  p_note text default null,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

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
  where a.id = p_principal_account_id
    and a.user_id = p_user_id
    and public.workspace_matches(a.organization_id, p_organization_id);

  if v_acct_currency is null then
    raise exception 'Account not found';
  end if;

  if upper(trim(coalesce(v_acct_currency, ''))) <>
     upper(trim(coalesce(p_currency_code, ''))) then
    raise exception 'Account currency must match loan currency';
  end if;

  insert into public.loans (
    user_id,
    organization_id,
    person_name,
    total_amount,
    currency_code,
    direction,
    principal_account_id,
    note,
    due_date
  ) values (
    p_user_id,
    p_organization_id,
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
      v_id,
      p_organization_id
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
      v_id,
      p_organization_id
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
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  if p_total_amount <= 0 then
    raise exception 'Total amount must be greater than zero';
  end if;

  select l.direction, upper(trim(coalesce(l.currency_code, '')))
  into v_existing_direction, v_existing_currency
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

create or replace function public.delete_loan_cascade(
  p_loan_id uuid,
  p_organization_id uuid default null
)
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
  where l.id = p_loan_id
    and l.user_id = v_user_id
    and public.workspace_matches(l.organization_id, p_organization_id);

  if not found then
    raise exception 'Loan not found';
  end if;

  for r in
    select lp.transaction_id
    from public.loan_payments lp
    where lp.loan_id = p_loan_id
      and lp.user_id = v_user_id
      and public.workspace_matches(lp.organization_id, p_organization_id)
      and lp.transaction_id is not null
  loop
    if exists (
    select 1
      from public.transactions t
      where t.id = r.transaction_id
        and t.user_id = v_user_id
        and public.workspace_matches(t.organization_id, p_organization_id)
    ) then
      perform public.delete_transaction_internal(v_user_id, r.transaction_id, true, p_organization_id);
    end if;
  end loop;

  delete from public.loan_payments
  where loan_id = p_loan_id
    and user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if v_principal_tx_id is not null
     and exists (
       select 1
       from public.transactions t
       where t.id = v_principal_tx_id
         and t.user_id = v_user_id
         and public.workspace_matches(t.organization_id, p_organization_id)
     ) then
    perform public.delete_transaction_internal(v_user_id, v_principal_tx_id, true, p_organization_id);
  end if;

  delete from public.loans
  where id = p_loan_id
    and user_id = v_user_id
    and public.workspace_matches(organization_id, p_organization_id);
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
  p_note text default null,
  p_organization_id uuid default null
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
  perform public.assert_workspace_access(p_user_id, p_organization_id);

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
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_dst_cur
    from accounts
    where id = p_to_id
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals
    where id = p_to_id
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    select direction, upper(trim(coalesce(currency_code, '')))
    into v_loan_dir, v_loan_cur
    from loans
    where id = p_to_id
      and user_id = p_user_id
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
      and user_id = p_user_id
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
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
    select upper(trim(coalesce(currency_code, ''))) into v_g2_cur
    from savings_goals
    where id = p_to_id
      and user_id = p_user_id
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
      and user_id = p_user_id
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

create or replace function public.run_due_recurring_transactions(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_next_date date;
  v_count integer := 0;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  for r in
    select *
    from public.recurring_transactions
    where user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id)
      and is_active = true
      and next_run_date <= current_date
    order by next_run_date asc
  loop
    perform public.create_transaction(
      p_user_id,
      r.account_id,
      r.category_id,
      r.kind,
      r.amount,
      r.next_run_date::timestamptz,
      coalesce(r.note, 'Recurring transaction'),
      null,
      null,
      p_organization_id
    );

    v_next_date :=
      case r.frequency
        when 'daily' then r.next_run_date + interval '1 day'
        when 'weekly' then r.next_run_date + interval '7 day'
        when 'monthly' then r.next_run_date + interval '1 month'
        when 'yearly' then r.next_run_date + interval '1 year'
      end;

    update public.recurring_transactions
    set next_run_date = v_next_date::date
    where id = r.id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function public.mark_bill_paid(
  p_user_id uuid,
  p_bill_id uuid,
  p_paid_on date default current_date,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_next_due date;
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  select *
  into r
  from public.bill_reminders
  where id = p_bill_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);

  if not found then
    raise exception 'Bill reminder not found';
  end if;

  perform public.create_transaction(
    p_user_id,
    r.account_id,
    r.category_id,
    'expense',
    r.amount,
    p_paid_on::timestamptz,
    'Bill paid: ' || r.title,
    null,
    null,
    p_organization_id
  );

  if r.frequency = 'once' then
    update public.bill_reminders
    set is_active = false,
        last_paid_at = now()
    where id = p_bill_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  else
    v_next_due :=
      case r.frequency
        when 'weekly' then r.due_date + interval '7 day'
        when 'monthly' then r.due_date + interval '1 month'
        when 'yearly' then r.due_date + interval '1 year'
      end;

    update public.bill_reminders
    set due_date = v_next_due,
        last_paid_at = now()
    where id = p_bill_id
      and user_id = p_user_id
      and public.workspace_matches(organization_id, p_organization_id);
  end if;
end;
$$;

create or replace function public.get_dashboard_summary(
  p_user_id uuid,
  p_organization_id uuid default null
)
returns table (
  total_balance numeric,
  income_month numeric,
  expense_month numeric,
  savings_total numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  return query
  with month_bounds as (
    select date_trunc('month', now())::date as month_start
  )
  select
    coalesce((
      select sum(a.current_balance)
      from public.accounts a
      where a.user_id = p_user_id
        and public.workspace_matches(a.organization_id, p_organization_id)
        and a.is_archived = false
    ), 0) as total_balance,
    coalesce((
      select sum(t.amount)
      from public.transactions t, month_bounds m
      where t.user_id = p_user_id
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.kind = 'income'
        and t.transaction_date >= m.month_start
    ), 0) as income_month,
    coalesce((
      select sum(t.amount)
      from public.transactions t, month_bounds m
      where t.user_id = p_user_id
        and public.workspace_matches(t.organization_id, p_organization_id)
        and t.kind = 'expense'
        and t.transaction_date >= m.month_start
    ), 0) as expense_month,
    coalesce((
      select sum(s.current_amount)
      from public.savings_goals s
      where s.user_id = p_user_id
        and public.workspace_matches(s.organization_id, p_organization_id)
    ), 0) as savings_total;
end;
$$;

create or replace function public.exchange_account_currency(
  p_user_id uuid,
  p_account_id uuid,
  p_target_currency text,
  p_rate numeric,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_workspace_access(p_user_id, p_organization_id);

  if p_rate is null or p_rate <= 0 then
    raise exception 'Invalid exchange rate';
  end if;

  update public.accounts
  set current_balance = round((current_balance * p_rate)::numeric, 2),
      opening_balance = round((opening_balance * p_rate)::numeric, 2),
      currency_code = p_target_currency
  where id = p_account_id
    and user_id = p_user_id
    and public.workspace_matches(organization_id, p_organization_id);
end;
$$;

create or replace function public.delete_my_data(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  delete from public.loan_payments where user_id = p_user_id;
  delete from public.loans where user_id = p_user_id;
  delete from public.savings_goal_contributions where user_id = p_user_id;
  delete from public.transactions where user_id = p_user_id;
  delete from public.budgets where user_id = p_user_id;
  delete from public.recurring_transactions where user_id = p_user_id;
  delete from public.bill_reminders where user_id = p_user_id;
  delete from public.savings_goals where user_id = p_user_id;
  delete from public.support_events where user_id = p_user_id;
  delete from public.categories where user_id = p_user_id;
  delete from public.accounts where user_id = p_user_id;
  delete from public.organization_members where user_id = p_user_id;
  delete from public.organizations where owner_user_id = p_user_id;

  update public.profiles
  set business_mode_enabled = false,
      active_workspace_kind = 'personal',
      active_workspace_organization_id = null
  where id = p_user_id;
end;
$$;

drop policy if exists accounts_own_all on public.accounts;
drop policy if exists categories_own_all on public.categories;
drop policy if exists transactions_own_all on public.transactions;
drop policy if exists transactions_select_own on public.transactions;
drop policy if exists budgets_own_all on public.budgets;
drop policy if exists savings_own_all on public.savings_goals;
drop policy if exists recurring_own_all on public.recurring_transactions;
drop policy if exists bills_own_all on public.bill_reminders;
drop policy if exists savings_contrib_own_all on public.savings_goal_contributions;
drop policy if exists loans_own_all on public.loans;
drop policy if exists loan_payments_own_all on public.loan_payments;
drop policy if exists support_events_own_all on public.support_events;

create policy accounts_own_all on public.accounts
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy categories_own_all on public.categories
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy transactions_own_all on public.transactions
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy budgets_own_all on public.budgets
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy savings_own_all on public.savings_goals
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy recurring_own_all on public.recurring_transactions
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy bills_own_all on public.bill_reminders
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy savings_contrib_own_all on public.savings_goal_contributions
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy loans_own_all on public.loans
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy loan_payments_own_all on public.loan_payments
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

create policy support_events_own_all on public.support_events
for all using (public.can_manage_workspace_row(user_id, organization_id, auth.uid()))
with check (public.can_manage_workspace_row(user_id, organization_id, auth.uid()));

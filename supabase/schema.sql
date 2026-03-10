

create extension if not exists "uuid-ossp";

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
  note text,
  transaction_date date not null default current_date,
  transfer_account_id uuid references public.accounts(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (kind = 'transfer' and transfer_account_id is not null and transfer_account_id <> account_id) or
    (kind <> 'transfer' and transfer_account_id is null)
  )
);
create index if not exists idx_transactions_user_date on public.transactions(user_id, transaction_date desc);

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
  target_date date,
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_goals_user on public.savings_goals(user_id);

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
  amount numeric(14, 2) not null check (amount > 0),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_savings_contrib_user_goal on public.savings_goal_contributions(user_id, goal_id, created_at desc);

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

create table if not exists public.loan_payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  loan_id uuid not null references public.loans(id) on delete cascade,
  amount numeric(14, 2) not null check (amount > 0),
  payment_date date not null default current_date,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_loan_payments_loan on public.loan_payments(loan_id, payment_date desc);

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
    (p_user_id, 'Investments', 'income', true),
    (p_user_id, 'Food', 'expense', true),
    (p_user_id, 'Transport', 'expense', true),
    (p_user_id, 'Rent', 'expense', true),
    (p_user_id, 'Bills', 'expense', true),
    (p_user_id, 'Health', 'expense', true)
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

create or replace function public.create_transaction(
  p_user_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_kind text,
  p_amount numeric,
  p_transaction_date timestamptz,
  p_note text,
  p_transfer_account_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  insert into public.transactions (
    user_id, account_id, category_id, kind, amount, transaction_date, note, transfer_account_id
  ) values (
    p_user_id, p_account_id, p_category_id, p_kind, p_amount, p_transaction_date::date, p_note, p_transfer_account_id
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
    set current_balance = current_balance + p_amount
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
    update public.accounts set current_balance = current_balance + r.amount
    where id = r.account_id and user_id = p_user_id;
    update public.accounts set current_balance = current_balance - r.amount
    where id = r.transfer_account_id and user_id = p_user_id;
  end if;

  delete from public.transactions where id = p_transaction_id and user_id = p_user_id;
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
  v_goal_name text;
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

  select name into v_goal_name
  from public.savings_goals
  where id = p_goal_id and user_id = p_user_id;

  if v_goal_name is null then
    raise exception 'Savings goal not found';
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
create policy transactions_own_all on public.transactions
for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

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

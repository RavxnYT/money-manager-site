-- Add account tracking for loan payments and auto-transaction posting.

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
  account_id uuid references public.accounts(id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  payment_date date not null default current_date,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_loan_payments_loan on public.loan_payments(loan_id, payment_date desc);

alter table if exists public.loan_payments
add column if not exists account_id uuid references public.accounts(id) on delete restrict;

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
  v_kind text;
  v_note text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Unauthorized';
  end if;

  select l.direction, l.person_name
  into v_direction, v_person_name
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

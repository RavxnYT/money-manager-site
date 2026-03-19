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

do $$
declare
  u record;
begin
  for u in select id from public.profiles loop
    perform public.seed_default_categories(u.id);
  end loop;
end $$;

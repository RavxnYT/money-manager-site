-- create_business_workspace used uuid_generate_v4() (uuid-ossp). Many Supabase
-- projects don't have that extension enabled, and security definer + search_path = public
-- won't find it in the extensions schema. pgcrypto's gen_random_uuid() is the
-- supported default on Supabase (see dashboard: pgcrypto usually ON).

create extension if not exists pgcrypto with schema extensions;

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

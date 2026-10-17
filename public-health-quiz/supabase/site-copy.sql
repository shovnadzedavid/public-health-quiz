-- Run once in the Supabase SQL Editor to enable the admin text editor.
begin;

create table if not exists public.site_copy (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint site_copy_key_allowed check (key = any (array[
    'home_eyebrow', 'home_title', 'home_title_em', 'home_intro',
    'home_explore_button', 'home_search_placeholder', 'home_daily_eyebrow',
    'home_daily_title', 'home_daily_description', 'home_daily_button',
    'home_categories_eyebrow', 'home_categories_title', 'brand_subtitle',
    'footer_slogan'
  ]::text[])),
  constraint site_copy_value_length check (char_length(value) between 1 and 400)
);

alter table public.site_copy enable row level security;
revoke all on public.site_copy from public, anon, authenticated;

create or replace function public.site_copy_public()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.site_copy;
$$;

create or replace function public.save_site_copy(p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  saved_count integer := 0;
  allowed_keys constant text[] := array[
    'home_eyebrow', 'home_title', 'home_title_em', 'home_intro',
    'home_explore_button', 'home_search_placeholder', 'home_daily_eyebrow',
    'home_daily_title', 'home_daily_description', 'home_daily_button',
    'home_categories_eyebrow', 'home_categories_title', 'brand_subtitle',
    'footer_slogan'
  ];
begin
  if auth.uid() is null or not exists (
    select 1 from public.editors where id = auth.uid()
  ) then
    raise exception 'ადმინისტრატორის უფლება საჭიროა';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 14 then
    raise exception 'ტექსტების სია არასწორია';
  end if;

  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item) <> 'object'
      or not ((item->>'key') = any(allowed_keys))
      or jsonb_typeof(item->'value') <> 'string'
      or char_length(item->>'value') not between 1 and 400 then
      raise exception 'ტექსტის ველი არასწორია';
    end if;

    insert into public.site_copy(key, value, updated_at, updated_by)
    values (item->>'key', item->>'value', now(), auth.uid())
    on conflict (key) do update
      set value = excluded.value,
          updated_at = excluded.updated_at,
          updated_by = excluded.updated_by;
    saved_count := saved_count + 1;
  end loop;

  return saved_count;
end;
$$;

revoke execute on function public.site_copy_public(), public.save_site_copy(jsonb)
  from public, anon, authenticated;
grant execute on function public.site_copy_public() to anon, authenticated;
grant execute on function public.save_site_copy(jsonb) to authenticated;

commit;

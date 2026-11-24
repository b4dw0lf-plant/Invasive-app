-- Invasives Field Survey: cloud setup
-- Paste this whole script into Supabase > SQL Editor > New query, then tap Run.
-- It is safe to run more than once.

-- 1. Tables -----------------------------------------------------------------
create table if not exists public.properties (
  owner      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  name       text,
  county     text,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false,
  primary key (owner, id)
);

create table if not exists public.survey_features (
  owner       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  property_id text not null,
  id          text not null,
  kind        text not null check (kind in ('poly', 'marker')),
  species     text[] not null default '{}',
  density     text,
  acres       numeric not null default 0,
  county      text,
  primary key (owner, property_id, id),
  foreign key (owner, property_id) references public.properties (owner, id) on delete cascade
);

create index if not exists survey_features_species_idx on public.survey_features using gin (species);

-- 2. Privacy: each surveyor can only read and write their own rows -----------
alter table public.properties enable row level security;
alter table public.survey_features enable row level security;

drop policy if exists "own properties" on public.properties;
create policy "own properties" on public.properties
  for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists "own features" on public.survey_features;
create policy "own features" on public.survey_features
  for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

-- 3. Save and delete a whole property in one step -----------------------------
create or replace function public.save_property(
  p_id text, p_name text, p_county text, p_data jsonb, p_features jsonb
) returns timestamptz
language plpgsql security invoker set search_path = public as $$
declare ts timestamptz := now();
begin
  insert into public.properties (owner, id, name, county, data, updated_at, deleted)
  values (auth.uid(), p_id, p_name, p_county, p_data, ts, false)
  on conflict (owner, id) do update
    set name = excluded.name, county = excluded.county, data = excluded.data,
        updated_at = ts, deleted = false;

  delete from public.survey_features where owner = auth.uid() and property_id = p_id;

  insert into public.survey_features (owner, property_id, id, kind, species, density, acres, county)
  select auth.uid(), p_id, t.f ->> 'id', t.f ->> 'kind',
         array(select jsonb_array_elements_text(t.f -> 'species')),
         t.f ->> 'density',
         coalesce((t.f ->> 'acres')::numeric, 0),
         p_county
  from jsonb_array_elements(p_features) as t(f);

  return ts;
end $$;

create or replace function public.delete_property(p_id text) returns void
language plpgsql security invoker set search_path = public as $$
begin
  update public.properties set deleted = true, updated_at = now()
   where owner = auth.uid() and id = p_id;
  delete from public.survey_features where owner = auth.uid() and property_id = p_id;
end $$;

-- 4. Totals across everyone (counts only, no names, notes or locations) -------
create or replace function public.species_totals()
returns table (species text, acres numeric, polygons bigint, markers bigint, properties bigint, surveyors bigint)
language sql stable security definer set search_path = public as $$
  select s,
         round(coalesce(sum(case when f.kind = 'poly' then f.acres end), 0), 2),
         count(*) filter (where f.kind = 'poly'),
         count(*) filter (where f.kind = 'marker'),
         count(distinct f.owner::text || ':' || f.property_id),
         count(distinct f.owner)
  from public.survey_features f
  cross join lateral unnest(f.species) as s
  group by s
  order by 2 desc, 1;
$$;

-- Total for any species whose name contains the search text (each polygon counted once)
create or replace function public.species_match_total(q text)
returns table (acres numeric, polygons bigint, markers bigint, properties bigint, surveyors bigint)
language sql stable security definer set search_path = public as $$
  select round(coalesce(sum(case when f.kind = 'poly' then f.acres end), 0), 2),
         count(*) filter (where f.kind = 'poly'),
         count(*) filter (where f.kind = 'marker'),
         count(distinct f.owner::text || ':' || f.property_id),
         count(distinct f.owner)
  from public.survey_features f
  where exists (select 1 from unnest(f.species) as s where s ilike '%' || q || '%');
$$;

revoke all on function public.save_property(text, text, text, jsonb, jsonb) from public, anon;
revoke all on function public.delete_property(text) from public, anon;
revoke all on function public.species_totals() from public, anon;
revoke all on function public.species_match_total(text) from public, anon;
grant execute on function public.save_property(text, text, text, jsonb, jsonb) to authenticated;
grant execute on function public.delete_property(text) to authenticated;
grant execute on function public.species_totals() to authenticated;
grant execute on function public.species_match_total(text) to authenticated;

-- 5. Private photo storage (each surveyor can only reach their own folder) ----
insert into storage.buckets (id, name, public) values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists "photos read own" on storage.objects;
create policy "photos read own" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photos add own" on storage.objects;
create policy "photos add own" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photos update own" on storage.objects;
create policy "photos update own" on storage.objects for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photos delete own" on storage.objects;
create policy "photos delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

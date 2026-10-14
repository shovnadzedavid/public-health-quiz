begin;
create table if not exists public.update_jobs(id uuid primary key default gen_random_uuid(),status text not null default 'running',started_at timestamptz not null default now(),finished_at timestamptz,summary jsonb not null default '{}');
create table if not exists public.update_sources(id uuid primary key default gen_random_uuid(),url text unique not null,title text not null,topic text not null,published_at text,source_type text not null,content_hash text,content text,checked_at timestamptz,status text not null default 'discovered');
create table if not exists public.source_audits(url text primary key,content_hash text,last_checked timestamptz not null default now(),status text not null,error text);
create table if not exists public.question_flags(question_id uuid primary key references public.questions on delete cascade,status text not null,checked_at timestamptz not null default now(),reason text not null);
create table if not exists public.draft_jobs(id uuid primary key default gen_random_uuid(),source_id uuid references public.update_sources,status text not null default 'running',started_at timestamptz not null default now(),finished_at timestamptz,count int not null default 0,error text);
create unique index if not exists draft_source_once on public.draft_jobs(source_id) where status in ('running','succeeded');
create unique index if not exists question_prompt_unique on public.questions(md5(lower(trim(prompt))));
alter table public.update_jobs enable row level security;
alter table public.update_sources enable row level security;
alter table public.source_audits enable row level security;
alter table public.question_flags enable row level security;
alter table public.draft_jobs enable row level security;
revoke all on public.update_jobs,public.update_sources,public.source_audits,public.question_flags,public.draft_jobs from anon,authenticated;
grant all on public.update_jobs,public.update_sources,public.source_audits,public.question_flags,public.draft_jobs to service_role;
create or replace function public.update_admin_status() returns jsonb language plpgsql security definer set search_path=public as $$ begin
if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if;
return jsonb_build_object('jobs',coalesce((select jsonb_agg(to_jsonb(t)) from (select * from update_jobs order by started_at desc limit 10)t),'[]'),'sources',coalesce((select jsonb_agg(to_jsonb(t)-'content') from (select * from update_sources order by checked_at desc nulls last,id limit 60)t),'[]'),'flags',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.prompt,'reason',f.reason,'status',f.status)) from question_flags f join questions q on q.id=f.question_id),'[]'),'next_due',coalesce((select max(finished_at)+interval '90 days' from update_jobs where status='succeeded'),now())); end; $$;
create or replace function public.begin_source_update(p_scheduled boolean) returns uuid language plpgsql security definer set search_path=public as $$ declare jid uuid; begin
perform pg_advisory_xact_lock(hashtext('source-updater'));
update update_jobs set status='failed',finished_at=now(),summary='{"error":"დროის ლიმიტი ამოიწურა; შესაძლებელია ხელახალი ცდა"}' where status='running' and started_at<now()-interval '10 minutes';
if exists(select 1 from update_jobs where status='running') then return null; end if;
if p_scheduled and exists(select 1 from update_jobs where status='succeeded' and finished_at>now()-interval '90 days') then return null; end if;
if exists(select 1 from update_jobs where started_at>now()-interval '10 minutes') then return null; end if;
insert into update_jobs default values returning id into jid;return jid;end; $$;
create or replace function public.finish_source_update(p_id uuid,p_status text,p_summary jsonb) returns void language sql security definer set search_path=public as $$ update update_jobs set status=p_status,summary=p_summary,finished_at=now() where id=p_id and status='running'; $$;
create or replace function public.source_update_inputs() returns jsonb language sql security definer set search_path=public as $$
with due as (select distinct q.source_url,a.last_checked from questions q left join source_audits a on a.url=q.source_url where q.status in ('draft','published') and (a.last_checked is null or a.last_checked<now()-interval '90 days'))
select jsonb_build_object('remaining',(select count(*) from due),'urls',coalesce((select jsonb_agg(t.source_url) from (select source_url from due order by last_checked nulls first,source_url limit 10)t),'[]')); $$;
create or replace function public.record_source_audit(p_url text,p_hash text,p_error text) returns text language plpgsql security definer set search_path=public as $$ declare oldhash text; st text; begin
select content_hash into oldhash from source_audits where url=p_url;
st:=case when p_error is not null then 'unreachable' when oldhash is null then 'baseline' when oldhash<>p_hash then 'changed' else 'unchanged' end;
insert into source_audits(url,content_hash,status,error) values(p_url,p_hash,st,p_error) on conflict(url) do update set content_hash=coalesce(excluded.content_hash,source_audits.content_hash),last_checked=now(),status=excluded.status,error=excluded.error;
if st in ('changed','unreachable') then insert into question_flags(question_id,status,reason) select id,st,case when st='changed' then 'წყაროს ტექსტი შეიცვალა — საჭიროა პასუხის ხელახლა შემოწმება' else 'წყარო ვერ გაიხსნა — ეს არ ადასტურებს პასუხის მცდარობას' end from questions where source_url=p_url on conflict(question_id) do update set status=excluded.status,reason=excluded.reason,checked_at=now(); end if; return st; end; $$;
create or replace function public.accept_discovered_sources(p_items jsonb) returns int language plpgsql security definer set search_path=public as $$ declare q jsonb;n int:=0;begin for q in select value from jsonb_array_elements(p_items) loop insert into update_sources(url,title,topic,published_at,source_type,checked_at) values(q->>'url',q->>'title',q->>'topic',q->>'published_at',q->>'source_type',now()) on conflict(url) do update set checked_at=now();n:=n+1;end loop;return n;end; $$;
create or replace function public.begin_draft_job(p_source uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare jid uuid;s update_sources;begin
perform pg_advisory_xact_lock(hashtext('draft-job'));
update draft_jobs set status='failed',finished_at=now(),error='დროის ლიმიტი ამოიწურა' where status='running' and started_at<now()-interval '5 minutes';
if (select count(*) from draft_jobs where started_at>now()-interval '24 hours')>=10 then raise exception 'დღიური ლიმიტი: 10 წყარო';end if;
select * into s from update_sources where id=p_source;if s.id is null then raise exception 'წყარო ვერ მოიძებნა';end if;
if exists(select 1 from draft_jobs where source_id=p_source and status in ('running','succeeded')) then raise exception 'ამ წყაროს დამუშავება უკვე დაწყებულია ან დასრულებულია';end if;
insert into draft_jobs(source_id) values(p_source) returning id into jid;return jsonb_build_object('job_id',jid,'source',to_jsonb(s));end; $$;
create or replace function public.finish_draft_job(p_id uuid,p_items jsonb,p_error text) returns int language plpgsql security definer set search_path=public as $$ declare q jsonb;n int:=0;src uuid;begin
select source_id into src from draft_jobs where id=p_id and status='running' for update;if src is null then raise exception 'ამოცანა მიუწვდომელია';end if;
if p_error is null then
for q in select value from jsonb_array_elements(p_items) loop insert into questions(family_id,prompt,options,answer_index,explanation,topic,kind,difficulty,source_url,source_title,source_locator,status) values(q->>'family_id',q->>'prompt',q->'options',(q->>'answer_index')::int,q->>'explanation',q->>'topic',q->>'kind',(q->>'difficulty')::int,q->>'source_url',q->>'source_title',q->>'source_locator','draft') on conflict do nothing; if found then n:=n+1;end if;end loop;end if;
update draft_jobs set status=case when p_error is null then 'succeeded' else 'failed' end,finished_at=now(),count=n,error=p_error where id=p_id;
update update_sources set status=case when p_error is null then 'drafted' else 'draft_failed' end where id=src;return n;end; $$;
create or replace function public.clear_question_flag(p_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია';end if;delete from question_flags where question_id=p_id;end; $$;
revoke execute on function public.update_admin_status(),public.clear_question_flag(uuid) from public,anon,authenticated;
grant execute on function public.update_admin_status(),public.clear_question_flag(uuid) to authenticated;
revoke execute on function public.begin_source_update(boolean),public.finish_source_update(uuid,text,jsonb),public.source_update_inputs(),public.record_source_audit(text,text,text),public.accept_discovered_sources(jsonb),public.begin_draft_job(uuid),public.finish_draft_job(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.begin_source_update(boolean),public.finish_source_update(uuid,text,jsonb),public.source_update_inputs(),public.record_source_audit(text,text,text),public.accept_discovered_sources(jsonb),public.begin_draft_job(uuid),public.finish_draft_job(uuid,jsonb,text) to service_role;
commit;

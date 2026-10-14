begin;
alter table public.questions add column if not exists last_daily_used date;
alter table public.questions add column if not exists bank text not null default 'legacy';
alter table public.questions add column if not exists daily_only boolean not null default false;
alter table public.questions add column if not exists review_status text not null default 'editorial_pending';
create or replace function public.import_questions(p_items jsonb) returns int language plpgsql security definer set search_path=public as $$ declare q jsonb;n int:=0;begin
if not exists(select 1 from editors where id=auth.uid()) then raise exception 'ადმინისტრატორის უფლება საჭიროა';end if;
if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>500 then raise exception 'მაქსიმუმ 500 კითხვა ერთ ატვირთვაზე';end if;
for q in select value from jsonb_array_elements(p_items) loop
insert into questions(id,family_id,prompt,options,answer_index,explanation,topic,kind,difficulty,source_url,source_title,source_locator,status,bank,daily_only,review_status) values(coalesce((q->>'id')::uuid,gen_random_uuid()),q->>'family_id',q->>'prompt',q->'options',(q->>'answer_index')::int,q->>'explanation',q->>'topic',q->>'kind',(q->>'difficulty')::int,q->>'source_url',q->>'source_title',q->>'source_locator','draft',coalesce(q->>'bank','legacy'),coalesce((q->>'daily_only')::boolean,false),coalesce(q->>'review_status','editorial_pending')) on conflict do nothing;
if found then n:=n+1;end if;end loop;return n;end; $$;
create or replace function public.editor_families() returns jsonb language plpgsql security definer set search_path=public as $$begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია';end if;
return coalesce((select jsonb_agg(to_jsonb(x)) from (select family_id,topic,bank,count(*) questions,min(prompt) example_prompt from questions where status='draft' group by family_id,topic,bank order by topic,family_id,bank)x),'[]');end; $$;
create or replace function public.publish_family(p_family text,p_bank text) returns int language plpgsql security definer set search_path=public as $$ declare n int;begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია';end if;
update questions set status='published',reviewed_at=current_date where family_id=p_family and bank=p_bank and status='draft';get diagnostics n=row_count;return n;end; $$;
create or replace function public.publish_ready_quizzes() returns int language plpgsql security definer set search_path=public as $$declare n int;begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია';end if;
update quizzes z set status='published' where z.status='draft' and cardinality(z.question_ids)=z.question_count and (select count(distinct q.family_id) from questions q where q.id=any(z.question_ids) and q.status='published' and not q.daily_only)=z.question_count;get diagnostics n=row_count;return n;end; $$;
revoke execute on function public.editor_families(),public.publish_family(text,text),public.publish_ready_quizzes() from public,anon,authenticated;
grant execute on function public.editor_families(),public.publish_family(text,text),public.publish_ready_quizzes() to authenticated;
commit;

-- Daily selection rotates the variant within each question family.
create or replace function public.start_game(p_mode text,p_quiz text default null) returns jsonb language plpgsql security definer set search_path=public as $$ declare s sessions; qs jsonb; d date:=(now() at time zone 'Asia/Tbilisi')::date; z quizzes; title_text text; theme_text text; begin
if auth.uid() is null then raise exception 'ჯერ შედით ანგარიშში'; end if;
if p_mode is null or p_mode not in ('quiz','daily') then raise exception 'უცნობი რეჟიმი'; end if;
perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
if p_mode='daily' then select * into s from sessions where user_id=auth.uid() and mode='daily' and day=d; else select * into s from sessions where user_id=auth.uid() and mode='quiz' and quiz_id=p_quiz; end if;
if s.id is not null then
if s.finished_at is null and now()>s.started_at+jsonb_array_length(s.items)*interval '40 seconds' then update sessions set finished_at=now() where id=s.id returning * into s; end if;
return quiz_state(s); end if;
if p_mode='daily' then
perform pg_advisory_xact_lock(hashtext('daily-'||d::text));
select items into qs from daily_sets where day=d;
select title,theme into title_text,theme_text from health_days where month_day=to_char(d,'MM-DD');
title_text:=coalesce(title_text,'დღის ქუიზი');
if qs is null then
select jsonb_agg(to_jsonb(q)) into qs from (select distinct on (family_id) * from questions where status='published' and (theme_text is null or topic=theme_text) and (daily_only or (bank='legacy' and not exists(select 1 from questions where status='published' and daily_only))) order by family_id,last_daily_used nulls first,md5(d::text||id::text)) q;
select jsonb_agg(x.item order by x.k) into qs from (select item,md5(d::text || (item->>'id')) k from jsonb_array_elements(coalesce(qs,'[]')) item order by k limit 15) x;
if coalesce(jsonb_array_length(qs),0)<15 then raise exception 'დღის თემისთვის საჭიროა 15 დამტკიცებული კითხვა'; end if;
insert into daily_sets values(d,qs);
update questions set last_daily_used=d where id in (select (item->>'id')::uuid from jsonb_array_elements(qs) item); end if;
else
select * into z from quizzes where id=p_quiz and status='published';
if z.id is null then raise exception 'ქუიზი ჯერ არ არის გამოქვეყნებული'; end if;
title_text:=z.title;
select jsonb_agg(to_jsonb(q) order by a.ord) into qs from unnest(z.question_ids) with ordinality a(id,ord) join questions q on q.id=a.id and q.status='published';
if coalesce(jsonb_array_length(qs),0)<>z.question_count then raise exception 'ქუიზის კითხვების შემოწმება დაუსრულებელია'; end if;
end if;
insert into sessions(user_id,mode,day,quiz_id,title,items) values(auth.uid(),p_mode,d,case when p_mode='daily' then d::text else p_quiz end,title_text,qs) returning * into s;
return quiz_state(s); end; $$;

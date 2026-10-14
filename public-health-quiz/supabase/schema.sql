begin;
create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users on delete cascade, nickname text not null check(char_length(nickname) between 2 and 30));
create table if not exists public.editors(id uuid primary key references auth.users on delete cascade);
create table if not exists public.questions(id uuid primary key default gen_random_uuid(), family_id text not null, prompt text not null, options jsonb not null check(jsonb_typeof(options)='array' and jsonb_array_length(options)=4), answer_index int not null check(answer_index between 0 and 3), explanation text not null, topic text not null, kind text not null, difficulty int not null check(difficulty between 1 and 3), source_url text not null check(source_url ~ '^https://'), source_title text not null, source_locator text not null, reviewed_at date, status text not null default 'draft' check(status in ('draft','published','retired')));
create table if not exists public.sessions(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade, mode text not null check(mode in ('quiz','daily')), day date not null, quiz_id text not null, title text not null, items jsonb not null, cursor int not null default 0, score int not null default 0, started_at timestamptz not null default now(), finished_at timestamptz);
create table if not exists public.daily_sets(day date primary key, items jsonb not null);
alter table public.daily_sets enable row level security;
revoke all on public.daily_sets from anon,authenticated;
create unique index if not exists quiz_first on public.sessions(user_id,quiz_id) where mode='quiz';
create table if not exists public.quizzes(id text primary key,title text not null,theme text not null,question_count int not null check(question_count in (15,20,25,30)),question_ids uuid[] not null,status text not null default 'draft' check(status in ('draft','published')));
create table if not exists public.health_days(month_day text primary key,title text not null,theme text not null,source_url text not null);
alter table public.quizzes enable row level security;
alter table public.health_days enable row level security;
revoke all on public.quizzes,public.health_days from anon,authenticated;
create unique index if not exists daily_once on public.sessions(user_id,day) where mode='daily';
create index if not exists sessions_user on public.sessions(user_id,started_at);
create table if not exists public.seen(user_id uuid references auth.users on delete cascade, family_id text, primary key(user_id,family_id));
alter table public.profiles enable row level security;
alter table public.editors enable row level security;
alter table public.questions enable row level security;
alter table public.sessions enable row level security;
alter table public.seen enable row level security;
revoke all on public.profiles,public.editors,public.questions,public.sessions,public.seen from anon,authenticated;
create or replace function public.make_profile() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into profiles(id,nickname) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'nickname',''),'მოთამაშე'),30)); return new; end; $$;
drop trigger if exists make_profile on auth.users;
create trigger make_profile after insert on auth.users for each row execute function public.make_profile();
create or replace function public.quiz_state(s sessions) returns jsonb language sql set search_path=public as $$ select jsonb_build_object('session_id',s.id,'mode',s.mode,'title',s.title,'expires_at',extract(epoch from s.started_at)+jsonb_array_length(s.items)*40,'position',s.cursor,'total',jsonb_array_length(s.items),'score',s.score,'finished',s.finished_at is not null,'question',case when s.finished_at is null then (s.items->s.cursor)-'answer_index'-'explanation'-'source_url'-'source_title'-'source_locator'-'reviewed_at' else null end); $$;
create or replace function public.quiz_catalog() returns jsonb language sql security definer set search_path=public as $$ select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'theme',theme,'question_count',question_count)),'[]') from quizzes where status='published'; $$;
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
select jsonb_agg(to_jsonb(q)) into qs from (select distinct on (family_id) * from questions where status='published' and (theme_text is null or topic=theme_text) order by family_id,id) q;
select jsonb_agg(x.item order by x.k) into qs from (select item,md5(d::text || (item->>'id')) k from jsonb_array_elements(coalesce(qs,'[]')) item order by k limit 15) x;
if coalesce(jsonb_array_length(qs),0)<15 then raise exception 'დღის თემისთვის საჭიროა 15 დამტკიცებული კითხვა'; end if;
insert into daily_sets values(d,qs); end if;
else
select * into z from quizzes where id=p_quiz and status='published';
if z.id is null then raise exception 'ქუიზი ჯერ არ არის გამოქვეყნებული'; end if;
title_text:=z.title;
select jsonb_agg(to_jsonb(q) order by a.ord) into qs from unnest(z.question_ids) with ordinality a(id,ord) join questions q on q.id=a.id and q.status='published';
if coalesce(jsonb_array_length(qs),0)<>z.question_count then raise exception 'ქუიზის კითხვების შემოწმება დაუსრულებელია'; end if;
end if;
insert into sessions(user_id,mode,day,quiz_id,title,items) values(auth.uid(),p_mode,d,case when p_mode='daily' then d::text else p_quiz end,title_text,qs) returning * into s;
return quiz_state(s); end; $$;
create or replace function public.answer_game(p_session uuid,p_position int,p_choice int) returns jsonb language plpgsql security definer set search_path=public as $$ declare s sessions; q jsonb; ok boolean; begin
select * into s from sessions where id=p_session and user_id=auth.uid() for update;
if s.id is null or s.finished_at is not null then raise exception 'რაუნდი მიუწვდომელია'; end if;
if p_position is null or p_position<>s.cursor or p_choice not between 0 and 3 or p_choice is null then raise exception 'პასუხი უკვე მიღებულია ან არასწორია'; end if;
if now()>s.started_at+jsonb_array_length(s.items)*interval '40 seconds' then update sessions set finished_at=now() where id=s.id returning * into s; return jsonb_build_object('expired',true,'state',quiz_state(s)); end if;
q:=s.items->s.cursor; ok:=p_choice=(q->>'answer_index')::int;
insert into seen values(auth.uid(),q->>'family_id') on conflict do nothing;
update sessions set score=score+case when ok then 100 else 0 end,cursor=cursor+1,finished_at=case when cursor+1=jsonb_array_length(items) then now() else null end where id=s.id returning * into s;
return jsonb_build_object('correct',ok,'answer_index',q->'answer_index','explanation',q->>'explanation','source_url',q->>'source_url','source_title',q->>'source_title','source_locator',q->>'source_locator','state',quiz_state(s)); end; $$;
create or replace function public.leaderboard(p_mode text default 'quiz',p_quiz text default null,p_period text default 'week') returns jsonb language plpgsql security definer set search_path=public as $$ declare d date:=(now() at time zone 'Asia/Tbilisi')::date; cutoff date; begin
cutoff:=case when p_period='month' then date_trunc('month',d)::date when p_period='day' then d else date_trunc('week',d)::date end;
return coalesce((select jsonb_agg(to_jsonb(t)) from (select p.nickname,round(avg(s.score::numeric/jsonb_array_length(s.items)),1) points,count(*) rounds from sessions s join profiles p on p.id=s.user_id where mode=p_mode and finished_at is not null and (p_mode<>'daily' or day>=cutoff) and (p_quiz is null or quiz_id=p_quiz) group by p.id,p.nickname order by points desc,rounds desc,p.nickname,p.id limit 50) t),'[]'); end; $$;
create or replace function public.game_info() returns jsonb language sql security definer set search_path=public as $$ select jsonb_build_object('published',(select count(*) from questions where status='published'),'drafts',(select count(*) from questions where status='draft'),'editor',exists(select 1 from editors where id=auth.uid())); $$;
create or replace function public.import_questions(p_items jsonb) returns int language plpgsql security definer set search_path=public as $$ declare q jsonb; n int:=0; begin
if not exists(select 1 from editors where id=auth.uid()) then raise exception 'ადმინისტრატორის უფლება საჭიროა'; end if;
if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>500 then raise exception 'მაქსიმუმ 500 კითხვა ერთ ატვირთვაზე'; end if;
for q in select value from jsonb_array_elements(p_items) loop
insert into questions(id,family_id,prompt,options,answer_index,explanation,topic,kind,difficulty,source_url,source_title,source_locator,status) values(coalesce((q->>'id')::uuid,gen_random_uuid()),q->>'family_id',q->>'prompt',q->'options',(q->>'answer_index')::int,q->>'explanation',q->>'topic',q->>'kind',(q->>'difficulty')::int,q->>'source_url',q->>'source_title',q->>'source_locator','draft') on conflict(id) do nothing; n:=n+1; end loop; return n; end; $$;
create or replace function public.editor_questions() returns jsonb language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if; return coalesce((select jsonb_agg(to_jsonb(q)) from (select * from questions where status='draft' order by id limit 100) q),'[]'); end; $$;
create or replace function public.publish_question(p_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if; update questions set status='published',reviewed_at=current_date where id=p_id and status='draft' and length(source_locator)>5 and length(explanation)>10; end; $$;
create or replace function public.quiz_results(p_session uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare s sessions; begin select * into s from sessions where id=p_session and user_id=auth.uid() and finished_at is not null; if s.id is null then raise exception 'შედეგები მიუწვდომელია'; end if; return s.items; end; $$;
create or replace function public.editor_quizzes() returns jsonb language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if; return coalesce((select jsonb_agg(to_jsonb(q)) from quizzes q where status='draft'),'[]'); end; $$;
create or replace function public.publish_quiz(p_id text) returns void language plpgsql security definer set search_path=public as $$ declare z quizzes; n int; begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if; select * into z from quizzes where id=p_id; select count(distinct family_id) into n from questions where id=any(z.question_ids) and status='published'; if n<>z.question_count or cardinality(z.question_ids)<>z.question_count then raise exception 'ჯერ დაამტკიცეთ ყველა კითხვა; სცენარები უნდა იყოს განსხვავებული'; end if; update quizzes set status='published' where id=p_id; end; $$;
create or replace function public.import_quizzes(p_items jsonb) returns int language plpgsql security definer set search_path=public as $$ declare q jsonb; ids uuid[]; n int:=0; begin if not exists(select 1 from editors where id=auth.uid()) then raise exception 'წვდომა აკრძალულია'; end if; if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>50 then raise exception 'მაქსიმუმ 50 ქუიზი'; end if; for q in select value from jsonb_array_elements(p_items) loop select array_agg(value::uuid) into ids from jsonb_array_elements_text(q->'question_ids'); insert into quizzes(id,title,theme,question_count,question_ids,status) values(q->>'id',q->>'title',q->>'theme',(q->>'question_count')::int,ids,'draft') on conflict(id) do nothing; n:=n+1; end loop; return n; end; $$;
revoke execute on function public.import_quizzes(jsonb) from public,anon,authenticated;
grant execute on function public.import_quizzes(jsonb) to authenticated;
revoke execute on function public.quiz_results(uuid),public.editor_quizzes(),public.publish_quiz(text) from public,anon,authenticated;
grant execute on function public.quiz_results(uuid),public.editor_quizzes(),public.publish_quiz(text) to authenticated;
revoke execute on function public.quiz_catalog() from public,anon,authenticated;
grant execute on function public.quiz_catalog() to anon,authenticated;
revoke execute on function public.make_profile(),public.quiz_state(public.sessions),public.start_game(text,text),public.answer_game(uuid,int,int),public.leaderboard(text,text,text),public.game_info(),public.import_questions(jsonb),public.editor_questions(),public.publish_question(uuid) from public,anon,authenticated;
grant execute on function public.game_info(),public.leaderboard(text,text,text) to anon,authenticated;
grant execute on function public.start_game(text,text),public.answer_game(uuid,int,int),public.import_questions(jsonb),public.editor_questions(),public.publish_question(uuid) to authenticated;
commit;

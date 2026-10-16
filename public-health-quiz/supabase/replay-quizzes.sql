begin;
drop index if exists public.quiz_first;

create or replace function public.start_game(p_mode text,p_quiz text default null) returns jsonb language plpgsql security definer set search_path=public as $$ declare s sessions; qs jsonb; d date:=(now() at time zone 'Asia/Tbilisi')::date; z quizzes; title_text text; theme_text text; begin
if auth.uid() is null then raise exception 'ჯერ შედით ანგარიშში'; end if;
if p_mode is null or p_mode not in ('quiz','daily') then raise exception 'უცნობი რეჟიმი'; end if;
perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
if p_mode='daily' then select * into s from sessions where user_id=auth.uid() and mode='daily' and day=d; else select * into s from sessions where user_id=auth.uid() and mode='quiz' and quiz_id=p_quiz and finished_at is null and now()<=started_at+jsonb_array_length(items)*interval '40 seconds' order by started_at desc limit 1; end if;
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

create or replace function public.leaderboard(p_mode text default 'quiz',p_quiz text default null,p_period text default 'week') returns jsonb language plpgsql security definer set search_path=public as $$ declare d date:=(now() at time zone 'Asia/Tbilisi')::date; cutoff date; begin
cutoff:=case when p_period='month' then date_trunc('month',d)::date when p_period='day' then d else date_trunc('week',d)::date end;
return coalesce((select jsonb_agg(to_jsonb(t)) from (select p.nickname,round(avg(s.score::numeric/jsonb_array_length(s.items)),1) points,count(*) rounds from sessions s join profiles p on p.id=s.user_id where mode=p_mode and finished_at is not null and (p_mode<>'daily' or day>=cutoff) and (p_quiz is null or quiz_id=p_quiz) and (p_mode<>'quiz' or s.id=(select first_try.id from sessions first_try where first_try.user_id=s.user_id and first_try.mode='quiz' and first_try.quiz_id=s.quiz_id and first_try.finished_at is not null order by first_try.started_at,first_try.id limit 1)) group by p.id,p.nickname order by points desc,rounds desc,p.nickname,p.id limit 50) t),'[]'); end; $$;
commit;

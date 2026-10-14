import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';import assert from 'node:assert/strict';
const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,raw_user_meta_data jsonb);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
await db.exec(fs.readFileSync('supabase/schema.sql','utf8').replace('create extension if not exists pgcrypto;',''));await db.exec(fs.readFileSync('supabase/seed-drafts.sql','utf8'));
const uid='11111111-1111-4111-8111-111111111111';await db.query(`insert into auth.users values($1,'{"nickname":"ტესტერი"}')`,[uid]);await db.exec(`set request.jwt.claim.sub='${uid}';`);
async function call(sql,args=[]){return (await db.query(sql,args)).rows[0]}
await assert.rejects(()=>call("select public.start_game('quiz','foundations-15')"));
await db.exec("update questions set status='published';update quizzes set status='published';set role authenticated;");
let s=(await call("select public.start_game('quiz','foundations-15') s")).s;assert.equal(s.total,15);assert.equal(s.question.answer_index,undefined);assert.equal(s.question.explanation,undefined);
await assert.rejects(()=>call('select * from public.questions'));await assert.rejects(()=>call('select * from public.sessions'));
await assert.rejects(()=>call('select public.publish_question($1)',[s.question.id]));
await assert.rejects(()=>call('select public.answer_game($1,null,0)',[s.session_id]));
const seed=JSON.parse(fs.readFileSync('data/questions.json'));for(let i=0;i<15;i++){const r=(await call('select public.answer_game($1,$2,$3) r',[s.session_id,i,seed[i].answer_index])).r;s=r.state;if(i===0)await assert.rejects(()=>call('select public.answer_game($1,0,0)',[s.session_id]));}
assert.equal(s.finished,true);assert.equal(s.score,1500);
const same=(await call("select public.start_game('quiz','foundations-15') s")).s;assert.equal(same.session_id,s.session_id);
const board=(await call("select public.leaderboard('quiz','foundations-15','week') b")).b;assert.equal(board[0].points,100);
let daily=(await call("select public.start_game('daily') s")).s;assert.equal(daily.total,15);assert.equal(daily.question.answer_index,undefined);
await db.exec("reset role;insert into auth.users values('22222222-2222-4222-8222-222222222222','{\"nickname\":\"მეორე\"}');set request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';set role authenticated;");let d2=(await call("select public.start_game('daily') s")).s;assert.equal(daily.question.id,d2.question.id);await assert.rejects(()=>call('select public.answer_game($1,0,0)',[daily.session_id]));
await db.exec("reset role;update sessions set started_at=now()-interval '2 hours' where id='"+d2.session_id+"';set role authenticated;");const expired=(await call('select public.answer_game($1,0,0) r',[d2.session_id])).r;assert.equal(expired.expired,true);assert.equal(expired.state.score,0);assert.equal(expired.state.finished,true);
console.log('PASS: schema, draft gate, 15-question quiz, hidden answers, RLS, editor gate, replay protection, first attempt, ranking normalization, daily equality, session ownership');await db.close();

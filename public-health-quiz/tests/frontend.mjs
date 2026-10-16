import vm from 'node:vm';import fs from 'node:fs';import assert from 'node:assert/strict';
const nodes=new Map(), classes=()=>({add(){},contains(){return false},toggle(){}});
const node=s=>{if(!nodes.has(s))nodes.set(s,{innerHTML:'',textContent:'',value:'',dataset:{},classList:classes(),showModal(){this.opened=true},close(){this.opened=false},reportValidity(){return true}});return nodes.get(s)};
const bank=JSON.parse(fs.readFileSync('dist/demo-questions.json'));const stored=new Map();let fetchMock=async()=>({json:async()=>bank});
const context=vm.createContext({document:{querySelector:node,querySelectorAll:()=>[],body:{classList:classes()}},window:{QUIZ_CONFIG:{url:'',key:''}},localStorage:{getItem:k=>stored.get(k)||null,setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)},fetch:(...args)=>fetchMock(...args),setInterval:()=>1,clearInterval(){},setTimeout:()=>1,clearTimeout(){},URL,Date,Math,JSON,Number,String,atob,alert:msg=>{throw Error(msg)}});
vm.runInContext(fs.readFileSync('dist/app.js','utf8'),context);await new Promise(r=>setImmediate(r));

const css=fs.readFileSync('dist/style.css','utf8');assert.match(css,/\.question-card \.option\{[^}]*background:var\(--card\);color:var\(--ink\)/);assert.match(css,/body\.dark \.question-card \.option\{[^}]*color:#f1f4fd/);
await vm.runInContext('home()',context);assert.match(node('#main').innerHTML,/feature-panel/);assert.doesNotMatch(node('#main').innerHTML,/play-art|art-orbit|ცნობისმოყვარეობა გიხდება/);assert.match(css,/prefers-reduced-motion:reduce/);
await vm.runInContext('quizzes()',context);assert.match(node('#main').innerHTML,/ქუიზების კატალოგი/);assert.match(node('#main').innerHTML,/რეგისტრაცია/);assert.doesNotMatch(node('#main').innerHTML,/სატესტო ქუიზის ნახვა/);
await vm.runInContext("start('demo')",context);assert.equal(vm.runInContext('state',context),null);assert.equal(node('#settings').opened,true);
await vm.runInContext("config={url:'https://example.supabase.co',key:'public'};auth={access_token:'test',expires_at:Date.now()/1000+3600}",context);
await vm.runInContext("start('demo')",context);assert.equal(vm.runInContext('state.total',context),15);assert.match(node('#main').innerHTML,/კითხვა 1/);assert.match(node('#main').innerHTML,/role="progressbar"/);
for(let i=0;i<15;i++)await vm.runInContext('answer(state.question.answer_index)',context);
assert.equal(vm.runInContext('state.score',context),1500);assert.equal(vm.runInContext('state.finished',context),true);assert.match(node('#main').innerHTML,/100<span>%/);assert.match(node('#main').innerHTML,/15 სწორი პასუხი/);assert.match(node('#main').innerHTML,/მთავარ გვერდზე/);
assert.equal(vm.runInContext("sourceLink('javascript:alert(1)')",context),'#');assert.equal(vm.runInContext("esc('<img>')",context),'&lt;img&gt;');
await vm.runInContext('results()',context);assert.match(node('#main').innerHTML,/პასუხები და წყაროები/);
assert.equal(bank.length,15);const q=JSON.parse(fs.readFileSync('data/questions.json'));assert.equal(q.length,30);assert.equal(new Set(q.map(x=>x.family_id)).size,30);assert.equal(bank.some(x=>q.some(y=>y.id===x.id||y.family_id===x.family_id)),false);
console.log('PASS: registration gate, authenticated quiz start, scoring, results, escaping, safe links, distinct seed/demo families');

fetchMock=async(url,options)=>{if(url.includes('/auth/v1/token'))return{ok:false,status:400,json:async()=>({error:'invalid_grant',error_description:'Invalid Refresh Token'})};if(url.includes('/rest/v1/rpc/quiz_catalog'))return{ok:true,status:200,json:async()=>[{id:'public-1',title:'სატესტო ქუიზი',theme:'ეპიდემიოლოგია',question_count:15}]};throw Error('Unexpected request: '+url)};
await vm.runInContext("(async()=>{auth={access_token:'expired',refresh_token:'stale',expires_at:Date.now()/1000-10};saveAuth(auth);await refreshInfo()})()",context);
assert.equal(vm.runInContext('auth',context),null);assert.equal(node('#account').textContent,'შესვლა');assert.equal(node('#joinButton').hidden,false);assert.equal(vm.runInContext('catalog.length',context),1);
await vm.runInContext('quizzes()',context);assert.match(node('#main').innerHTML,/ქუიზების კატალოგი/);assert.match(node('#main').innerHTML,/გამოქვეყნებული ქუიზი/);
console.log('PASS: expired sessions clear the stale login state and public quiz catalog still loads');


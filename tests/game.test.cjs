const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

function game(){
 const elements=new Map(),root={innerHTML:''},calls=[];
 const questions=JSON.parse(fs.readFileSync('questions.js','utf8').split('export const questions = ')[1].replace(/;\s*$/,''));
 let source=fs.readFileSync('src.js','utf8').replace(/^import .*;\r?\n/gm,'').replace(/^const url=.*;\r?\n/m,'').replace(/^const db=.*;\r?\n/m,'');
 source=source.slice(0,source.lastIndexOf('if(!db){'));
 const db={auth:{getSession:async()=>({data:{session:{user:{id:'player'}}}})},rpc:async(name,args)=>{calls.push({name,args});return {data:context.next};}};
 const context=vm.createContext({questions,db,document:{querySelector:selector=>selector==='#app'?root:elements.get(selector)||elements.set(selector,{style:{setProperty(){}},setAttribute(){},isConnected:true}).get(selector)},location:{origin:'http://localhost',pathname:'/',search:'?room=ABC123'},URLSearchParams});
 vm.runInContext(source,context);
 const run=code=>vm.runInContext(code,context);
 function render(overrides={}){context.input={code:'ABC123',joined:true,role:'host',mine:null,theirs:null,round:0,question_count:5,question_id:114,can_reroll:true,scores:[],...overrides};run('state=input;render()');return root.innerHTML;}
 return {context,run,render,root,questions,elements,calls};
}

test('115 stable question IDs include the supplied 100 statements',()=>{
 const {questions}=game();assert.equal(questions.length,115);assert.equal(new Set(questions.map(q=>q[1])).size,115);
 assert.match(questions[15][1],/^It is important that your partner can tell/);
 assert.match(questions[114][1],/all your flaws/);
});
test('room length chooser offers every integer from 5 through 15',()=>{
 const g=game();g.run('lobby()');assert.equal((g.root.innerHTML.match(/<option /g)||[]).length,11);
 for(let n=5;n<=15;n++)assert.match(g.root.innerHTML,new RegExp(`value="${n}"`));
});
test('selected question ID and room length control rounds and recap',()=>{
 const g=game();assert.match(g.render(),/ROUND 1 \/ 5/);assert.match(g.root.innerHTML,/all your flaws/);
 for(const count of [5,10,15]){
  assert.match(g.render({round:count-1,question_count:count}),new RegExp(`ROUND ${count} / ${count}`));
  assert.match(g.render({round:count,question_count:count,scores:[{distance:0},{distance:100}]}),/class="bigscore">50%/);
  assert.match(g.root.innerHTML,new RegExp(`exact matches out of ${count}`));
 }
});
test('reroll disables after a submission and zero answers reveal correctly',()=>{
 const g=game();assert.match(g.render(),/id="reroll" class="reroll" >/);
 assert.match(g.render({mine:0,can_reroll:false}),/id="reroll" class="reroll" disabled/);
 assert.doesNotMatch(g.root.innerHTML,/class="comparison"/);
 assert.match(g.render({mine:0,theirs:100,can_reroll:false}),/100% apart/);
 assert.doesNotMatch(g.root.innerHTML,/id="reroll"/);
});
test('same-round reroll resets the slider and sends current question identity',async()=>{
 const g=game();g.render({question_id:0});g.run('selected=87');
 g.context.next={...g.context.input,question_id:114};await g.run('refresh()');assert.equal(g.run('selected'),50);
 assert.match(g.root.innerHTML,/all your flaws/);
 await g.run('submit()');const call=g.calls.find(c=>c.name==='submit_answer');
 assert.equal(call.args.p_question_id,114);assert.equal(call.args.p_round,0);assert.equal(call.args.p_value,50);
});

test('final recap shows every played question with both answers and preserves scores',()=>{
 const g=game();
 const answers=Array.from({length:5},(_,round)=>({round,question_id:round===0?114:round,mine:round===0?0:75,theirs:round===0?100:75}));
 const html=g.render({round:5,answers,scores:answers.map(a=>({distance:Math.abs(a.mine-a.theirs)}))});
 assert.equal((html.match(/class="recap-card"/g)||[]).length,5);
 assert.match(html,/all your flaws/);assert.match(html,/class="bigscore">80%/);
 assert.match(html,/<strong>4<\/strong> exact matches out of 5/);
 assert.match(html,/You: 0% toward agree completely/);assert.match(html,/Them: 100% toward agree completely/);
 assert.match(html,/0% alignment/);assert.match(html,/100% alignment/);
});

test('answer recap is hidden before the game ends and handles older databases',()=>{
 const g=game();
 assert.doesNotMatch(g.render({answers:[{round:0,question_id:0,mine:0,theirs:100}]}),/class="answer-recap"/);
 assert.match(g.render({round:5}),/Run migration 003/);
});

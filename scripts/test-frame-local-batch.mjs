// Run production key/transition helpers and backdrop size delivery on the host.
// BEFORE_FRAME_BATCH enables exact old/new preparation-key differentials.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const read=p=>fs.readFileSync(new URL('../'+p,import.meta.url),'utf8');
const compile=s=>ts.transpileModule(s.replace(/^import[\s\S]*?;\n/gm,'').replace(/\bexport /g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
let templates=0,scales=0;
const instrument=context=>{
 const visit=node=>{
  const next=ts.visitEachChild(node,visit,context);
  return ts.isTemplateExpression(node)?ts.factory.createCallExpression(ts.factory.createIdentifier('__template'),undefined,[next]):next;
 };return node=>ts.visitNode(node,visit);
};
const ctx=vm.createContext({__template:v=>{templates++;return v;},Curve:{EaseOut:'EaseOut'},
 TransitionEffect:{OPACITY:'opacity',scale:opts=>{scales++;return {opts,combine(v){this.combined=v;return this;},animation(v){this.animationOptions=v;return this;}};}}});
vm.runInContext(ts.transpileModule(read('entry/src/main/ets/util/preparedMessageKeyCache.ets').replace(/\bexport /g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020},transformers:{before:[instrument]}}).outputText+
 compile(read('entry/src/main/ets/util/reactionTransitions.ets'))+'\nglobalThis.Keys=PreparedMessageKeyCache;globalThis.Fx=ReactionTransitions;',ctx);
const cache=new ctx.Keys(),row={},args=[row,'message_group_message_1_0_0',-100,0,'',0,0,0,300,[],'|g10'];
assert.equal(cache.prepare(...args),'message_group_message_1_0_0|c-100|lw0|u0|r0|editable0|poll0|pin0|paid0|anim000|fresh0|slot|slotms0|msg0|bg0|width300|selm|g10');
templates=0;for(let i=0;i<1000;i++)cache.prepare(...args);assert.equal(templates,0);
for(let i=1;i<args.length;i++){
 const next=[...args];next[i]=i===9?[1,2]:typeof args[i]==='number'?args[i]+1:args[i]+'x';
 assert.notEqual(cache.prepare(...next),cache.prepare(...args),`input ${i}`);
}
for(let bit=0;bit<11;bit++)assert.notEqual(cache.prepare(...args.slice(0,3),1<<bit,...args.slice(4)),cache.prepare(...args));
const selected=[1];const selectedArgs=[...args];selectedArgs[9]=selected;const first=cache.prepare(...selectedArgs);selected[0]=2;assert.notEqual(cache.prepare(...selectedArgs),first);
cache.clear();templates=0;cache.prepare(...args);assert.ok(templates>0);
let differential=0;
if(process.env.BEFORE_FRAME_BATCH){
 const source=fs.readFileSync(process.env.BEFORE_FRAME_BATCH+'/entry/src/main/ets/pages/chat/ChatTimelineSession.ets','utf8');
 const start=source.indexOf('    const cacheKey: string = `${this.rowKeyOf(g)}');const end=source.indexOf('    const cached:',start);
 assert.ok(start>=0&&end>start);
 const fn=`function original(rowKey,chatId,flags,rowSlot,rowSlotStartMs,messageRevision,backgroundRevision,contentWidth,selectedMemberIds,pageKey){
 const g={};const page={keyPart:pageKey};const audio=true;
 const lightweightRow=!!(flags&1),showUnreadDivider=!!(flags&2),showResumeDivider=!!(flags&4),menuEditable=!!(flags&8),pollExpired=!!(flags&16),isPinnedMsg=!!(flags&32),paidMediaPending=!!(flags&64),paused=!!(flags&128),forcePlay=!!(flags&256),playbackFailed=!!(flags&512),animateIn=!!(flags&1024);
 ${source.slice(start,end)} return cacheKey;}`;
 vm.runInContext(compile(fn),ctx);
 let seed=9;const rand=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
 for(let i=0;i<10000;i++){
  const a=[row,'message_group_album_'+rand(40)+'_'+rand(3),rand(2)?-100:1,rand(2048),rand(2)?'12_0':'',rand(1000),rand(7),rand(5),250+rand(150),rand(2)?[1,2]:[],`|page${rand(6)}`];
  assert.equal(cache.prepare(...a),ctx.original.call({rowKeyOf:()=>a[1],bindings:{chatId:()=>a[2]},messageListRevision:a[6],chatBackgroundRevision:a[7]},...a.slice(1)));differential++;
 }
}
const fx=new ctx.Fx(),reaction={};const effect=fx.prepare(reaction,180);scales=0;
for(let i=0;i<1000;i++)assert.equal(fx.prepare(reaction,180),effect);assert.equal(scales,0);
assert.equal(effect.opts.x,.6);assert.equal(effect.opts.y,.6);assert.equal(effect.combined,'opacity');assert.equal(effect.animationOptions.duration,180);
const zero=fx.prepare(reaction,0);assert.notEqual(zero,effect);assert.equal(zero.animationOptions.duration,0);assert.equal(effect.animationOptions.duration,180);assert.notEqual(fx.prepare({},0),zero);
// Execute the real measured-size callback. Position-only events no longer own a listener.
const backdrop=read('entry/src/main/ets/pages/chat/ChatBackdrop.ets');const a=backdrop.indexOf('.onSizeChange((_old: SizeOptions, size: SizeOptions): void => {');assert.ok(a>=0);
const b=backdrop.indexOf('\n      })',a);const callback=backdrop.slice(a+'.onSizeChange('.length,b+8-1); // ending brace, without ')'
const deliveries=[],targets=[];const bctx=vm.createContext({publishChatContentWidth:w=>deliveries.push(w),setInlinePhotoTargetPx:w=>targets.push(w),vp2px:w=>w*3,mediaThumbWidth:w=>w-40});
vm.runInContext(compile('globalThis.deliver = function'+callback.slice(callback.indexOf('('),callback.indexOf('=>'))+callback.slice(callback.indexOf('=>')+2)+';'),bctx);
const state={areaW:0,areaH:0};bctx.deliver.call(state,{}, {width:390,height:700});assert.deepEqual(state,{areaW:390,areaH:700});
bctx.deliver.call(state,{}, {width:300,height:400});assert.deepEqual(state,{areaW:300,areaH:400});
bctx.deliver.call(state,{}, {width:'100%',height:400});assert.deepEqual(state,{areaW:300,areaH:400});assert.deepEqual(deliveries,[390,300]);assert.equal(targets.length,2);
assert.ok(!backdrop.includes('.onAreaChange('));
console.log(`Frame local batch: key inputs/11 decisions/selection mutation/clear passed; 1000 key hits no templates; ${differential} exact old-key differentials; 1000 reaction hits no new descriptors; independent durations/chips and backdrop initial/resize/invalid delivery passed.`);

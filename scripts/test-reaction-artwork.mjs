// Execute production metadata/cache/image controllers with deterministic TDLib,
// file and decoder boundaries. Does not claim raster or device timing coverage.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
function load(ctx,file,names=[]){
 const src=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(src+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});
}
const flush=async()=>{for(let i=0;i<10;i++)await Promise.resolve();};
const file=(id,path='')=>({id,local:{path,is_downloading_completed:!!path}});
const sticker=(id,format='stickerFormatWebp')=>({format:{'@type':format},sticker:file(id),thumbnail:{file:file(id+1000)},emoji:'🙂'});
const standard=id=>({static_icon:sticker(id),center_animation:sticker(id+100,'stickerFormatTgs')});
function service(){
 let now=1,owner;
 const calls=[],logs=[];
 const createClient=()=>{const created={send(request){return new Promise((resolve,reject)=>calls.push({request,resolve,reject,owner:created}));}};return created;};
 owner=createClient();
 const ctx=vm.createContext({getTdClient:()=>owner,Date:{now:()=>now},logW:msg=>logs.push(msg),parseReactionKey:key=>key.startsWith('ce:')?{emoji:'',customEmojiId:key.slice(3)}:{emoji:key,customEmojiId:''},customEmojiNeedsRepainting:s=>s.full_type?.needs_repainting===true});
 load(ctx,'services/ReactionArtwork.ets',['watchReactionArtwork','reactionArtworkFrom','resetReactionArtwork']);
 return{ctx,calls,logs,tick:ms=>now+=ms,switchClient(){owner=createClient();return owner;},setClient:client=>owner=client,state:()=>vm.runInContext('({active,records:records.size,recent:recent.size,queued:first?.key??null})',ctx)};
}
{
 const s=service(),{ctx,calls}=s,events=[];
 const offA=ctx.watchReactionArtwork('👍',x=>events.push(['A',x])),offB=ctx.watchReactionArtwork('👍',x=>events.push(['B',x]));
 await flush();assert.equal(calls.length,1,'concurrent same reaction is single-flight');calls[0].resolve(standard(1));await flush();
 assert.equal(events.filter(e=>e[1]).length,2);assert.equal(s.state().active,0);offA();offB();
 const off=ctx.watchReactionArtwork('👍',x=>assert.equal(x.poster.id,1));await flush();assert.equal(calls.length,1);off();
 s.tick(300001);const fresh=ctx.watchReactionArtwork('👍',()=>{});await flush();assert.equal(calls.length,2);calls[1].resolve(standard(2));await flush();fresh();
 assert.equal(s.state().records,0);
 const custom=sticker(5,'stickerFormatTgs');custom.full_type={'@type':'stickerFullTypeCustomEmoji',custom_emoji_id:'9007199254740999',needs_repainting:true};
 const parsed=ctx.reactionArtworkFrom('ce:9007199254740999',{stickers:[sticker(4),custom]});
 assert.equal(parsed.poster.id,1005);assert.equal(parsed.animation.id,5);assert.equal(parsed.repaint,true);
 assert.equal(ctx.reactionArtworkFrom('ce:9007199254740998',{stickers:[custom]}),null,'never assign another int64 sticker by index');
 const idOff=ctx.watchReactionArtwork('ce:9007199254740999',()=>{});await flush();assert.equal(calls.at(-1).request.custom_emoji_ids[0],'9007199254740999');calls.at(-1).resolve({stickers:[custom]});await flush();idOff();
}
{
 const s=service(),off=[];
 for(let i=0;i<10;i++)off.push(s.ctx.watchReactionArtwork('r'+i,()=>{}));await flush();assert.equal(s.calls.length,4);assert.equal(s.state().active,4);
 off[5]();s.calls[0].resolve(standard(0));await flush();assert.equal(s.calls.length,5);assert.equal(s.calls[4].request.emoji,'r4');
 s.calls[1].resolve(standard(1));await flush();assert.equal(s.calls[5].request.emoji,'r6','cancel queued node in O(1)');
 off.forEach(fn=>fn());for(const call of s.calls)call.resolve(standard(5));await flush();assert.equal(s.state().active,0);assert.equal(s.state().records,0);
 const cancelled=s.ctx.watchReactionArtwork('never-sent',()=>{});cancelled();await flush();assert.equal(s.calls.length,6,'cancel before microtask skips dispatch');
 const retry=s.ctx.watchReactionArtwork('never-sent',()=>{});await flush();assert.equal(s.calls.length,7,'cancellation must not create a negative cache');s.calls.at(-1).resolve(standard(8));await flush();retry();
}
{
 const s=service(),seen=[];const off=s.ctx.watchReactionArtwork('failure',x=>seen.push(x));await flush();s.calls[0].reject(Error('network'));await flush();assert.equal(s.state().active,0);
 const second=s.ctx.watchReactionArtwork('failure',()=>{});await flush();assert.equal(s.calls.length,1);second();
 s.tick(15001);const third=s.ctx.watchReactionArtwork('failure',()=>{});await flush();assert.equal(s.calls.length,2,'negative cache expires even if another subscriber stays mounted');s.calls[1].resolve(standard(2));await flush();assert.equal(seen.at(-1).poster.id,2);off();third();
 s.setClient({send(){throw Error('synchronous bridge failure');}});const syncOff=s.ctx.watchReactionArtwork('sync',()=>{});await flush();assert.equal(s.state().active,0);syncOff();
}
{
 const s=service(),seen=[];const a=s.ctx.watchReactionArtwork('same',x=>{if(x)seen.push('old');});await flush();
 s.switchClient();const b=s.ctx.watchReactionArtwork('same',x=>{if(x)seen.push('new');});await flush();
 s.calls[0].resolve(standard(1));await flush();assert.equal(seen.length,0);assert.equal(s.state().active,1);a();
 s.calls[1].resolve(standard(2));await flush();assert.deepEqual(seen,['new']);b();
}
{
 const s=service();let bCount=0,bOff;const a=s.ctx.watchReactionArtwork('join',value=>{if(value&&!bOff)bOff=s.ctx.watchReactionArtwork('join',next=>{if(next)bCount++;});});await flush();s.calls[0].resolve(standard(1));await flush();assert.equal(bCount,1,'reentrant new subscriber receives one snapshot');a();bOff();
 const bad=s.ctx.watchReactionArtwork('throw',()=>{throw Error('consumer');});const goodSeen=[];const good=s.ctx.watchReactionArtwork('throw',x=>goodSeen.push(x));await flush();s.calls[1].resolve(standard(3));await flush();assert.equal(goodSeen.at(-1).poster.id,3);assert.ok(s.logs.length>=2);bad();good();
 // Finishing a callback may remove its record; queued work must still drain.
 let self;self=s.ctx.watchReactionArtwork('self',value=>{if(value)self();});
 const offs=[];for(let i=0;i<4;i++)offs.push(s.ctx.watchReactionArtwork('after'+i,()=>{}));await flush();const first=s.calls.find(c=>c.request.emoji==='self');first.resolve(standard(4));await flush();assert.ok(s.calls.some(c=>c.request.emoji==='after3'));
 offs.forEach(fn=>fn());s.calls.forEach(c=>c.resolve(standard(5)));await flush();
}
{
 const s=service();
 for(let i=0;i<260;i++){const off=s.ctx.watchReactionArtwork('cache'+i,()=>{});await flush();s.calls.at(-1).resolve(standard(i+1));await flush();off();}
 assert.equal(s.state().recent,256);assert.equal(s.state().records,0);
 const hit=s.ctx.watchReactionArtwork('cache259',()=>{});await flush();assert.equal(s.calls.length,260);hit();
 const miss=s.ctx.watchReactionArtwork('cache0',()=>{});await flush();assert.equal(s.calls.length,261);s.calls.at(-1).resolve(standard(1));await flush();miss();
}
{
 const s=service();let switched=false,newOwner;const offs=[];
 const off=s.ctx.watchReactionArtwork('old-watch',()=>{
  if(switched)return;switched=true;newOwner=s.switchClient();
  for(let i=0;i<6;i++)offs.push(s.ctx.watchReactionArtwork('new'+i,()=>{}));
 });
 await flush();assert.equal(s.calls.length,4);assert.ok(s.calls.every(call=>call.owner===newOwner),'initial observer account switch must not pump new-account queue on old client');
 off();offs.forEach(fn=>fn());s.calls.forEach(call=>call.resolve(standard(1)));await flush();
}
{
 const s=service();let delivered=0;const off=s.ctx.watchReactionArtwork('paid:stars',value=>{assert.equal(value,null);delivered++;});await flush();
 assert.equal(delivered,1);assert.equal(s.calls.length,0);assert.equal(s.state().records,0);off();
}
console.log('PASS: production reaction metadata single-flight, 4-request queue, bounded 256 LRU/TTL, error retry, cancellation, reentrant observers/account changes and exact int64 matching.');

function images(){
 let now=100,serial=0,changes=0,labels=0,filters=0;
 const timers=new Map(),metadata=[],files=[],sessions=[],requests=[],paint=[];
 class Brush{setAntiAlias(){}setColorFilter(filter){this.filter=filter;}}
 class Session{constructor(callback){this.callback=callback;this.active=false;sessions.push(this);}update(spec){this.spec=spec;}activate(spec){this.active=true;this.spec=spec;}dispose(){this.active=false;}}
 const ctx=vm.createContext({Date:{now:()=>now},setTimeout:fn=>{timers.set(++serial,fn);return serial;},clearTimeout:id=>timers.delete(id),
  drawing:{Brush,ColorFilter:{createBlendModeColorFilter:color=>{filters++;return {...color};}},BlendMode:{SRC_IN:1}},ImageFit:{Contain:1},
  DrawnImageReceiver:class{bind(){}setPixels(p){this.pixels=p;}canDraw(p){return !p?.invalid;}drawFront(){paint.push('image');}},
  CachedImageSession:Session,DrawnTextLineCache:class{prepare(text){labels++;return {heightPx:20,recolor(){},paragraph:{paint(){paint.push(text);}}};}},
  watchReactionArtwork:(key,callback)=>{const record={key,callback,off:false};metadata.push(record);callback(null);return()=>record.off=true;},
  documentFileId:f=>f?.id??0,documentFilePath:f=>f?.local?.path??'',documentFileState:f=>({path:f?.local?.path??'',failed:f?.failed??false}),
  watchDocumentFile:(f,callback)=>{const record={file:f,callback,off:false};files.push(record);return()=>record.off=true;},requestDocumentFile:(f,p,retry)=>requests.push({id:f.id,retry}),THUMBNAIL_PRIORITY:1});
 load(ctx,'pages/chat/ReactionImage.ets',['ReactionImage']);
 const canvas={attachBrush:b=>paint.push(b.filter),detachBrush:()=>{}};
 return{ctx,metadata,files,sessions,requests,timers,paint,canvas,stats:()=>({changes,labels,filters}),changed:()=>changes++,tick(ms){now+=ms;for(const [id,fn]of[...timers]){timers.delete(id);fn();}}};
}
const color={alpha:255,red:20,green:40,blue:60};
{
 const r=images(),img=new r.ctx.ReactionImage({},'ce:1','',1,'1',color,r.changed);img.start('fallback.webp');assert.equal(r.sessions[0].active,true);assert.equal(r.sessions[0].spec.path,'fallback.webp');
 img.start('fallback.webp');assert.equal(r.metadata.length,1);
 r.sessions[0].callback({id:1},true,20,20);img.draw({canvas:r.canvas});assert.equal(r.paint.at(-1),'image');
 const art={poster:file(2,'poster.webp'),animation:file(4),format:'stickerFormatTgs',emoji:'🦊',repaint:true};r.metadata[0].callback(art);
 assert.equal(r.sessions[0].spec.path,'poster.webp');assert.ok(r.stats().filters>0);
 r.sessions[0].callback({id:2},true,20,20);img.draw({canvas:r.canvas});assert.equal(r.paint.at(-2).red,20);
 const before=r.stats();for(let i=0;i<1000;i++){img.update(color,'fallback.webp');img.draw({canvas:r.canvas});}assert.deepEqual(r.stats(),before,'stable draw/update does not shape/resolve colors/invalidate');
 const mutable={...color};img.update(mutable,'fallback.webp');mutable.red=90;img.update(mutable,'fallback.webp');assert.ok(r.stats().filters>before.filters,'caller color mutation cannot poison equality');
 let played=0;img.play(()=>played++);assert.equal(r.timers.size,0,'monochrome native animation stays on tinted static/pulse');assert.equal(played,0);
 const previous=r.files[0];r.metadata[0].callback({...art,poster:file(3,'new.webp')});previous.callback({path:'stale.webp'});assert.equal(r.sessions[0].spec.path,'new.webp');assert.equal(previous.off,true);
 img.dispose();const ended=r.stats().changes;r.metadata[0].callback(art);r.sessions[0].callback({id:99},true,20,20);assert.equal(r.stats().changes,ended);r.paint.length=0;img.draw({canvas:r.canvas});assert.equal(r.paint.length,0);assert.ok(r.files.every(f=>f.off));
}
{
 const r=images(),img=new r.ctx.ReactionImage({},'🔥','🔥',1,'1',color,r.changed);img.start('');
 r.metadata[0].callback({poster:undefined,animation:file(7),format:'stickerFormatWebm',emoji:'🔥',repaint:false});
 let result;img.play(x=>result=x);assert.equal(r.files.length,1);assert.equal(r.requests[0].id,7);
 r.files[0].callback({path:'animation.webm'});assert.equal(result.path,'animation.webm');assert.equal(r.files[0].off,true);assert.equal(r.timers.size,0,'successful animation releases watch and expiry timer');
 const resultCount=r.files.length;img.play(()=>assert.fail('cancelled animation'));const cancelled=r.files.at(-1);img.cancelAnimation();cancelled.callback({path:'late.webm'});assert.equal(r.timers.size,0);
 img.play(()=>assert.fail('expired animation'));const expired=r.files.at(-1);r.tick(1501);assert.equal(expired.off,true);expired.callback({path:'late.webm'});
 img.dispose();assert.ok(r.files.every(f=>f.off));assert.ok(resultCount>0);
}
{
 const r=images(),img=new r.ctx.ReactionImage({},'ce:8','',1,'1',color,r.changed);img.start('old.webp');img.update(color,'new.webp');assert.equal(r.sessions[0].spec.path,'new.webp');
 r.metadata[0].callback({poster:undefined,animation:undefined,format:'stickerFormatTgs',emoji:'🐈',repaint:false});img.draw({canvas:r.canvas});assert.equal(r.paint.at(-1),'🐈','metadata-only emoji fallback repaints');
 r.sessions[0].callback({invalid:true},true,0,0);img.draw({canvas:r.canvas});assert.equal(r.paint.at(-1),'🐈','invalid native pixel metadata cannot suppress fallback');
 img.play(()=>assert.fail('too-late metadata'));r.tick(1501);r.metadata[0].callback({poster:undefined,animation:file(1,'x.tgs'),format:'stickerFormatTgs',emoji:'🐈',repaint:false});assert.equal(r.timers.size,0);
 img.dispose();
}
{
 const r=images(),img=new r.ctx.ReactionImage({},'x','x',1,'1',color,r.changed);img.start('');r.metadata[0].callback({poster:{...file(9),failed:true},animation:undefined,format:'',emoji:'x',repaint:false});assert.equal(r.requests[0].retry,true,'new mount retries a previous failed file only once');img.dispose();
}
console.log('PASS: real ReactionImage fallback activation, poster delivery, monochrome tint, 1000 stable draws/updates, mutable-color safety, metadata-only fallback, file generation, disposal and finite animation request lifetimes.');

{
 const r=images();let recolors=0;
 const prepared={heightPx:20,recolor(){recolors++;},paragraph:{paint(){r.paint.push('shared');}}};
 const img=new r.ctx.ReactionImage({},'🔥','🔥',1,'1',color,r.changed,prepared);img.start('');
 assert.equal(r.stats().labels,0,'reuse the plan label without duplicate cold shaping');img.draw({canvas:r.canvas});assert.equal(r.paint.at(-1),'shared');
 r.metadata[0].callback({poster:undefined,animation:undefined,format:'',emoji:'🔥',repaint:false});assert.equal(r.stats().labels,0,'same metadata emoji retains prepared label');
 img.update({...color,red:88},'');assert.equal(r.stats().labels,0);assert.ok(recolors>=3,'shared label recolors without shaping');
 r.metadata[0].callback({poster:undefined,animation:undefined,format:'',emoji:'🦊',repaint:false});assert.equal(r.stats().labels,1,'different metadata emoji shapes once');
 r.metadata[0].callback({poster:undefined,animation:undefined,format:'',emoji:'🦊',repaint:false});assert.equal(r.stats().labels,1);
 img.draw({canvas:r.canvas});assert.equal(r.paint.at(-1),'🦊');img.dispose();
}
console.log('PASS: prepared emoji label reuse, metadata identity and color-only changes avoid duplicate shaping.');

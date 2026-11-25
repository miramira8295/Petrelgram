import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const ctx=vm.createContext({Map,Set,Math,Number,String,DataOperationType:{ADD:'add'}});
function run(code){vm.runInContext(ts.transpileModule(code.replace(/^import[^\n]*\n/gm,'').replace(/\bexport /g,'').replace(/@Observed\s*/g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
run(fs.readFileSync('entry/src/main/ets/pages/common/AvatarGallerySession.ets','utf8')+'\nglobalThis.Session=AvatarGallerySession;globalThis.Photo=AvatarPhoto;');
const tick=()=>new Promise(r=>setImmediate(r));
class Client {
 requests=[];listeners=new Set();
 send(req){return new Promise((resolve,reject)=>this.requests.push({req,resolve,reject}));}
 onUpdate(_name,cb){this.listeners.add(cb);return()=>this.listeners.delete(cb);}
 emit(file){for(const cb of this.listeners)cb({file});}
}
const file=(id,path='',complete=!!path)=>({id,local:{path,is_downloading_completed:complete}});
const photo=(id,image,video=0,path='',videoPath='')=>({id:String(id),sizes:[{width:160,height:160,photo:file(image+10000)},{width:640,height:640,photo:file(image,path)}],animation:video?{length:640,file:file(video,videoPath)}:undefined});
function model(user=1,chat=0,seedId=10){const c=new Client();let updates=0;const s=new ctx.Session(c,user,chat,seedId,'/current.jpg','/current.mp4',()=>updates++);return {c,s,updates:()=>updates};}
// Merge the current photo by file identity; preserve personal/public seed when absent.
const {c,s}=model();const adds=[];s.registerDataChangeListener({onDatasetChange:ops=>adds.push(...ops)});s.open();
assert.equal(c.requests[0].req['@type'],'getUserProfilePhotos');assert.equal(c.requests[0].req.limit,20);
s.loadMore();assert.equal(c.requests.length,1,'single in-flight history request');
c.requests[0].resolve({photos:[photo('9007199254740999',10,20),photo('9007199254740998',11,21),photo('9007199254740997',12,22)],total_count:5});await tick();
assert.equal(s.totalCount(),3);assert.equal(s.getData(0).key,'current');assert.equal(s.getData(0).videoPath,'/current.mp4');
assert.equal(adds.length,1);assert.equal(adds[0].index,1);assert.equal(adds[0].count,2);
assert.deepEqual(c.requests.slice(1).map(x=>x.req.file_id),[10011,11],'only adjacent thumbnail and still; no background video');
s.select(1);assert.equal(s.index,1);assert.ok(c.requests.some(x=>x.req.file_id===21));assert.ok(!c.requests.some(x=>x.req.file_id===22));
const next=c.requests.find(x=>x.req.offset===3);assert.ok(next);
next.resolve({photos:[photo('9007199254740997',12,22),photo('9007199254740996',13)],total_count:5});await tick();
assert.equal(s.totalCount(),4,'overlapping pages deduplicate without changing page identity');assert.equal(s.hasMore,false);
const before=s.getData(1).imagePath;c.emit(file(11,'/unfinished',false));assert.equal(s.getData(1).imagePath,before);
c.emit(file(11,'/eleven.jpg'));assert.equal(s.getData(1).imagePath,'/eleven.jpg');
c.emit(file(21,'/eleven.mp4'));assert.equal(s.getData(1).videoPath,'/eleven.mp4');assert.equal(s.getData(0).videoPath,'/current.mp4');
const old0=s.getData(0);s.select(3);c.emit(file(12,'/twelve.jpg'));assert.equal(s.getData(3).imagePath,'','unrelated completion cannot replace selected image');
assert.equal(s.getData(0),old0);
const download13=c.requests.find(x=>x.req.file_id===13);download13.reject(new Error('offline'));await tick();assert.equal(s.getData(3).downloadFailed,true);
s.retry();assert.equal(c.requests.filter(x=>x.req.file_id===13).length,2);
s.close();assert.equal(c.listeners.size,0);c.emit(file(13,'/late'));assert.equal(s.getData(3).imagePath,'');
const late=c.requests.filter(x=>x.req.file_id===13).at(-1);late.resolve(file(13,'/late'));await tick();assert.equal(s.getData(3).imagePath,'');
// Private/public current photo is not replaced by the first historical photo.
const a=model();a.s.open();a.c.requests[0].resolve({photos:[photo('old',30)],total_count:1});await tick();
assert.equal(a.s.totalCount(),2);assert.equal(a.s.getData(0).imagePath,'/current.jpg');a.s.updateSeedVideo('/late-current.mp4');assert.equal(a.s.getData(0).videoPath,'/late-current.mp4');
a.s.close();a.s.updateSeedVideo('/wrong');assert.equal(a.s.getData(0).videoPath,'/late-current.mp4');
// Group history uses service-photo filter and the server cursor, never local total count.
const group=model(0,-100);group.s.open();const req=group.c.requests[0].req;
assert.equal(req.filter['@type'],'searchMessagesFilterChatPhoto');assert.equal(req.from_message_id,0);
group.c.requests[0].resolve({messages:[{content:{'@type':'messageChatChangePhoto',photo:photo('a',10)}},{content:{'@type':'messageChatChangePhoto',photo:photo('b',40)}}],next_from_message_id:123});await tick();
group.s.loadMore();const gnext=group.c.requests.find(x=>x.req['@type']==='searchChatMessages'&&x.req.from_message_id===123);assert.ok(gnext);
gnext.resolve({messages:[{content:{'@type':'messageChatChangePhoto',photo:photo('b',40)}}],next_from_message_id:123});await tick();assert.equal(group.s.hasMore,false,'repeated cursor terminates');assert.equal(group.s.totalCount(),2);group.s.close();
const closed=model();closed.s.open();closed.s.close();closed.c.requests[0].resolve({photos:[photo('late',70)],total_count:1});await tick();assert.equal(closed.s.totalCount(),1);
// A failed page remains explicitly retryable; no background retry loop.
const fail=model();fail.s.open();fail.c.requests[0].reject(new Error('offline'));await tick();assert.equal(fail.s.error,true);fail.s.select(0);assert.equal(fail.c.requests.length,1);fail.s.retry();assert.equal(fail.c.requests.length,2);fail.s.close();
// Large history stays lazy: O(1) selection, max three image downloads and one current video.
const big=model();big.s.open();big.c.requests[0].resolve({photos:Array.from({length:1000},(_,i)=>photo('big'+i,100+i,100000+i)),total_count:1000});await tick();
assert.equal(big.s.totalCount(),1001);assert.equal(big.c.requests.filter(x=>x.req['@type']==='downloadFile').length,2);
const n=big.c.requests.length;big.s.select(500);assert.equal(big.c.requests.length-n,7);big.s.close();
console.log('PASS: avatar user/group pagination, current-photo identity, int64 keys, overlap dedup, bounded downloads, completed-only files, retry, stale completion and close isolation.');
// Replay real ArkUI compiler output for active-page playback and gesture routing.
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/';
function members(file,name,names){const a=ts.createSourceFile(file,fs.readFileSync(compiled+file+'.ts','utf8'),ts.ScriptTarget.Latest,true);
 const cls=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===name);
 return names.map(k=>cls.members.find(n=>n.name?.getText(a)===k).getText(a)).join('\n');}
const calls=[],players=[],pagerProps=[];
const enums=new Proxy({}, {get:(_,k)=>k});
for(const k of ['HitTestMode','Color','ImageFit','GestureMode','GesturePriority','PanDirection','Alignment','ButtonType','Curve','Axis','BarState','ScrollAlign'])ctx[k]=enums;
for(const k of ['Stack','Image','LoadingProgress','Button','Gesture','GestureGroup','TapGesture','PinchGesture','PanGesture','If','Row','Text','SymbolGlyph','Swiper','Column','List','ListItem','__Common__'])ctx[k]=new Proxy({}, {get:(_,method)=>(...args)=>calls.push([k,method,...args])});
ctx.$r=x=>x;ctx.ViewV2={create(){}};ctx.ViewPU={create(){}};
ctx.AvLoopVideo=class{constructor(_,props){players.push(props);}};
const ui={observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_,fn)=>fn()};
run(`class Cell {${members('common/AvatarViewerPage','AvatarViewerPage',['initialRender','videoSide','reset','onActiveChanged'])}}globalThis.Cell=Cell;`);
for(const active of [false,true])for(const foreground of [false,true]){
 const cell=new ctx.Cell();Object.assign(cell,ui,{photo:{imagePath:'/a.jpg',videoPath:'/a.mp4',thumbPath:''},active,foreground,boxWidth:400,boxHeight:800,zoom:1,x:0,y:0,onZoom(){},onClose(){}});
 players.length=calls.length=0;cell.initialRender();assert.equal(players.length,active?1:0);
 if(active){assert.equal(players[0].paused,!foreground);assert.equal(players[0].muted,true);assert.equal(players[0].loop,true);assert.equal(players[0].boxHeight,400);}
 assert.equal(calls.find(x=>x[0]==='PanGesture'&&x[1]==='create')[2].direction,'Vertical','at 1x horizontal drag must reach pager');
 cell.zoom=2;calls.length=0;cell.initialRender();assert.equal(calls.find(x=>x[0]==='PanGesture'&&x[1]==='create')[2].direction,'All');
 cell.onActiveChanged();assert.equal(cell.zoom,1);assert.equal(cell.x,0);
}
ctx.AvatarFilmstripCell=class{constructor(_,props){}};
ctx.AvatarViewerPage=class{constructor(_,props){pagerProps.push(props);}};
ctx.LazyForEach={create:(_id,_owner,source,build)=>{for(let i=0;i<source.totalCount();i++)build(source.getData(i),i);},pop(){}};
ctx.TransitionEffect={scale:()=>({combine(){return this;},animation(){return this;}}),OPACITY:0};
run(`class Viewer {${members('common/AvatarViewer','AvatarViewer',['initialRender','openTransition','selectPhoto','centerFilmstrip','filmstrip'])}}globalThis.Viewer=Viewer;`);
const viewer=new ctx.Viewer();let selected=-1;
Object.assign(viewer,ui,{ready:true,source:{totalCount:()=>2,getData:i=>({index:i,key:'k'+i}),ensureThumbnail(){},select:i=>{selected=i;}},
 filmScroller:{scrollToIndex(){}},index:0,count:2,zoomed:false,viewportWidth:400,viewportHeight:800,saving:false,loading:false,hasMore:false,topSafe:24,bottomSafe:24});
calls.length=0;viewer.initialRender();assert.equal(pagerProps.length,2);assert.equal(pagerProps[0].active,true);assert.equal(pagerProps[1].active,false);
assert.equal(calls.find(x=>x[0]==='Swiper'&&x[1]==='loop')[2],false);assert.equal(calls.find(x=>x[0]==='Swiper'&&x[1]==='cachedCount')[2],1);
viewer.zoomed=true;calls.find(x=>x[0]==='Swiper'&&x[1]==='onChange')[2](1);assert.equal(selected,1);assert.equal(viewer.zoomed,false);
for(const page of ['ProfilePage','ChatProfilePage']){
 run(`globalThis.Back=class {${members('profile/'+page,page,['goBack'])}};`);
 const b=new ctx.Back();let popped=0;b.navStack={pop:()=>popped++};b.viewerAvatarPath='/current';b.goBack();assert.equal(popped,0);assert.equal(b.viewerAvatarPath,'');b.goBack();assert.equal(popped,1);
 const file=compiled+'profile/'+page+'.ts',a=ts.createSourceFile(file,fs.readFileSync(file,'utf8'),ts.ScriptTarget.Latest,true);let callback;
 function find(n){if(ts.isCallExpression(n)&&n.expression.getText(a).endsWith('.onBackPressed')&&n.arguments[0]?.getText(a).includes('viewerAvatarPath'))callback=n.arguments[0].getText(a);ts.forEachChild(n,find);}find(a);
 assert.ok(callback);ctx.collapseFloatingVideo=()=>false;run(`globalThis.back=function(){return (${callback})();};`);
 const host={viewerAvatarPath:'/current'};assert.equal(ctx.back.call(host),true);assert.equal(host.viewerAvatarPath,'');assert.equal(ctx.back.call(host),false);
}
console.log('PASS: compiled current-page-only muted loop, background pause, horizontal paging vs zoom/pan, lazy pager selection and profile/system back priority.');

// Filmstrip downloads only requested low-resolution files; it never warms
// large images/videos for every historical item or leaks a failed thumb into
// the selected full-image error state.
const thumbs=model();thumbs.s.open();
thumbs.c.requests[0].resolve({photos:Array.from({length:30},(_,i)=>photo('strip'+i,200+i,2000+i)),total_count:30});await tick();
const t=thumbs.s.getData(15), key=t.key, tn=thumbs.c.requests.length;
thumbs.s.ensureThumbnail(15);thumbs.s.ensureThumbnail(15);
assert.equal(thumbs.c.requests.length,tn+1);assert.equal(thumbs.c.requests.at(-1).req.file_id,t.thumbId);
assert.ok(!thumbs.c.requests.some(r=>r.req.file_id===t.imageId||r.req.file_id===t.videoId));
thumbs.c.emit(file(t.thumbId,'/partial-small',false));assert.equal(t.thumbPath,'');
thumbs.c.emit(file(t.thumbId,'/small.jpg'));assert.equal(t.thumbPath,'/small.jpg');assert.equal(t.imagePath,'');assert.equal(t.key,key);
thumbs.s.ensureThumbnail(16);thumbs.c.requests.at(-1).reject(Error('thumb failure'));await tick();
assert.equal(thumbs.s.getData(16).downloadFailed,false);assert.equal(thumbs.s.getData(16).thumbFailed,true);
const failedCount=thumbs.c.requests.length;thumbs.s.ensureThumbnail(16);assert.equal(thumbs.c.requests.length,failedCount,'no mount retry loop');
thumbs.s.close();thumbs.s.ensureThumbnail(17);assert.equal(thumbs.c.requests.length,failedCount);
// Both navigation sources select the same lazy page and center the filmstrip.
const center=[];viewer.filmScroller={scrollToIndex:(...a)=>center.push(a)};
viewer.selectPhoto(0);assert.equal(viewer.index,0);assert.equal(selected,0);assert.equal(center.at(-1)[0],0);
const beforeInvalid=center.length;viewer.selectPhoto(90);assert.equal(center.length,beforeInvalid);
// Pending full image retains its available preview, with no player off-page.
const preview=new ctx.Cell();Object.assign(preview,ui,{photo:{imagePath:'',thumbPath:'/small.jpg',videoPath:'',downloadFailed:false},active:true,foreground:true,boxWidth:400,boxHeight:800,zoom:1,x:0,y:0});
calls.length=0;preview.initialRender();assert.ok(calls.some(c=>c[0]==='Image'&&c[1]==='create'&&c[2]==='file:///small.jpg'));
console.log('PASS: lazy filmstrip thumbnail requests, completed-only preview, failure isolation, stable keys, navigation and small-to-full fallback.');
// Render the actual cell, not a text-source snapshot: preview identity, current
// outline, animated marker and mount-time load all use the same photo object.
run(`class Film {${members('common/AvatarFilmstripCell','AvatarFilmstripCell',['initialRender','preview','aboutToAppear'])}}globalThis.Film=Film;`);
const film=new ctx.Film();let warmed=0;
Object.assign(film,ui,{photo:{thumbPath:'/small',imagePath:'/full',videoId:9,videoPath:''},current:true,onLoad:()=>warmed++});
film.aboutToAppear();assert.equal(warmed,1);calls.length=0;film.initialRender();
assert.ok(calls.some(c=>c[0]==='Image'&&c[1]==='create'&&c[2]==='file:///small'));
assert.ok(calls.some(c=>c[0]==='Stack'&&c[1]==='border'&&c[2].width===2));
film.photo.thumbPath='';assert.equal(film.preview(),'file:///full');
film.photo.imagePath='';film.current=false;calls.length=0;film.initialRender();
assert.ok(!calls.some(c=>c[0]==='Image'&&c[1]==='create'));
console.log('PASS: compiled filmstrip cell preview priority, selected border, loading ownership and empty placeholder.');

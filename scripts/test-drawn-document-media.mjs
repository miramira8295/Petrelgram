import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const created=[],children=[],clicks=[],glyphs=[],buttonLabels=[];let next=0;
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}static create(child){children.push(child);}}
class Child {constructor(_parent,params){this.params=params;}}
class Control {bind(...args){glyphs.push(args[5]);return this;}}
const ctx=vm.createContext({ViewV2:View,ViewPU:class{},DrawnMediaControl:Control,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},ImageFit:{Cover:1},HitTestMode:{None:0},str:k=>k,documentFileId:f=>f?.id??0,documentEmbedUrl:url=>url.startsWith('https://'),CachedImage:Child,DrawnDocumentPlayback:Child,LiveProgressRing:Child,DrawnLoadingSpinner:Child,DrawnMediaPlaceholder:Child});
for(const name of ['ViewStackProcessor','Row','Stack','Button','If','__Common__','Image','Text','SymbolGlyph','LoadingProgress'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k.startsWith('create')){created.push(name);if(name==='Button'&&typeof args[0]==='string')buttonLabels.push(args[0]);}if(k==='onClick')clicks.push(args[0]);}});
function load(path,names){const source=fs.readFileSync(root+path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('util/cachedImageSpec.ts',['CachedImageSpecCache']);
for(const name of ['DrawnDocumentArticleImage','DrawnDocumentMediaIsland','DrawnDocumentVideo','DrawnDocumentEmbed','DrawnDocumentMap','DrawnDocumentVoice'])load('pages/chat/'+name+'.ts',[name]);
function row(name,extra){return Object.assign(Object.create(ctx[name].prototype),{boxWidth:240,boxHeight:160,env:ctx.chatEnv,getUIContext:()=>({}),specs:new ctx.CachedImageSpecCache(),observeComponentCreation2:fn=>fn(++next,true),ifElseBranchUpdateFunction:(_i,fn)=>fn(),...extra});}
function render(r){created.length=0;children.length=0;clicks.length=0;glyphs.length=0;r.initialRender();for(const node of ['Image','Text','SymbolGlyph','LoadingProgress'])assert.equal(created.includes(node),false,`${r.constructor.name} must not recreate static native ${node}`);}
let opened=0;
const media=row('DrawnDocumentMediaIsland',{media:{key:'m1',kind:'photo',file:{id:1},thumbnail:{id:2}},path:'/a',failed:false,pageActive:true,control:new Control(),onOpen:()=>opened++});
const spec=media.imageSpec;assert.equal(spec.drawOnCanvas,true);for(let i=0;i<1000;i++)assert.equal(media.imageSpec,spec);
render(media);assert.equal(children[0].params.spec,spec);clicks[0]();assert.equal(opened,1);
media.media={...media.media,key:'m2',file:{id:3}};assert.notEqual(media.imageSpec.sourceKey,spec.sourceKey);
media.path='';media.failed=true;render(media);assert.deepEqual(glyphs,['retry']);
media.media={...media.media,kind:'video'};media.failed=false;render(media);assert.deepEqual(glyphs,['play']);assert.ok(children.some(c=>c.params.posterPath===''));
const article=row('DrawnDocumentArticleImage',{widget:{key:'a1',avatar:{id:1},avatarMini:'mini'},path:''});
const mini=article.imageSpec;assert.equal(mini.path,'mini');assert.equal(mini.drawOnCanvas,true);render(article);assert.equal(children[0].params.spec,mini);
article.path='/full';assert.notEqual(article.imageSpec,mini);article.widget={...article.widget,avatar:{id:5}};assert.notEqual(article.imageSpec.sourceKey,mini.sourceKey);
let starts=0;const video=row('DrawnDocumentVideo',{widget:{key:'video',url:'https://cdn/a.mp4'},playing:false,fallback:false,playPainter:new Control(),start:()=>starts++});
render(video);assert.deepEqual(glyphs,['play']);assert.equal(created.filter(n=>n==='Button').length,1);clicks[0]();assert.equal(starts,1);
let external=[];const embed=row('DrawnDocumentEmbed',{widget:{key:'embed',url:'https://example.test'},ready:false,loaded:false,failed:true,onClaim:()=>true,onOpen:url=>external.push(url)});
render(embed);assert.equal(children[0].params.primaryKey,'mb_web_link');clicks[0]();assert.deepEqual(external,['https://example.test']);
embed.onClaim=()=>false;clicks[0]();assert.equal(external.length,1);embed.failed=false;render(embed);assert.equal(children[0].params.ringSize,24);
const map=row('DrawnDocumentMap',{widget:{latitude:1,longitude:2,zoom:15},chatId:3,path:'/map',pin:new Control(),onOpen:()=>opened++});
const mapSpec=map.imageSpec;for(let i=0;i<1000;i++)assert.equal(map.imageSpec,mapSpec);render(map);assert.deepEqual(glyphs,['pin']);clicks[0]();assert.equal(opened,2);
map.widget={...map.widget,latitude:4};assert.notEqual(map.imageSpec.sourceKey,mapSpec.sourceKey);
console.log('PASS: compiled document photo/video/map/embed static Canvas routes, native playback/semantic actions, source identities, 1000 immutable specs and no native text/icon/image decorations.');

ctx.DrawnMediaTexts=class {prepare(_ui,_env,width,content){if(this.content!==content||this.width!==width){this.content=content;this.width=width;this.plan={width:Math.min(width,content.length*6),height:20,content};}return this.plan;}};
ctx.DrawnMediaTextPainter=class{bind(p){this.plan=p;return this;}};
ctx.VoiceBubble=Child;ctx.COLOR_PRIMARY='primary';
const voice=row('DrawnDocumentVoice',{widget:{key:'voice',file:{id:10},duration:12},boxWidth:240,visible:true,path:'',loading:false,failed:false,labels:new ctx.DrawnMediaTexts(),labelPainter:new ctx.DrawnMediaTextPainter(),buttonPainter:{bind(_ui,spec){this.spec=spec;return this;}},paintEnv:ctx.chatEnv,onClaim:()=>true});
let requested=0;voice.request=()=>requested++;
const voicePlan=voice.labelPlan;for(let i=0;i<1000;i++)assert.equal(voice.labelPlan,voicePlan);
render(voice);assert.equal(voice.buttonPainter.spec.background,'primary');assert.ok(voice.buttonPainter.spec.width<=voice.boxWidth);assert.ok(voice.buttonPainter.spec.height<=64);assert.equal(created.filter(n=>n==='Button').length,1);assert.equal(buttonLabels.length,0,'voice action label must be drawn, not native Button text');clicks[0]();assert.equal(requested,1);
voice.failed=true;assert.equal(voice.labelPlan.content,'live_media_retry_now');render(voice);clicks[0]();assert.equal(requested,2);
voice.loading=true;render(voice);assert.ok(children.some(c=>c.params.fileId===10));
voice.loading=false;voice.path='/voice';render(voice);const playable=children.find(c=>c.params.voicePath==='/voice');assert.ok(playable);assert.equal(playable.params.allowTranscription,false);
console.log('PASS: embedded voice Canvas action label, stable cache, retry/loading/ready transitions and existing native playback host.');

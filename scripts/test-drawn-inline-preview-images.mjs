import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const created=[],children=[],watchers=[],requests=[];let offCount=0,next=0;
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}static create(c){children.push(c);}}
class Child {constructor(_parent,params){this.params=params;}}
class Placeholder {bind(...args){this.args=args;return this;}}
const ctx=vm.createContext({ViewV2:View,ViewPU:class{},CachedImage:Child,LiveProgressRing:Child,DrawnMediaRetry:Child,DrawnInlineIconDecoration:Placeholder,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},ImageFit:{Contain:1,Cover:2},HitTestMode:{None:0},THUMBNAIL_PRIORITY:24,COLOR_PRIMARY:'primary',documentFileId:f=>f?.id??0,documentFileState:f=>({path:f.path??''}),watchDocumentFile:(file,fn)=>{watchers.push({file,fn});return()=>offCount++;},requestDocumentFile:(...args)=>requests.push(args),$r:key=>key});
for(const name of ['Stack','Row','If','Image','Text','SymbolGlyph'])ctx[name]=new Proxy({}, {get:(_t,k)=>(..._args)=>{if(k.startsWith('create'))created.push(name);}});
function load(file,names){const s=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('util/cachedImageSpec.ts',['CachedImageSpecCache']);
load('util/drawnInlineIcon.ts',['drawnInlineIcon','drawnInlineIconAnimated']);
load('pages/chat/DrawnInlineIconLayer.ts',['DrawnInlineIconImage']);load('pages/chat/DrawnPreviewImage.ts',['DrawnPreviewImage']);
function fixture(name,props){return Object.assign(Object.create(ctx[name].prototype),{specs:new ctx.CachedImageSpecCache(),getUIContext:()=>({}),observeComponentCreation2:fn=>fn(++next,true),ifElseBranchUpdateFunction:(_i,fn)=>fn(),...props});}
function render(row,animated=false){created.length=0;children.length=0;row.initialRender();for(const name of ['Image','Text','SymbolGlyph'])assert.equal(created.includes(name),animated&&name==='Image',`${row.constructor.name} has no raw ${name}`);}
const inline=fixture('DrawnInlineIconImage',{icon:{file:{id:1,path:'/same'},width:12,height:24},boxWidth:12,boxHeight:24,path:'',env:ctx.chatEnv,placeholder:new Placeholder(),generation:0,visible:false,off:null});
inline.aboutToAppear();assert.equal(requests.length,0,'offscreen icon must not start a download');render(inline);
let spec=children[0].params.spec;assert.equal(spec.fit,ctx.ImageFit.Contain);assert.equal(spec.opaque,false);assert.equal(spec.drawOnCanvas,true);for(let i=0;i<1000;i++)assert.equal(inline.imageSpec,spec);
inline.visible=true;inline.bind();assert.equal(requests.length,1);const a=watchers.at(-1);
inline.icon={file:{id:2,path:'/same'},width:12,height:24};inline.onIconChanged();const b=watchers.at(-1);assert.notEqual(inline.imageSpec.sourceKey,spec.sourceKey,'same path with another file clears old ownership');
a.fn({path:'/stale-A'});assert.equal(inline.path,'/same');b.fn({path:'/B'});assert.equal(inline.path,'/B');
inline.icon={file:{id:1},width:12,height:24};inline.onIconChanged();const currentA=watchers.at(-1);assert.equal(inline.path,'');a.fn({path:'/stale-A-again'});b.fn({path:'/stale-B'});assert.equal(inline.path,'');
render(inline);assert.equal(children.length,0);assert.ok(created.includes('Row'));
currentA.fn({path:'/current-A'});render(inline);assert.equal(children[0].params.spec.path,'/current-A');inline.aboutToDisappear();const count=requests.length;currentA.fn({path:'/detached'});assert.equal(inline.path,'/current-A');assert.ok(offCount>=3);assert.equal(requests.length,count);
inline.boxWidth=24;assert.equal(inline.imageSpec.boxWidth,24);
const preview=fixture('DrawnPreviewImage',{msg:{id:10,rowId:20,linkPhotoFileId:5,linkPhotoPath:'/same',linkPhotoFailed:false,linkPhotoProgress:40},plan:{previewImage:{width:140,height:90,x:4,y:20}}});
render(preview);spec=children[0].params.spec;assert.equal(spec.drawOnCanvas,true);assert.equal(spec.opaque,false);assert.equal(spec.fit,ctx.ImageFit.Cover);
for(let i=0;i<1000;i++){preview.msg={...preview.msg,linkPhotoProgress:i%100};assert.equal(preview.imageSpec,spec);}
preview.msg={...preview.msg,id:11,rowId:21};assert.notEqual(preview.imageSpec.sourceKey,spec.sourceKey);preview.msg={...preview.msg,linkPhotoFileId:6};assert.notEqual(preview.imageSpec.sourceKey,spec.sourceKey);
preview.plan={previewImage:{width:70,height:45,x:0,y:0}};assert.equal(preview.imageSpec.boxWidth,70);
preview.msg={...preview.msg,linkPhotoPath:'',linkPhotoFailed:true};render(preview);assert.equal(children[0].params.labelKey,'');assert.equal(children[0].params.foreground,'primary');
preview.msg={...preview.msg,linkPhotoFailed:false};render(preview);assert.equal(children[0].params.fileId,6);assert.equal(children[0].params.ringSize,30);
console.log('PASS: compiled inline/preview Canvas image specs, 1000 stable/progress bindings, alpha and aspect fit, same-path file/row ownership, A/B/A and detached callbacks, offscreen request guard, placeholder/retry/progress routes.');

for(const document of [{mime_type:'image/gif'},{mime_type:'IMAGE/APNG'},{file_name:'animation.GIF'}]) {
 const icon=ctx.drawnInlineIcon({document:{...document,document:{id:8}},width:12,height:12});assert.equal(icon.animated,true);
 inline.icon=icon;inline.path='/extensionless';render(inline,true);assert.equal(children.length,0,'known animation retains native frame playback, never static CachedImage');
}
inline.icon=ctx.drawnInlineIcon({document:{mime_type:'image/png',document:{id:9}},width:12,height:12});inline.path='/static.png';render(inline);assert.equal(children[0].params.spec.drawOnCanvas,true);
inline.path='/local/file.apng';render(inline,true);assert.equal(ctx.drawnInlineIconAnimated(inline.icon,'/file.GIF?cached=1'),true);
assert.equal(ctx.drawnInlineIconAnimated(inline.icon,'/dir.gif/file.png'),false);
console.log('PASS: GIF/APNG document metadata and local animation paths keep native playback; static PNG still uses Canvas.');

import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,ui,shapes} from './test-drawn-media-text.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function load(path,names){const source=fs.readFileSync(root+path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
Object.assign(ctx,{ViewV2:class{},ViewPU:class{},COLOR_TEXT_PRIMARY:'primary',COLOR_TEXT_SECONDARY:'secondary',str:k=>k,formatVoiceDuration:n=>`${n}s`,formatFileSize:n=>`${n}B`,displayFileName:n=>n,fullDate:d=>d.toISOString(),documentFileId:f=>f?.id??0,ImageFit:{Cover:1}});
load('util/cachedImageSpec.ts',['CachedImageSpecCache']);
load('pages/chat/DrawnDocumentAudio.ts',['DrawnDocumentAudio']);
load('util/fileMessage.ts',[]);
load('util/filePreview.ts',[]);
load('pages/chat/DrawnFileCardLayout.ts',[]);
load('pages/chat/FileBubble.ts',['FileBubble']);
load('pages/chat/DrawnDocumentAudioCover.ts',['DrawnDocumentAudioCover']);
load('pages/chat/DrawnDocumentPostAuthor.ts',['DrawnDocumentPostAuthor']);
function instance(name,extra){return Object.assign(Object.create(ctx[name].prototype),{labels:new ctx.Layouts(),getUIContext:()=>ui,env:{appearanceEpoch:1,langEpoch:1},boxWidth:250,...extra});}
ctx.textMeasureEnvironment={epoch:1};
const audio=instance('DrawnDocumentAudio',{widget:{title:'article track',performer:'artist',duration:90},elapsed:0});
const plan=audio.labelPlan;assert.ok(shapes.get('article track')>0);const titleCount=shapes.get('article track');
for(let i=0;i<1000;i++){audio.elapsed=i;audio.progress=i/1000;audio.playing=i%2===0;audio.labelPlan;}
assert.equal(shapes.get('article track'),titleCount,'clock cannot reshape audio title');
audio.widget={title:'reused track',performer:'next',duration:5};assert.notEqual(audio.labelPlan.primary,plan.primary);assert.ok(shapes.get('reused track')>0);
const file=instance('FileBubble',{paintEnv:{appearanceEpoch:1,langEpoch:1},labelLayouts:new ctx.Layouts(),fileName:'article.pdf',mimeType:'application/pdf',fileSize:500,fileId:9,filePath:'',downloadFailed:false,downloadProgress:0,downloadActive:false,uploading:false,maxWidth:250,fitAvailableWidth:true,thumbnailId:0,mini:''});
const filePlan=file.labelPlan,fileTitleCount=shapes.get('article.pdf');
for(let i=0;i<1000;i++){file.downloadFailed=i%2===0;file.filePath=`/file-${i}`;file.downloadActive=i%3===0;file.labelPlan;}
assert.equal(shapes.get('article.pdf'),fileTitleCount,'status cannot reshape filename');assert.equal(filePlan.width,150);
const author=instance('DrawnDocumentPostAuthor',{widget:{key:'author',name:'Author',date:5,avatar:{id:1}},path:'/one',specs:new ctx.CachedImageSpecCache()});
const authorPlan=author.labelPlan,authorShapes=shapes.get('Author'),authorSpec=author.imageSpec;
for(let i=0;i<1000;i++){author.path=`/avatar-${i}`;assert.equal(author.labelPlan,authorPlan);}
assert.equal(shapes.get('Author'),authorShapes,'avatar completion cannot reshape author');assert.equal(authorSpec.radius,20);assert.equal(authorSpec.drawOnCanvas,true);
author.widget={...author.widget,avatar:{id:2}};assert.notEqual(author.imageSpec.sourceKey,authorSpec.sourceKey);
author.widget={key:'new',name:'No avatar',date:0};assert.equal(author.labelPlan.width,250);assert.equal(author.labelPlan.secondary,null);
const cover=instance('DrawnDocumentAudioCover',{fileId:7,coverPath:'',mini:'mini',specs:new ctx.CachedImageSpecCache()});
const spec=cover.imageSpec;for(let i=0;i<1000;i++)assert.equal(cover.imageSpec,spec);assert.equal(spec.drawOnCanvas,true);assert.equal(spec.radius,6);
cover.fileId=8;assert.notEqual(cover.imageSpec.sourceKey,spec.sourceKey);
console.log('PASS: compiled article audio/file/author paragraph caches, 1000 local updates, reuse reset and receiver ownership; no row layout feedback.');

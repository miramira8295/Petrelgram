import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,ui,shapes} from './test-drawn-media-text.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
Object.assign(ctx,{ViewV2:class{},ViewPU:class{},ImageFit:{Cover:1},COLOR_TEXT_PRIMARY:'primary',COLOR_TEXT_SECONDARY:'secondary',str:key=>key,textMeasureEnvironment:{epoch:1}});
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function load(path,names){const source=fs.readFileSync(root+path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('util/cachedImageSpec.ts',['CachedImageSpecCache']);load('pages/chat/PaidMediaBubble.ts',['PaidMediaBubble']);
const card=Object.assign(Object.create(ctx.PaidMediaBubble.prototype),{env:{appearanceEpoch:1,langEpoch:1},fitAvailableWidth:true,maxWidth:240,locked:false,mediaSet:null,prepared:null,caption:'compatibility caption',photoPath:'/poster',photoFileId:8,ownerKey:'chat:1',messageId:2,getUIContext:()=>ui,fallbackLabels:new ctx.Layouts(),fallbackNotes:new ctx.Layouts(),posterSpecs:new ctx.CachedImageSpecCache()});
const labels=card.fallbackText,note=card.fallbackNote,poster=card.posterSpec;
assert.equal(poster.drawOnCanvas,true);assert.equal(poster.boxWidth,240);assert.equal(poster.boxHeight,156);
const before=new Map(shapes);
for(let i=0;i<1000;i++){card.photoProgress=i%100;card.pending=i%2===0;card.starCount=i;assert.equal(card.fallbackText,labels);assert.equal(card.fallbackNote,note);assert.equal(card.posterSpec,poster);}
assert.deepEqual(shapes,before,'transfer/payment state cannot reshape compatibility text');
card.photoFileId=9;assert.notEqual(card.posterSpec.sourceKey,poster.sourceKey);card.ownerKey='chat:2';assert.notEqual(card.posterSpec.sourceKey,poster.sourceKey);
card.caption='reused caption';assert.notEqual(card.fallbackText.secondary,labels.secondary);card.caption='';assert.equal(card.fallbackText.secondary,null);
card.locked=true;assert.notEqual(card.fallbackText.primary,labels.primary);
console.log('PASS: paid compatibility labels/poster use retained Canvas inputs, 1000 transfer/payment updates without reshaping, caption reset and cross-owner source identity.');

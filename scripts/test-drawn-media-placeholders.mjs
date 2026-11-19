import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,ui,shapes,paints,styles} from './test-drawn-media-text.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const layouts=new ctx.Layouts();
const p=layouts.prepare(ui,'center',72,'👩‍👩‍👧‍👦',56,'primary','Complete localized fallback text '.repeat(5),12,'secondary',0,false,6,68,false,true,0);
assert.equal(styles.at(-1).align,ctx.text.TextAlign.CENTER);assert.equal(styles.at(-1).maxLines,undefined);assert.equal(styles.at(-2).maxLines,undefined,'fallback paragraphs keep complete text');
let transforms=0,saves=0;const scales=[];const painter=new ctx.Painter();
painter.bind(p,68);paints.length=0;painter.drawBehind({canvas:{save(){saves++;},restore(){saves--;},translate(){transforms++;},scale(x,y){assert.equal(x,y);scales.push(x);}}});
assert.equal(saves,0);assert.ok(scales[0]>0&&scales[0]<1);assert.equal(paints[0].content,'👩‍👩‍👧‍👦');assert.equal(paints[1].content,'Complete localized fallback text '.repeat(5));
const counts=new Map(shapes);for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,'center',72,'👩‍👩‍👧‍👦',56,'primary','Complete localized fallback text '.repeat(5),12,'secondary',0,false,6,68,false,true,0),p);assert.deepEqual(shapes,counts);
function load(path,names){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
ctx.ViewV2=class{};ctx.ViewPU=class{};ctx.ImageFit={Contain:1};
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
load(compiled+'util/cachedImageSpec.ts',['CachedImageSpecCache']);
load(compiled+'pages/chat/StickerMessageBubble.ts',['StickerMessageBubble']);
const sticker=Object.assign(Object.create(ctx.StickerMessageBubble.prototype),{imageSpecs:new ctx.CachedImageSpecCache(),data:{chatId:1},contentOnly:true,contentMax:160,msg:{rowId:2,stickerFileId:3,photoFileId:4,photoWidth:512,photoHeight:512,isEmojiSticker:false}});
const first=sticker.stickerImageSpec('/poster');assert.equal(first.drawOnCanvas,true);assert.equal(first.opaque,false);assert.equal(first.fit,1);
for(let i=0;i<1000;i++){sticker.livePhotoProgress=i%100;sticker.liveStickerProgress=i%100;assert.equal(sticker.stickerImageSpec('/poster'),first);}
sticker.data={chatId:99};assert.notEqual(sticker.stickerImageSpec('/poster').sourceKey,first.sourceKey);sticker.msg={...sticker.msg,stickerFileId:5};assert.notEqual(sticker.stickerImageSpec('/poster').sourceKey,first.sourceKey);
console.log('PASS: complete multiline/ZWJ placeholder text, reserved-box fit transform, 1000 cache hits, alpha-safe sticker poster receiver specs and chat/file identity.');

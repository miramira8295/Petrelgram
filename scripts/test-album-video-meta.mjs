// Run the production metadata method and real formatters against its pre-change
// implementation. This covers reuse, locale and width-boundary invalidation.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const read=p=>fs.readFileSync(p,'utf8');
const root='entry/src/main/ets/';
const source=read(root+'pages/chat/AlbumCellView.ets');
const baseline=process.env.ALBUM_META_BASELINE;
assert.ok(baseline,'Set ALBUM_META_BASELINE to pre-change AlbumCellView.ets');
const strip=s=>s.replace(/^import[^\n]*\n/gm,'').replace(/\bexport /g,'');
function method(s){const start=s.indexOf('  private videoMetaText(): string {');assert.ok(start>=0);const end=s.indexOf('\n  }',start);return s.slice(start,end+4);}
let locale='en-US',formats=0,epochReads=0;
const units={size_bytes:'B',size_kb:'KB',size_mb:'MB',size_gb:'GB'};
const context=vm.createContext({Intl,i18n:{System:{getAppPreferredLanguage:()=>locale}},
 chatEnv:{get langEpoch(){epochReads++;return epoch;}},
 str:(key,value)=>`${value} ${locale==='de-DE'?'DE-':''}${units[key]}`});
let epoch=0;
const helpers=strip(read(root+'util/intlFormat.ets'))+'\n'+strip(read(root+'util/formatFileSize.ets'))+'\n'+strip(read(root+'util/mediaDuration.ets'));
const fields=source.split('\n').filter(l=>/^  private meta\w+:/.test(l)).join('\n');
const code=helpers+`\nclass Before {${method(read(baseline))}}\nclass After {${fields}\n${method(source)}}
const originalFormat=formatFileSize;formatFileSize=function(b){__count();return originalFormat(b);};
globalThis.before=new Before();globalThis.after=new After();globalThis.localeChanged=refreshLocale;`;
context.__count=()=>formats++;
vm.runInContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
const {before,after}=context;
let cases=0,previousKey='';
for(const lang of ['en-US','de-DE','zh-CN']){
 locale=lang;epoch++;context.localeChanged();
 for(const videoFileSize of [0,1,1023,1024,1259520,3.4*1024**3])
 for(const videoDuration of [0,1,59,60,3661])
 for(const width of [111.9,112,112.1]){
  const cell={videoFileSize,videoDuration,width,isVideo:true};before.cell=cell;after.cell=cell;
  const expected=before.videoMetaText();const start=formats;
  const key=JSON.stringify([videoFileSize,videoDuration,width>=112,epoch]);
  assert.equal(after.videoMetaText(),expected);const cold=formats-start;
  assert.equal(cold,videoFileSize>0&&key!==previousKey?1:0);
  previousKey=key;
  const reads=epochReads;
  for(let i=0;i<8;i++)assert.equal(after.videoMetaText(),expected);
  assert.equal(formats-start,cold);assert.equal(epochReads-reads,8);
  cases++;
 }
}
// Mutate the same object as download metadata and layout evolve; no identity key.
const cell={videoFileSize:12000,videoDuration:61,width:111.9,isVideo:true};before.cell=cell;after.cell=cell;
for(const change of [()=>{},()=>cell.width=112,()=>cell.videoDuration=0,()=>cell.videoFileSize=0,
 ()=>cell.isVideo=false,()=>{cell.isVideo=true;cell.videoDuration=120;cell.videoFileSize=125000;},
 ()=>{locale='de-DE';epoch++;context.localeChanged();}]){
 change();assert.equal(after.videoMetaText(),before.videoMetaText());cases++;
}
// Same width band does not reformat; changing locale with identical inputs does.
after.videoMetaText();let start=formats;cell.width=112.1;after.videoMetaText();assert.equal(formats,start);
locale='en-US';epoch++;context.localeChanged();start=formats;
assert.equal(after.videoMetaText(),before.videoMetaText());assert.equal(formats-start,2);
assert.match(source,/if \(this\.isVideo\(\) && this\.videoMetaText\(\) !== ''\)/);
console.log(`Album metadata: ${cases} exact old/new results; 8 stable reads per case do not format; width band, locale, mutable cell and photo guard passed`);

// Replay actual source builders with native UI doubles, not a duplicated renderer.
// This checks submitted filters/geometry/opacity; device pixel quality is separate.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const read=path=>fs.readFileSync(root+path+'.ets','utf8');
function closeBrace(source,start){
 let level=1,quote='',line=false,block=false;
 for(let i=start+1;i<source.length;i++){
  const c=source[i],next=source[i+1];
  if(line){if(c==='\n')line=false;continue;}
  if(block){if(c==='*'&&next==='/'){block=false;i++;}continue;}
  if(quote){if(c==='\\')i++;else if(c===quote)quote='';continue;}
  if(c==='/'&&next==='/'){line=true;i++;continue;}
  if(c==='/'&&next==='*'){block=true;i++;continue;}
  if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
  if(c==='{')level++;else if(c==='}'&&--level===0)return i;
 }
 throw Error('Unclosed UI builder');
}
function lowerBuilders(source){
 const edits=[];
 for(const match of source.matchAll(/\b(Stack|Column|Row)\(\)\s*\{/g)){
  const open=match.index+match[0].lastIndexOf('{'),close=closeBrace(source,open);
  edits.push({start:match.index,end:open+1,value:match[1]+'(() => {'},{start:close+1,end:close+1,value:')'});
 }
 edits.sort((a,b)=>b.start-a.start);
 for(const e of edits)source=source.slice(0,e.start)+e.value+source.slice(e.end);
 return source.replace(/@Builder\s*/g,'');
}
const nodes=[];
function component(kind){return (...args)=>{
 const node={kind,args:args.filter(x=>typeof x!=='function'),props:{}};nodes.push(node);
 for(const arg of args)if(typeof arg==='function')arg();
 const chain=new Proxy({}, {get:(_,key)=>(...values)=>{node.props[key]=values;return chain;}});return chain;
};}
let tests=0;
const context=vm.createContext({Stack:component('Stack'),Column:component('Column'),Row:component('Row'),Image:component('Image'),
 ForEach:(items,body)=>items.forEach(body),ImageFit:{Cover:'cover'},ImageInterpolation:{High:'high'},Color:{Black:'black'},$r:x=>x,
 gradientStops:colors=>colors.map((c,i)=>[c,i]),
 describe:(_name,fn)=>fn(),it:(_name,_flags,fn)=>{fn();tests++;},
 expect:value=>({assertEqual:expected=>assert.equal(value,expected),assertTrue:()=>assert.equal(value,true),assertFalse:()=>assert.equal(value,false)})});
function run(source,filename='production'){
 source=source.replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport default /g,'').replace(/\bexport /g,'');
 const result=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020},reportDiagnostics:true});
 assert.equal((result.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error).length,0,filename+' syntax');
 vm.runInContext(result.outputText,context,{filename});
}
const raster=read('util/chatBackgroundRaster');
run(lowerBuilders(raster)+'\nglobalThis.render=backgroundLayer;globalThis.tiles=patternTileGridLayer;globalThis.grid=patternTileGrid;globalThis.signature=rasterSignature;globalThis.diskPath=rasterPathFor;');
assert.equal(context.tiles.length,3,'tile builder no longer accepts a blur radius');
for(const name of ['backgroundBlurRadius','backgroundOverscan','shouldOverscan','wallpaperTakesBlur','NO_BLUR_RADIUS','BLUR_OVERSCAN_SCALE'])assert.doesNotMatch(raster,new RegExp('\\b'+name+'\\b'));
const source={colors:['#102030','#506070'],angle:45,path:'/cache/wall.png',isPattern:false,imageOpacity:.4,dimming:.3,width:360,height:800};
for(const isPattern of [false,true])for(const path of ['',source.path])for(const dimming of [0,.3])for(const colors of [[],source.colors]){
 nodes.length=0;const p={...source,isPattern,path,dimming,colors};context.render(p);
 for(const n of nodes)for(const key of ['blur','backdropBlur','backgroundBlurStyle','scale'])assert.equal(n.props[key],undefined,`${n.kind} must not submit ${key}`);
 const images=nodes.filter(n=>n.kind==='Image'),masks=nodes.filter(n=>n.kind==='Column'&&n.props.backgroundColor?.[0]==='black');
 const grid=context.grid(p.width,p.height);
 assert.equal(images.length,path?(isPattern?grid.rows*grid.cols:1):0);
 assert.equal(masks.length,dimming>0?1:0);if(masks.length)assert.equal(masks[0].props.opacity[0],dimming);
 const fill=nodes.find(n=>n.kind==='Column');assert.ok(colors.length?fill.props.linearGradient:fill.props.backgroundColor);
 for(const img of images){assert.equal(img.args[0],'file://'+path);assert.equal(img.props.autoResize[0],false);assert.equal(img.props.syncLoad[0],true);assert.equal(img.props.interpolation[0],'high');}
 if(path){const texture=isPattern?nodes.find(n=>n.kind==='Column'&&n.props.opacity):images[0];assert.equal(texture.props.opacity[0],p.imageOpacity);}
 assert.equal(nodes.find(n=>n.kind==='Stack').props.clip[0],true);
}
const sharp=context.signature(source);
const legacy=`v7_${source.colors.join('-')}_${source.angle}_${source.path}_w_40_dim3000_blur8_360x800`;
assert.notEqual(context.diskPath(sharp,'/cache'),context.diskPath(legacy,'/cache'),'sharp and already-baked blurred files cannot share disk path');
assert.equal(context.signature({...source,blurred:true,userBlur:20}),sharp,'legacy account/settings fields cannot affect rendering identity');
const patternView=read('pages/chat/PatternTileLayer');
assert.doesNotMatch(patternView,/\.\s*(?:blur|backdropBlur|backgroundBlurStyle|scale)\s*\(/,'live pattern previews must not submit filters or overscan');
// Run the real Hypium suites with only the expectation transport substituted.
run(fs.readFileSync('entry/src/test/BackgroundRaster.test.ets','utf8')+'\nbackgroundRasterTest();','BackgroundRaster.test.ets');
const app=read('store/AppSettings'),ast=ts.createSourceFile('AppSettings.ets',app,ts.ScriptTarget.Latest,true);
const settings=ast.statements.filter(n=>ts.isVariableStatement(n)&&n.declarationList.declarations.some(d=>/^KEY_|^WALLPAPER_NUMBER_SETTINGS$|^BG_PATTERN_DEFAULT$/.test(d.name.getText(ast))));
run(settings.map(n=>n.getText(ast)).join('\n'));
run(read('util/wallpaperSlot'));
run(fs.readFileSync('entry/src/test/WallpaperSlot.test.ets','utf8')+'\nwallpaperSlotTest();','WallpaperSlot.test.ets');
assert.equal(tests,16,'9 raster cases and 7 retained slot cases');
console.log('PASS: 16 real Hypium cases, 16 source-builder rendering combinations without blur/overscan, tiled/photo fidelity, retained masks/intensity, sharp disk namespace and ignored legacy blur values.');

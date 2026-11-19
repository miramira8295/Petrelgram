// Exercise real palette/settings helpers and the real Hypium suite with host storage.
// Native blur is forbidden on the card chains; popup menu materials are unrelated.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const read=path=>fs.readFileSync(root+path+'.ets','utf8');
const stored=new Map([['surfaceGlassOn',true],['bubbleGlassOn',false],['surfaceGlassLevel',-1],['bubbleGlassLevel',2],['appIsDark',true],['surfaceGlassEpoch',88]]);
const original=[...stored];let tests=0;
const context=vm.createContext({
 AppStorage:{get:key=>stored.get(key),setOrCreate:(key,value)=>stored.set(key,value),delete:key=>stored.delete(key)},
 $r:name=>({id:100,type:10001,bundleName:'',moduleName:'',params:[name]}),
 describe:(_name,fn)=>fn(),it:(_name,_flags,fn)=>{fn();tests++;assert.deepEqual([...stored].sort(),[...original].sort(),'test must restore shared settings');},
 expect:value=>({assertEqual:expected=>assert.equal(value,expected),assertTrue:()=>assert.equal(value,true),assertFalse:()=>assert.equal(value,false)})
});
function run(source,name){
 source=source.replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport default /g,'').replace(/\bexport /g,'');
 const result=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020},reportDiagnostics:true});
 assert.equal((result.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error).length,0,name+' syntax');
 vm.runInContext(result.outputText,context,{filename:name});
}
run(read('util/materialTuning'),'materialTuning');
const theme=read('util/theme'),themeAst=ts.createSourceFile('theme.ets',theme,ts.ScriptTarget.Latest,true);
run(themeAst.statements.find(n=>ts.isVariableStatement(n)&&n.declarationList.declarations.some(d=>d.name.getText(themeAst)==='KEY_APP_DARK')).getText(themeAst),'theme dark key');
const appearance=read('util/appearance'),appearanceAst=ts.createSourceFile('appearance.ets',appearance,ts.ScriptTarget.Latest,true);
run(appearanceAst.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name.text==='appIsDark').getText(appearanceAst),'appIsDark');
const surface=read('util/surfaceGlass');run(surface,'surfaceGlass');
run(fs.readFileSync('entry/src/test/SurfaceGlass.test.ets','utf8')+'\nsurfaceGlassTest();','SurfaceGlass.test.ets');
assert.equal(tests,10);
assert.doesNotMatch(surface,/\b(?:surfaceGlassBlurStyle|surfaceGlassScrim|surfaceGlassVeilOnly|glassBlurStyleFor|bubbleGlassBlurStyle|BlurStyle)\b/);
assert.doesNotMatch(surface,/from\s+['"][^'"]*(?:overlayMaterial|materialModifier)['"]/);
const cards=['pages/chatlist/ChatRow','pages/chatlist/MainTabBody','pages/profile/ChatProfilePage','pages/profile/ProfilePage','pages/main/ContactsPage','pages/main/MyProfilePage','pages/main/SettingsPage'];
for(const path of cards){
 const source=read(path);assert.match(source,/surfaceGlassFill\(/,path+' must use the shared tint');
 assert.doesNotMatch(source,/\.\s*(?:backgroundBlurStyle|backdropBlur|blur)\s*\(/,path+' card chains must not mount blur');
 assert.doesNotMatch(source,/materialModifier(?:When)?\s*\(\s*['"]card['"]/,path+' cards must not layer another system material over the tint');
}
// Execute the actual adjustments builder with the real slot policy. No page is
// constructed: the component DSL's Column block is lowered to a callback only.
function closingBrace(source,open){
 const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,source);scanner.setTextPos(open);
 let depth=0;
 for(let token=scanner.scan();token!==ts.SyntaxKind.EndOfFileToken;token=scanner.scan()){
  if(token===ts.SyntaxKind.OpenBraceToken)depth++;
  else if(token===ts.SyntaxKind.CloseBraceToken&&--depth===0)return scanner.getTokenPos();
 }
 throw Error('Unclosed production method');
}
function member(source,name){
 const match=new RegExp('^  (?:private )?'+name+'\\([^\\n]*','m').exec(source);assert.ok(match,name);
 const open=source.indexOf('{',match.index);return source.slice(match.index,closingBrace(source,open)+1);
}
const backgroundPage=read('pages/main/ChatBackgroundPage');
let adjustment=member(backgroundPage,'adjustmentsCard');
const column=adjustment.indexOf('Column() {'),open=adjustment.indexOf('{',column),close=closingBrace(adjustment,open);
adjustment=adjustment.slice(0,close+1)+')'+adjustment.slice(close+1);
adjustment=adjustment.replace('Column() {','Column(() => {');
let patterns=0,masks=0,dividers=0;
const chain=new Proxy({}, {get:()=>()=>chain});
context.Column=callback=>{callback();return chain;};context.Divider=()=>{dividers++;return chain;};
context.COLOR_SURFACE='#ffffff';context.CARD_RADIUS=17;
run(read('util/wallpaperSlot'),'wallpaper slot policy');
run(`class AdjustmentProbe {${member(backgroundPage,'effectiveSlot')}\n${adjustment}}
globalThis.AdjustmentProbe=AdjustmentProbe;`,'adjustmentsCard production');
const rasterSource=read('util/chatBackgroundRaster'),rasterAst=ts.createSourceFile('raster.ets',rasterSource,ts.ScriptTarget.Latest,true);
run(rasterAst.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name.text==='wallpaperTakesUserDim').getText(rasterAst),'wallpaper dim eligibility');
const settings=read('store/AppSettings'),settingsAst=ts.createSourceFile('AppSettings.ets',settings,ts.ScriptTarget.Latest,true);
run(settingsAst.statements.find(n=>ts.isVariableStatement(n)&&n.declarationList.declarations.some(d=>d.name.getText(settingsAst)==='CHAT_DIM_MAX')).getText(settingsAst),'dim limit');
run(`class PreviewProbe {${member(read('pages/main/WallpaperPreview'),'darkDim')}}
globalThis.PreviewProbe=PreviewProbe;`,'WallpaperPreview production');
for(const slot of ['appLight','chatLight','appDark','chatDark']){
 const dark=slot.endsWith('Dark');
 const probe=new context.AdjustmentProbe();probe.slotId=slot;probe.forDark=dark;
 probe.patternAdjustment=()=>patterns++;probe.dimAdjustment=()=>masks++;
 patterns=0;masks=0;dividers=0;probe.adjustmentsCard();
 assert.equal(patterns,1,slot+' retains texture control');assert.equal(masks,dark?1:0,slot+' dim control');
 assert.equal(dividers,dark?1:0,slot+' dim divider must disappear with its control');
 const preview=new context.PreviewProbe();preview.dark=dark;preview.dimAmount=.3;
 for(const wallpaper of [{colors:[],path:'/photo.jpg'},{colors:['#111111','#222222'],path:''}]){
  preview.wallpaper=wallpaper;assert.equal(preview.darkDim(),dark ? 0.3 : 0,slot+' preview ignores persisted dim for light slots');
 }
 preview.wallpaper={colors:['#111111'],path:''};assert.equal(preview.darkDim(),0,slot+' solid stays free of user mask');
}
console.log('PASS: 10 real Hypium cases, same-RGBA palettes, independent settings, invalid values, seven filter-free card surfaces; real adjustments builder creates dim/divider only for dark slots, and all four preview slots preserve dim eligibility.');

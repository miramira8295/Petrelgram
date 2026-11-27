// Execute production settings and compiled UI policies across opt-in/restart transitions.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const storage = new Map([['materialThickness', 2], ['edgeBlurChatTop', 'on'], ['edgeBlurChatBottom', 'on'], ['surfaceGlassOn',true], ['bubbleGlassLevel',1]]);
const disk = new Map();
const calls = [];
const ctx = vm.createContext({
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  persist: (key, value) => disk.set(key, value), bumpMaterialEpoch:()=>{}, recomputeAppearance:()=>{}, mirrorChatEnvKey: () => {},
  KEY_DEBUG_DRAWN_TRACE: 'debug', KEY_HIDE_PINNED_DEFAULT: 'pinned', KEY_EDGE_BLUR_ON: 'edge',
  KEY_EDGE_BLUR_TOP_ON: 'top', KEY_EDGE_BLUR_BOTTOM_ON: 'bottom', KEY_CRASH_UPLOAD: 'crash', KEY_VIDEO_AUTO_PRELOAD: 'preload',
  immersiveMaterialAvailable: () => true
});
function run(source) {
  source = source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
function declaration(file, name) {
  const source = fs.readFileSync(file, 'utf8'), ast = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
  return ast.statements.find(n => ts.isFunctionDeclaration(n) && n.name.text === name).getText(ast);
}
function method(file, name, directory = 'chat') {
  const path = compiled + 'pages/' + directory + '/' + file + '.ts';
  const source = fs.readFileSync(path, 'utf8'), ast = ts.createSourceFile(path, source, ts.ScriptTarget.Latest, true);
  return ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === file).members.find(n => n.name?.getText(ast) === name).getText(ast);
}
run(fs.readFileSync(root + 'util/materialTuning.ets', 'utf8'));
run(fs.readFileSync(root + 'util/systemMaterialSetting.ets', 'utf8'));
run('globalThis.state = systemMaterialState; globalThis.key = KEY_SYSTEM_MATERIAL;');
assert.equal(ctx.state.level,-4);assert.equal(ctx.state.chatEnabled,false,'App default retains plain chat chrome');
run(declaration(root + 'store/AppSettings.ets', 'setSystemMaterialLevel'));
run(declaration(root + 'util/overlayMaterial.ets', 'thicknessOffset'));
run(declaration(root + 'util/overlayMaterial.ets', 'materialOff'));
run(fs.readFileSync(root + 'util/edgeBlurSetting.ets', 'utf8'));
run('globalThis.edges = edgeBlurSwitch;');
Object.assign(ctx.edges, {master:true, top:true, bottom:true, chatTop:'on', chatBottom:'on'});
run(`class Timeline {${['edgeBlurTopEnabled','edgeBlurBottomEnabled'].map(n => method('ChatTimelineHost', n)).join('\n')}} globalThis.timeline = new Timeline();`);
run(`class Composer {${method('ChatComposerInput', 'glassHostOn')}} globalThis.composer = new Composer();`);
const chain = new Proxy({}, {get: (_target, name) => (...args) => calls.push([name, ...args])});
Object.assign(ctx, {Stack:chain, Row:chain, Column:chain, Text:chain, ViewV2:{create(){}},
  HitTestMode:{None:0}, Alignment:{Start:0,Center:1,TopStart:2}, FlexAlign:{Center:0}, FontWeight:{Medium:0}, COLOR_TEXT_PRIMARY:'ink',
  $r:x=>x, SystemGlassSurface:class {constructor(_owner, props){calls.push(['surface',props]);}}});
run(`class DateOverlay {${method('FloatingDateOverlay', 'initialRender')}} globalThis.dateOverlay = new DateOverlay();`);
Object.assign(ctx.dateOverlay, {state:{shown:true,label:'date'}, observeComponentCreation2:cb=>cb(1,true),ifElseBranchUpdateFunction:(_id,cb)=>cb()});
for(const level of [-4,-3,-2,-1,0,1,2,-4,0]) {
  const enabled=level>=-2;
  ctx.setSystemMaterialLevel(level);
  assert.equal(ctx.state.level,level);assert.equal(ctx.state.chatEnabled,enabled);
  assert.equal(storage.get(ctx.key),level);assert.equal(disk.get(ctx.key),level);
  assert.equal(ctx.systemMaterialThickness(),level===-4?0:level);
  assert.equal(ctx.materialOff(),level===-3);
  assert.equal(ctx.systemMaterialOff(level),level===-3);
  assert.equal(ctx.chatPlainFill(level),level===-3?'app.color.surface':'app.color.chat_overlay');
  for(const dark of [false,true]) {
    storage.set('appIsDark',dark);
    assert.equal(ctx.systemMaterialThickness(),level===-4?0:level,'both color modes share the selection');
  }
  for (const [global, override, expected] of [
    [true, 'follow', true], [false, 'follow', false],
    [true, 'off', false], [false, 'on', true]
  ]) {
    Object.assign(ctx.edges, { master: true, top: global, bottom: !global, chatTop: override, chatBottom: 'follow' });
    assert.equal(ctx.timeline.edgeBlurTopEnabled(), expected);
    assert.equal(ctx.timeline.edgeBlurBottomEnabled(), !global);
    Object.assign(ctx.edges, { top: !global, bottom: global, chatTop: 'follow', chatBottom: override });
    assert.equal(ctx.timeline.edgeBlurTopEnabled(), !global);
    assert.equal(ctx.timeline.edgeBlurBottomEnabled(), expected);
    ctx.edges.master = false;
    assert.equal(ctx.timeline.edgeBlurTopEnabled(), false);
    assert.equal(ctx.timeline.edgeBlurBottomEnabled(), false);
  }
  assert.equal(ctx.composer.glassHostOn(),enabled);
  calls.length=0;ctx.dateOverlay.initialRender();assert.equal(calls.find(c=>c[0]==='surface')[1].effectsEnabled,enabled);
  ctx.state.level=-3;ctx.applySystemMaterial(disk.get(ctx.key));assert.equal(ctx.state.level,level);
}
ctx.immersiveMaterialAvailable=()=>false;assert.equal(ctx.composer.glassHostOn(),false,'old devices retain plain input fallback');
for(const invalid of [NaN,Infinity,-5,3,0.5]) {
  ctx.setSystemMaterialLevel(invalid);assert.equal(ctx.state.level,-4);assert.equal(ctx.state.chatEnabled,false);
}
for(let i=0;i<1000;i++)ctx.applySystemMaterial(-4);
assert.equal(storage.get('materialThickness'),2);assert.equal(storage.get('edgeBlurChatTop'),'on');
assert.equal(storage.get('edgeBlurChatBottom'),'on');assert.equal(disk.size,1,'only the new preference is persisted');
assert.equal(storage.get('surfaceGlassOn'),true);assert.equal(storage.get('bubbleGlassLevel'),1);
console.log('PASS: App default + off + five thicknesses; one persisted level for both themes; restart/invalid settings; compiled chat edge/input/date gates; unrelated list/bubble preferences preserved.');
run(fs.readFileSync(root + 'util/scrollEdgeBlur.ets', 'utf8'));
run(`class Gallery {${method('ChatBackgroundPage', 'galleryEdgeBlur', 'main')}} globalThis.gallery = new Gallery();`);
Object.assign(ctx.gallery, { edgeBlur: { bind: (...args) => args }, listViewH: 800,
  edgeBlurOn: true, edgeBlurTopOn: true, edgeBlurBottomOn: true,
  edgeBlurOtherTop: 'off', edgeBlurOtherBottom: 'follow' });
for (const scrolling of [false, true, false]) {
  ctx.gallery.scrollActive = scrolling;
  assert.deepEqual(ctx.gallery.galleryEdgeBlur(), [scrolling ? 0 : ctx.edgeBlurRadiusOf(true), 800, false, true]);
}
ctx.gallery.edgeBlurOn = false;
assert.deepEqual(ctx.gallery.galleryEdgeBlur(), [0, 800, false, false]);
// Real menu values and compiled selection callback: index zero must remain App default.
const settingsFile = compiled + 'pages/main/ChatSettingsPage.ts';
const settingsSource = fs.readFileSync(settingsFile,'utf8');
const settingsAst = ts.createSourceFile(settingsFile,settingsSource,ts.ScriptTarget.Latest,true);
ctx.str=x=>x;
for(const name of ['THICKNESS_OPTIONS','TINT_OPTIONS','SYSTEM_MATERIAL_OPTIONS']) {
  run(settingsAst.statements.find(n=>ts.isVariableStatement(n)&&n.declarationList.declarations.some(d=>d.name.getText(settingsAst)===name)).getText(settingsAst));
}
const settingsClass=settingsAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatSettingsPage');
run(`class Settings {${['systemMaterialIndex','systemMaterialSelectRow'].map(name=>settingsClass.members.find(n=>n.name?.getText(settingsAst)===name).getText(settingsAst)).join('\n')}} globalThis.settings = new Settings();`);
Object.assign(ctx,{Select:chain,Context:{animation(){}},HorizontalAlign:{Start:0},VerticalAlign:{Center:0},COLOR_TEXT_SECONDARY:'secondary'});
Object.assign(ctx.settings,{systemMaterialLevel:-4,observeComponentCreation2:cb=>cb(1,true),accent:()=> 'accent'});
calls.length=0;ctx.settings.systemMaterialSelectRow();
const options=calls.find(c=>c[0]==='create'&&Array.isArray(c[1]))[1];
assert.equal(options.length,7);assert.equal(options[0].value,'material_app_default');assert.equal(options[1].value,'material_thickness_off');
const select=calls.find(c=>c[0]==='onSelect')[1];
for(let index=0;index<7;index++) {
  ctx.settings.systemMaterialLevel=99;select(index);
  assert.equal(ctx.state.level,index-4);ctx.settings.systemMaterialLevel=ctx.state.level;
  assert.equal(ctx.settings.systemMaterialIndex(),index);
}
for(const invalid of [-1,7,NaN,0.5]){select(invalid);assert.equal(ctx.state.level,2);}
console.log('PASS: compiled single system-material menu has seven ordered options, persists each choice, rejects invalid indices.');

import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
let now=1000,queries=0,resolveSupport,starts=[],warnings=[],writes=[],rejectMotor=false;
const storage=new Map();
const ctx=vm.createContext({Date:{now:()=>now},AppStorage:{get:k=>storage.get(k)},logW:m=>warnings.push(m),
  vibrator:{isSupportEffect:()=>{queries++;return new Promise(r=>resolveSupport=r);},
    startVibration:(effect,attr)=>{starts.push({effect,attr});return rejectMotor?Promise.reject({code:1,message:'unavailable'}):Promise.resolve();}},
  setBoolean:(key,value)=>{storage.set(key,value);writes.push([key,value]);},
  setNumber:(key,value)=>{storage.set(key,value);writes.push([key,value]);}});
function run(source){vm.runInContext(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
function load(path,names){run(fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'')+names.map(n=>`\nglobalThis.${n}=${n};`).join(''));}
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
load(root+'util/navigationHapticSettings.ets',['normalizeNavigationHapticStrength']);
load(root+'services/NavigationHaptics.ets',['NavigationHaptics','navigationHaptics']);
const service=ctx.navigationHaptics;
for(let i=0;i<1000;i++)service.prepare();assert.equal(queries,1,'capability query is single-flight and cached');
service.play('folder');assert.equal(starts.length,0);resolveSupport(true);await Promise.resolve();assert.equal(starts.length,0,'late capability result must not cause delayed vibration');
storage.set('folderHapticStrength',20);storage.set('dockHapticStrength',75);
service.play('folder');assert.equal(starts.at(-1).effect.count,2,'repeat the original preset twice in one native call');assert.equal(starts.at(-1).effect.intensity,20);assert.equal(starts.at(-1).attr.usage,'touch');
service.play('dock');assert.equal(starts.length,1,'rapid duplicate calls coalesce');now+=100;service.play('dock');assert.equal(starts.at(-1).effect.intensity,75);
storage.set('folderHapticOn',false);now+=100;service.play('folder');assert.equal(starts.length,2);service.play('dock');assert.equal(starts.length,3,'folder toggle does not silence dock');
storage.set('folderHapticOn',true);storage.set('dockHapticOn',false);now+=100;service.play('dock');assert.equal(starts.length,3);service.play('folder');assert.equal(starts.length,4);
for(const [value,expected] of [[NaN,40],[Infinity,40],[-8,1],[200,100],[24.6,25]])assert.equal(ctx.normalizeNavigationHapticStrength(value),expected);
rejectMotor=true;now+=100;service.play('folder');await Promise.resolve();now+=100;service.play('folder');await Promise.resolve();assert.equal(warnings.length,1,'failures are bounded and do not interrupt navigation');rejectMotor=false;
const unsupported=new ctx.NavigationHaptics();unsupported.prepare();resolveSupport(false);await Promise.resolve();const before=starts.length;for(let i=0;i<1000;i++)unsupported.play('folder');assert.equal(starts.length,before);assert.equal(queries,2,'no repeated query or long vibration fallback');

// Actual compiled settings: moving a slider neither flushes preferences nor
// starts the motor; release writes only its category, toggling retains strength.
const events={toggle:null,slider:null,preview:null};
class View {observeComponentCreation2(fn){fn(1,true);}ifElseBranchUpdateFunction(_id,fn){fn();}}
Object.assign(ctx,{ViewPU:View,Context:{animation(){}},$r:x=>x,str:(k,v)=>`${k}:${v}`,COLOR_PRIMARY:1,COLOR_TEXT_PRIMARY:2,COLOR_TEXT_SECONDARY:3,
  ToggleType:{Switch:0},SliderChangeMode:{Moving:0,End:1,Click:2},Color:{Transparent:0}});
for(const name of ['Column','Row','Text','Toggle','Slider','Button','If'])ctx[name]=new Proxy({}, {get:(_t,key)=>(...args)=>{
  if(name==='Toggle'&&key==='onChange')events.toggle=args[0];if(name==='Slider'&&key==='onChange')events.slider=args[0];if(name==='Button'&&key==='onClick')events.preview=args[0];}});
load(compiled+'pages/main/NavigationHapticSettings.ts',['NavigationHapticCard']);
for(const category of ['folder','dock']) {
  const card=Object.create(ctx.NavigationHapticCard.prototype);
  for(const [key,value] of Object.entries({category,feedbackOn:true,feedbackStrength:40,cardLabel:'label'}))Object.defineProperty(card,key,{value,writable:true});
  storage.set(`${category}HapticOn`,true);card.initialRender();writes=[];const before=starts.length;
  events.slider(63,0);assert.equal(writes.length,0);assert.equal(starts.length,before);
  now+=100;events.slider(63,1);assert.deepEqual(writes,[[`${category}HapticStrength`,63]]);assert.equal(starts.at(-1).effect.intensity,63);
  events.toggle(false);assert.equal(storage.get(`${category}HapticOn`),false);assert.equal(storage.get(`${category}HapticStrength`),63);
  now+=100;const count=starts.length;events.preview();assert.equal(starts.length,count,'off cannot preview');
  events.toggle(true);assert.equal(storage.get(`${category}HapticStrength`),63);assert.equal(starts.at(-1).effect.intensity,63);
}
// Actual gesture commit method: one feedback across start/change/end, none for
// a cancelled swipe or unarmed programmatic selection.
const chat=fs.readFileSync(compiled+'pages/chatlist/ChatListPage.ts','utf8'),ast=ts.createSourceFile('chat.ts',chat,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatListPage');
const method=cls.members.find(n=>n.name?.getText(ast)==='finishFolderHaptic');run(`class Gesture {${method.getText(ast)}} globalThis.Gesture=Gesture;`);
const gesture=new ctx.Gesture();storage.set('folderHapticOn',true);let count=starts.length;now+=100;gesture.hapticGestureStart=1;gesture.finishFolderHaptic(2);gesture.finishFolderHaptic(2);assert.equal(starts.length,count+1);
count=starts.length;now+=100;gesture.hapticGestureStart=2;gesture.finishFolderHaptic(2);gesture.finishFolderHaptic(3);assert.equal(starts.length,count);
assert.match(fs.readFileSync('entry/src/main/module.json5','utf8'),/ohos\.permission\.VIBRATE/);
console.log('PASS: independent toggles/strength, normalization, single capability query, no delayed feedback, throttling/unsupported/failures; compiled settings persist only at release, and gesture commit deduplicates/cancels.');

// Replay the actual HDS tap callbacks, including returning to logical tab zero.
// Programmatic changes must not vibrate, and child clicks must not double it.
const main=fs.readFileSync(compiled+'pages/main/MainScreen.ts','utf8');
const mainAst=ts.createSourceFile('main.ts',main,ts.ScriptTarget.Latest,true);
const nativeTaps=[],changes=[],childClicks=[];
function visit(n){
 if(ts.isCallExpression(n)&&ts.isPropertyAccessExpression(n.expression)){
  const name=n.expression.name.text;
  if(name==='onTabBarClick')nativeTaps.push(n.arguments[0]);
  if(name==='onChange'||name==='onAnimationStart')changes.push(n.arguments[0]);
  if(name==='onClick')childClicks.push(n.arguments[0]);
 }
 ts.forEachChild(n,visit);
}
visit(mainAst);assert.equal(nativeTaps.length,2,'phone and split bars both bind native taps');
storage.set('dockHapticOn',true);storage.set('folderHapticOn',false);
for(const cb of nativeTaps){
 ctx.logicalTabIndex=(index,show)=>show?index:(index===0?0:index+1);
 ctx.tapHost={showContactsTab:true,select() {}};
 run('globalThis.tap=(function(){return '+cb.getText(mainAst)+';}).call(tapHost);');
 for(const tab of [2,0,3,0]){now+=100;const n=starts.length;ctx.tap(tab);assert.equal(starts.length,n+1);assert.equal(starts.at(-1).effect.count,2);}
 storage.set('dockHapticOn',false);now+=100;const n=starts.length;ctx.tap(0);assert.equal(starts.length,n);storage.set('dockHapticOn',true);
}
for(const cb of [...changes,...childClicks])assert.ok(!cb.getText(mainAst).includes('navigationHaptics.play'), 'native tap is the only dock haptic source');
console.log('PASS: both HDS bars vibrate when returning to Chats; no child-click duplicates or programmatic feedback; two preset repetitions.');

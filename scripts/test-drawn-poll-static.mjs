import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const created=[],children=[],glyphs=[];let next=0;
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}static create(c){children.push(c);}}
class Child {constructor(_parent,params){this.params=params;}}
class Painter {bind(){return this;}}
class Control {bind(...args){glyphs.push(args[5]);return this;}}
const ctx=vm.createContext({ViewV2:View,ViewPU:class{},DrawnPollText:Child,DrawnLoadingSpinner:Child,DrawnMediaControl:Control,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},str:k=>k,plural:k=>k,HitTestMode:{None:0},FlexAlign:{Center:0},HorizontalAlign:{Start:0},VerticalAlign:{Top:0},COLOR_PRIMARY:'primary',COLOR_TEXT_PRIMARY:'text',COLOR_TEXT_SECONDARY:'secondary'});
for(const name of ['Column','Row','If','Text','SymbolGlyph','Circle','__Common__','ViewStackProcessor'])ctx[name]=new Proxy({}, {get:(_t,k)=>(..._args)=>{if(k.startsWith('create'))created.push(name);}});
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const src=fs.readFileSync(root+'pages/chat/PollBubble.ts','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
vm.runInContext(ts.transpileModule(src+'\nglobalThis.Poll=PollBubble;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const b=Object.assign(Object.create(ctx.Poll.prototype),{msg:{pollQuestion:'Q',pollDescription:'',pollOptions:[],pollIsClosed:true,pollVotePending:false,pollExplanation:'Explain',pollVoteError:'Error'},prepared:{question:{},unavailable:{heightVp:20},showSubmit:false,showExplanation:true,explanation:{heightVp:20},error:{heightVp:20},headerHeight:20,height:150},paintEnv:ctx.chatEnv,headerPainter:new Painter(),footerPainter:new Painter(),submitPainter:new Painter(),unavailableIcon:new Control(),explanationIcon:new Control(),errorIcon:new Control(),maxWidth:240,fitAvailableWidth:true,emptyEntities:[],getUIContext:()=>({}),statusText:()=>'status',voterText:()=>'voters',observeComponentCreation2:fn=>fn(++next,true),ifElseBranchUpdateFunction:(_i,fn)=>fn()});
Object.defineProperties(b,{isUnavailable:{value:true},isExpired:{value:false},isResultsVisible:{value:true},isSubmitting:{value:false}});
b.initialRender();assert.deepEqual(glyphs,['warning','info','warning']);assert.equal(children.length,4);
for(const node of ['Text','SymbolGlyph','Circle'])assert.equal(created.includes(node),false,`prelaid poll must not create native ${node}`);
b.prepared={...b.prepared,showExplanation:false,error:null};b.msg={...b.msg,pollVoteError:''};glyphs.length=0;children.length=0;b.initialRender();assert.deepEqual(glyphs,['warning']);assert.equal(children.length,2);
console.log('PASS: compiled prepared poll empty/error/explanation states use Canvas icons and prelaid text, then remove stale decorations.');

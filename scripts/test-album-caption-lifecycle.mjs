// Real component methods, without ArkUI scheduling/rendering. Device validation
// still covers layout, reuse timing, visual continuity and frame latency.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
function compile(source) {
  return ts.transpileModule(source.replace(/^import[\s\S]*?;\n/gm, '')
    .replace(/@ComponentV2\s*/g, '').replace(/@Monitor\([^\n]*\)\s*/g, '')
    .replace(/@(?:Require|Param|Local|BuilderParam)\s*/g, '')
    .replace(/\bexport /g, '').replace(/\bstruct /g, 'class '),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
}
function method(source, name) {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, `missing method ${name}`);
  const end = source.indexOf('\n  }', start);
  return source.slice(start, end + 4);
}
const cellSource = read('../entry/src/main/ets/pages/chat/AlbumCellView.ets');
const liveSource = read('../entry/src/main/ets/pages/chat/LiveThumbImage.ets');
const helpers = ['thumbBackdrop', 'miniThumbPlaceholder', 'cachedImageSpec', 'liveThumbPath', 'liveThumbAttach', 'imageSwap', 'CachedImageSession']
  .map(name => read(`../entry/src/main/ets/util/${name}.ets`)).join('\n');
const cellJs = compile(`class Cell { cachedThumbSpec = null; ${method(cellSource, 'thumbSpec')} }\nglobalThis.Cell = Cell;`);
const liveJs = compile(liveSource.slice(0, liveSource.indexOf('  @Builder\n')) + '}\nglobalThis.Live = LiveThumbImage;');
function setup() {
  const paths = new Map(), listeners = new Map();
  const ctx = vm.createContext({ ImageFit: { Cover: 0 }, warnStaleThumbAttach() {},
    scrollPlaceholderState: {active:false}, vp2px:n=>n*3,
    cachedPixelMap:()=>undefined, cancelPixelMap:()=>{}, loadPixelMap:()=>new Promise(()=>{}),
    loadPixelMapSync:()=>undefined, retainPixelMap:()=>{}, releasePixelMap:()=>{},
    thumbPathFor: id => paths.get(id) || '',
    subscribeThumbPath(id, callback) {
      if (!listeners.has(id)) listeners.set(id, new Set());
      listeners.get(id).add(callback);
      return () => listeners.get(id).delete(callback);
    }
  });
  vm.runInContext(compile(helpers) + cellJs + liveJs, ctx);
  const cell = new ctx.Cell(), live = new ctx.Live();
  cell.cell = { thumbFileId: 1, thumbPath: '/a', width: 100, height: 80, isVideo: false, mini: 'mini-a' };
  live.spec = cell.thumbSpec(); live.aboutToAppear();
  return { cell, live, paths, listeners,
    update(changes) {
      const old = live.spec;
      cell.cell = { ...cell.cell, ...changes }; live.spec = cell.thumbSpec();
      if (old !== live.spec) live.onSpecChanged();
    },
    publish(id, path) { paths.set(id, path); for (const cb of listeners.get(id) || []) cb(path); }
  };
}
let count = 0;
function check(name, fn) {
  try { fn(); count++; } catch (error) { error.message = `${name}: ${error.message}`; throw error; }
}
check('selection/progress/retry metadata retain spec, image input and subscription', () => {
  const s = setup(), spec = s.live.spec, image = s.live.imageSpec(), unsub = s.live.unsubThumb;
  s.update({ selected: true, selectionActive: true, progress: 80, failed: true, uploading: true });
  assert.equal(s.live.spec, spec); assert.equal(s.live.imageSpec(), image); assert.equal(s.live.unsubThumb, unsub);
  assert.equal(spec.syncDisplay, true); assert.equal(spec.opaque, true); assert.equal(spec.deferMiniOnScroll, true);
});
check('all thumbnail inputs invalidate independently without mutating earlier specs', () => {
  for (const [field, value] of Object.entries({thumbFileId:2, thumbPath:'/b', width:130, height:99, isVideo:true, mini:'mini-b'})) {
    const s = setup(), first = s.live.spec, original = JSON.stringify(first);
    s.update({ [field]: value }); assert.notEqual(s.live.spec, first);
    assert.equal(JSON.stringify(first), original); assert.equal(s.cell.thumbSpec(), s.live.spec);
  }
});
check('a new downloadable file detaches old listener and receives only its own image', () => {
  const s = setup(); s.update({ thumbFileId: 2, thumbPath: '' });
  assert.equal(s.live.path, ''); assert.equal(s.listeners.get(1).size, 0);
  s.publish(1, '/late-a'); assert.equal(s.live.path, '');
  s.publish(2, '/b'); assert.equal(s.live.path, '/b'); assert.equal(s.live.imageSpec().sourceKey, 'f2');
});
check('channel path upgrade updates image input with an unchanged upstream spec', () => {
  const s = setup(), spec = s.live.spec, image = s.live.imageSpec();
  s.publish(1, '/better'); assert.equal(s.live.spec, spec);
  assert.notEqual(s.live.imageSpec(), image); assert.equal(s.live.imageSpec().path, '/better');
  assert.equal(s.live.imageSpec().sourceKey, image.sourceKey);
});
check('path-only reuse replaces and clears the old source', () => {
  const s = setup(); s.update({thumbFileId:0, thumbPath:'/local-a'});
  s.update({thumbPath:'/local-b'}); assert.equal(s.live.path, '/local-b');
  s.update({thumbPath:''}); assert.equal(s.live.path, ''); assert.equal(s.listeners.get(1).size, 0);
});
check('same-spec recycle/reuse reseeds synchronously even when the monitor stays silent', () => {
  const s = setup(), spec = s.live.spec; s.publish(1, '/known');
  s.live.aboutToRecycle(); assert.equal(s.listeners.get(1).size, 0);
  s.live.path = ''; s.live.spec = s.cell.thumbSpec(); assert.equal(s.live.spec, spec);
  s.live.aboutToReuse(); assert.equal(s.live.path, '/known'); assert.equal(s.listeners.get(1).size, 1);
  s.live.aboutToDisappear(); assert.equal(s.listeners.get(1).size, 0);
});
check('new-row reuse seeds the new source before asynchronous notifications', () => {
  const s = setup(); s.live.aboutToRecycle(); s.live.path = '';
  s.cell.cell = {...s.cell.cell, thumbFileId:3, thumbPath:'/new-row'};
  s.live.spec = s.cell.thumbSpec(); s.live.aboutToReuse();
  assert.equal(s.live.path, '/new-row'); assert.equal(s.live.attachedFileId, 3);
  s.publish(1, '/stale'); assert.equal(s.live.path, '/new-row');
});
const captionSource = read('../entry/src/main/ets/pages/chat/MessageBubbleText.ets');
const captionNames = ['plainCaptionShown','replacementTranslationShown','displayedMessageText',
  'displayedMessageEntities','timeReserveInText','timeReserveOnFooter','timeReserveOnStatus','hasTranslationStatusRow'];
const ctx = vm.createContext({});
vm.runInContext(compile(read('../entry/src/main/ets/util/richText.ets') + '\n' +
  read('../entry/src/main/ets/util/translationMode.ets') + '\nclass Caption {\n get input() { return {text:this.text, entities:this.entities}; }\n' +
  captionNames.map(n => method(captionSource, n)).join('\n') + '}\nglobalThis.Caption = Caption;'), ctx);
const entity = type => ({offset:0, length:4, type:{'@type':`textEntityType${type}`}});
function caption() {
  const c = new ctx.Caption(); c.text = '普通配文\n第二行'; c.entities = [];
  c.msg = {translatedText:'',translatedEntities:[],translationHidden:false,reactions:[]};
  c.env = {translateReplaceOriginal:false}; c.context = {translationStatus:null}; return c;
}
check('plain edits/reuse use current text and switch to rich rendering when links appear', () => {
  const c = caption(); assert.equal(c.plainCaptionShown(), true);
  c.text = '  edited\n😀\n'; assert.equal(c.plainCaptionShown(), true);
  assert.equal(c.displayedMessageText(c.text), '  edited\n😀\n');
  c.text = 'https://example.com'; assert.equal(c.plainCaptionShown(), false);
  c.text = 'plain again'; assert.equal(c.plainCaptionShown(), true);
});
check('same text with changed entities immediately switches rendering path', () => {
  const c = caption();
  for (const type of ['Bold','Spoiler','CustomEmoji','Pre','ExpandableBlockQuote','TextUrl']) {
    c.entities = [entity(type)]; assert.equal(c.plainCaptionShown(), false);
  }
  c.entities = []; assert.equal(c.plainCaptionShown(), true);
});
check('replacement translation uses its own entities and hiding restores the original path', () => {
  const c = caption(); c.entities = [entity('Bold')];
  c.env.translateReplaceOriginal = true; c.msg.translatedText = '译文';
  assert.equal(c.plainCaptionShown(), true); assert.equal(c.displayedMessageText(c.text), '译文');
  c.msg.translatedEntities = [entity('Spoiler')]; assert.equal(c.plainCaptionShown(), false);
  assert.equal(c.displayedMessageEntities(c.entities), c.msg.translatedEntities);
  c.msg.translatedEntities = []; c.msg.translationHidden = true;
  assert.equal(c.plainCaptionShown(), false); assert.equal(c.displayedMessageText(c.text), c.text);
});
check('automatic links in a replacement translation keep rich interaction', () => {
  const c = caption(); c.env.translateReplaceOriginal = true; c.msg.translatedText = 'visit t.me/example';
  assert.equal(c.plainCaptionShown(), false); c.msg.translationHidden = true;
  assert.equal(c.plainCaptionShown(), true);
});
check('time reserve stays on exactly the right text/status/footer for 24 combinations', () => {
  const c = caption();
  for (const reactions of [[], [{}]]) for (const translated of ['', '译文'])
    for (const hidden of [false, true]) for (const status of [null, {phase:'loading'}, {phase:'failed'}]) {
      c.msg.reactions = reactions; c.msg.translatedText = translated;
      c.msg.translationHidden = hidden; c.context.translationStatus = status;
      assert.deepEqual([c.timeReserveInText(), c.timeReserveOnStatus(), c.timeReserveOnFooter()],
        reactions.length ? [false,false,false] : translated ? [false,false,true] : status ? [false,true,false] : [true,false,false]);
    }
});
// Input identity and real text-state reset methods share the component contract.
const textSource = read('../entry/src/main/ets/pages/chat/MessageBubbleText.ets');
const resetStart = textSource.indexOf('  resetTextState():');
const resetEnd = textSource.indexOf('\n  }', resetStart) + 4;
const inputContext = vm.createContext({chatEnv:{}});
const textFields = textSource.slice(textSource.indexOf('  @Require @Param context:'), textSource.indexOf('  aboutToAppear():'));
vm.runInContext(compile(read('../entry/src/main/ets/util/messageTextInput.ets')) +
  compile(`class TextState { ${textFields}
    ${method(textSource, 'rememberTextSource')}
    ${textSource.slice(resetStart, resetEnd)}
  }
 globalThis.TextState = TextState; globalThis.InputCache = MessageTextInputCache; globalThis.PresentationCache = MessageTextPresentationCache;`), inputContext);
check('text input cache preserves identity and invalidates edited entities/width/mode', () => {
  const cache = new inputContext.InputCache(), entities = [];
  const first = cache.prepare('caption', entities, 100, 'caption');
  assert.equal(cache.prepare('caption', entities, 100, 'caption'), first);
  for (const args of [['edit',entities,100,'caption'],['caption',[],100,'caption'],
    ['caption',entities,120,'caption'],['caption',entities,100,'body']]) {
    cache.prepare('caption',entities,100,'caption');
    assert.notEqual(cache.prepare(...args),first);
  }
  assert.equal(first.text,'caption'); assert.equal(first.maxWidth,100);
});
check('text presentation updates preserve expanded state until text or row identity changes', () => {
  const cache = new inputContext.PresentationCache(), text = new inputContext.TextState();
  const layout = {contentWidth:390,isGroup:true,isChannel:false}, entities = [];
  let msg = {rowId:1};
  text.presentation = cache.prepare(msg, false, layout, 'caption', entities, 100, 'caption');text.rememberTextSource();
  text.expandedQuoteKeys=['q'];text.revealedSpoilerKeys=['s'];
  msg={rowId:1,translatedText:'translation'};
  text.presentation=cache.prepare(msg, true, {...layout,contentWidth:700}, 'caption',entities,120,'caption');text.resetTextState();
  assert.equal(text.expandedQuoteKeys[0],'q');assert.equal(text.revealedSpoilerKeys[0],'s');
  assert.equal(text.msg,msg);assert.equal(text.data.contentWidth,700);assert.equal(text.maxWidth,120);
  text.presentation=cache.prepare(msg,true,layout,'edited',entities,120,'caption');text.resetTextState();
  assert.equal(text.expandedQuoteKeys.length,0);assert.equal(text.revealedSpoilerKeys.length,0);
  text.expandedQuoteKeys=['q'];msg={rowId:2};
  text.presentation=cache.prepare(msg,true,layout,'edited',entities,120,'caption');text.resetTextState();
  assert.equal(text.expandedQuoteKeys.length,0);
});
check('caption getters consume the latest message and layout, with live context kept separate', () => {
  const cache = new inputContext.PresentationCache(), text = new inputContext.TextState();
  const context = {translationStatus:null,gestureClaimed:false,liveViews:'1'};
  const actions = {onLinkTap:()=>{}}; text.context=context; text.actions=actions;
  const msg = {rowId:1,translatedText:'old'}; const layout={contentWidth:390,isGroup:true,isChannel:false};
  text.presentation=cache.prepare(msg,false,layout,'caption',[],100,'caption');
  const old=text.presentation;
  const entities=[entity('Spoiler')];const nextMsg={rowId:2,translatedText:'new'};
  text.presentation=cache.prepare(nextMsg,true,{...layout,isGroup:false,isChannel:true},'new body',entities,200,'body');
  assert.equal(text.msg,nextMsg);assert.equal(text.text,'new body');assert.equal(text.entities,entities);
  assert.equal(text.mode,'body');assert.equal(text.data.isGroup,false);assert.equal(text.data.isChannel,true);
  assert.equal(text.presentation.showSenderName,true);assert.equal(old.msg,msg);assert.equal(old.input.text,'caption');
  context.gestureClaimed=true;context.translationStatus={phase:'loading'};
  assert.equal(text.context,context);assert.equal(text.context.gestureClaimed,true);assert.equal(text.actions,actions);
});
console.log(`Album/caption lifecycle: ${count} scenarios passed (including 24 time-reserve combinations)`);

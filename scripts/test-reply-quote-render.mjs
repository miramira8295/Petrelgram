// Exercise the actual ArkUI compiler output. Native layout/pixels still need device QA.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
for (const component of ['MessageBubbleShell', 'LightweightPlainTextBubble']) {
const source = fs.readFileSync(`entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/${component}.ts`, 'utf8');
const ast = ts.createSourceFile('shell.ts', source, ts.ScriptTarget.Latest, true);
let quote;
function visit(n) {
  if (ts.isMethodDeclaration(n) && n.name.getText(ast) === 'replyQuote') quote = n.getText(ast);
  ts.forEachChild(n, visit);
}
visit(ast);
assert.ok(quote);
let stack, root, snapshots = 0, layoutCallbacks = 0, animations = 0;
function node(type) {
  return new Proxy({}, { get: (_target, prop) => (...args) => {
    if (prop === 'create') {
      const child = { type, props: {}, children: [], content: args[0] };
      stack.at(-1).children.push(child); stack.push(child); return;
    }
    if (prop === 'pop') { assert.equal(stack.pop().type, type); return; }
    if (prop === 'background') snapshots++;
    if (prop === 'onSizeChange' || prop === 'onAreaChange') layoutCallbacks++;
    if (prop === 'animation') animations++;
    stack.at(-1).props[prop] = args[0];
  } });
}
const enumOf = () => new Proxy({}, { get: (_target, key) => key });
const globals = Object.fromEntries(['Row', 'Column', 'Text', 'Image', 'If'].map(type => [type, node(type)]));
const ctx = vm.createContext({ ...globals, REPLY_THUMB_GAP: 6, REPLY_THUMB_SIZE: 34,
  REPLY_QUOTE_LINE_H: 16, COLOR_TEXT_SECONDARY: 'secondary', accentSoft: () => 'soft',
  replyThumbSrc: path => path, ...Object.fromEntries(['VerticalAlign', 'ItemAlign', 'HorizontalAlign',
    'ImageFit', 'ImageInterpolation', 'TextOverflow'].map(name => [name, enumOf()])) });
vm.runInContext(ts.transpileModule(`class Probe { ${quote} } globalThis.Probe = Probe;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const probe = new ctx.Probe();
let width = 200, taps = [];
Object.assign(probe, { context: { gestureClaimed: false },
  actions: { onReplyTap: (...args) => taps.push(args) }, inlineMaxW: () => width,
  replyQuoteMaxW: () => Math.round(width * .76), replyMaxW: () => Math.round(width * .76), accent: () => 'accent',
  observeComponentCreation2: fn => {
    fn(1, true);
    if (stack.at(-1).type === 'Image') globals.Image.pop();
  }, ifElseBranchUpdateFunction: (_index, fn) => fn() });
let cases = 0;
for (const nextWidth of [160, 620, 200, 450, 160]) for (const thumbnail of ['', '/photo', '/sticker']) {
  width = nextWidth;
  probe.msg = { id: ++cases, replyToMessageId: 100 + cases, replyDiceLayers: [],
    replyThumbPath: thumbnail, replyThumbSticker: thumbnail === '/sticker',
    replySenderName: `sender ${cases}`, replyText: `current quote ${cases}` };
  root = { children: [] }; stack = [root]; probe.replyQuote();
  assert.equal(stack.length, 1);
  const row = root.children[0];
  assert.equal(row.props.constraintSize.maxWidth, width);
  assert.equal(row.props.alignSelf, 'Stretch');
  assert.equal(row.props.backgroundColor, 'soft');
  assert.equal(row.props.width, undefined, 'percentage width must not force every bubble to maximum width');
  const column = row.type === 'Column' ? row : row.children.find(child => child.type === 'Column');
  if (row.type === 'Row') assert.equal(column.props.flexShrink, 1);
  const texts = column.children.filter(child => child.type === 'Text');
  assert.equal(texts[1].content, probe.msg.replyText);
  for (const text of texts) assert.equal(text.props.constraintSize.maxWidth, Math.round(width * .76));
  row.props.onClick();
  assert.deepEqual(taps.at(-1), [probe.msg.replyToMessageId, probe.msg.id]);
  probe.context.gestureClaimed = true; probe.gestureClaimed = true;
  const before = taps.length; row.props.onClick(); assert.equal(taps.length, before);
  probe.context.gestureClaimed = false; probe.gestureClaimed = false;
}
assert.equal(snapshots, 0);
assert.equal(layoutCallbacks, 0);
assert.equal(animations, 0);
console.log(`${component} reply quote: ${cases} compiled-render cases passed; current constraints/content, no detached background, size callbacks or resident animation.`);

}

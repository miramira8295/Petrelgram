// Run after the HAP build: real compiled album input routing + pure geometry.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const ctx = vm.createContext({ ViewV2: class {}, ViewPU: class {} });
function load(path, names) {
  const source = fs.readFileSync(path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '')
    .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/@Monitor\([^)]*\)\s*/g, '')
    .replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(source + names.map(n => `\nglobalThis.${n} = ${n};`).join(''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
load('entry/src/main/ets/util/messageBubblePresentation.ets', ['BubbleCornerCache']);
load('entry/src/main/ets/util/bubbleCornerInset.ets', []);
load('entry/src/main/ets/util/albumCornerRadii.ets', ['AlbumCornerRadiiCache']);
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/LegacyAlbumMessageBubble.ts';
load(compiled, ['LegacyAlbumMessageBubble']);
const inner = new ctx.AlbumCornerRadiiCache(), outer = new ctx.BubbleCornerCache();
const keys = ['topLeft', 'topRight', 'bottomLeft', 'bottomRight'];
for (let radius = 0; radius <= 40; radius++) {
  for (let flags = 0; flags < 8; flags++) {
    const outgoing = !!(flags & 1), name = !!(flags & 2), avatar = !!(flags & 4);
    const shell = outer.prepare(radius, outgoing, name, avatar);
    const grid = inner.prepare(false, radius, outgoing, name, avatar);
    keys.forEach(k => assert.equal(grid[k], Math.max(0, shell[k] - 2)));
    assert.equal(inner.prepare(false, radius, outgoing, name, avatar), grid);
    assert.equal(inner.prepare(true, radius, outgoing, name, avatar).topLeft, 13);
    assert.equal(inner.prepare(false, radius, outgoing, name, avatar), grid, 'pure switch does not corrupt cached mixed corners');
  }
}
const album = Object.create(ctx.LegacyAlbumMessageBubble.prototype);
album.cornerCache = new ctx.AlbumCornerRadiiCache(); album.env = { bubbleRadius: 20 };
album.group = { caption: '', showSenderName: true, showAvatar: true, head: { text: '', translatedText: '',
  replyToMessageId: 0, reactions: [], forwardFrom: '', isOutgoing: false, senderName: '', commentCount: 0 } };
album.data = { isGroup: false, isChannel: false };
assert.equal(album.gridCornerRadii().topRight, 13, 'pure album stays 13vp');
const h = album.group.head;
for (const [target, key, value] of [[album.group, 'caption', 'caption'], [h, 'text', 'body'],
  [h, 'translatedText', 'translated'], [h, 'replyToMessageId', 9], [h, 'forwardFrom', 'sender'], [h, 'reactions', [{}]]]) {
  const previous = target[key]; target[key] = value;
  assert.equal(album.gridCornerRadii().topRight, 18, `${key} uses configured shell contour`);
  target[key] = previous;
}
album.data.isGroup = true; h.senderName = 'sender';
assert.equal(album.gridCornerRadii().topLeft, 18, 'visible nickname uses mixed contour');
album.group.showSenderName = false;
assert.equal(album.gridCornerRadii().topLeft, 13, 'hidden nickname retains pure contour');
album.group.caption = 'caption';
assert.equal(album.gridCornerRadii().topLeft, 5); assert.equal(album.gridCornerRadii().topRight, 18);
h.isOutgoing = true;
assert.equal(album.gridCornerRadii().topLeft, 18); assert.equal(album.gridCornerRadii().topRight, 5);
album.env.bubbleRadius = 1;
assert.equal(album.gridCornerRadii().bottomLeft, 0);
const source = fs.readFileSync(compiled, 'utf8');
assert.match(source, /new DrawnAlbumGrid\(/);
assert.match(source, /gridCorners: this\.gridCornerRadii\(\)/);
const gridSource = fs.readFileSync(compiled.replace('LegacyAlbumMessageBubble.ts', 'DrawnAlbumGrid.ts'), 'utf8');
assert.match(gridSource, /Stack\.borderRadius\(this\.gridCorners\)/);
assert.match(gridSource, /Stack\.borderRadius\(this\.gridCorners\);\s*Stack\.clip\(true\)/);
console.log('PASS: 328 geometry combinations, cache reuse, pure/mixed switch, actual compiled caption/name/reply/translation/outgoing/radius routing and grid clip binding.');

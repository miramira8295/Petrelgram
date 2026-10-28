// Exercise real component methods and presentation helpers on the host.
// ArkUI scheduling/rendering still requires a device recording.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const source = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
function compile(text) {
  return ts.transpileModule(text.replace(/^import[\s\S]*?;\n/gm, '')
    .replace(/@(?:ComponentV2|ObservedV2)\s*/g, '')
    .replace(/@Monitor\([^\n]*\)\s*/g, '')
    .replace(/@(?:Require|Param|Event|Local|Trace)\s*/g, '')
    .replace(/\bexport /g, '').replace(/\bstruct /g, 'class '),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
}
const shellSource = source('../entry/src/main/ets/pages/chat/MessageBubbleShell.ets');
const avatarStart = shellSource.indexOf('interface SenderAvatarState {');
const avatarEnd = shellSource.indexOf('  build() {', avatarStart);
const avatarJs = compile(shellSource.slice(avatarStart, avatarEnd) + '}\nglobalThis.Avatar = LiveSenderAvatar;');
const helpersJs = compile(source('../entry/src/main/ets/util/messageBubblePresentation.ets') + '\n' +
  source('../entry/src/main/ets/util/cachedImageSpec.ets'));
const channelJs = compile(source('../entry/src/main/ets/util/senderAvatarChannel.ets'));
const plain = value => JSON.parse(JSON.stringify(value));
const avatarSpec = changes => ({ senderId: 1, senderIsUser: true, initialPath: '/fallback',
  initials: 'A', avatarSize: 38, animate: true, ...changes });
function setup(initial = avatarSpec()) {
  const animated = new Set();
  let imagePolicyReads = 0;
  const ctx = vm.createContext({ ImageFit: { get Cover() { imagePolicyReads++; return 0; } },
    senderHasAnimatedPhoto: (id, user) => animated.has(`${user ? 'u' : 'c'}${id}`) });
  vm.runInContext(helpersJs + channelJs + avatarJs, ctx);
  const avatar = new ctx.Avatar(); avatar.spec = initial;
  return { avatar, ctx, animated, policyReads: () => imagePolicyReads,
    publish(key, path) { ctx.key = key; ctx.path = path; vm.runInContext('publishSenderAvatar(key, path)', ctx); },
    listeners(key) { ctx.key = key; return vm.runInContext('subs.get(key)?.size ?? 0', ctx); },
    update(changes) { avatar.spec = avatarSpec({ ...avatar.spec, ...changes }); avatar.onSpecChanged(); }
  };
}
let count = 0;
function check(name, run) {
  try { run(); count++; } catch (error) { error.message = `${name}: ${error.message}`; throw error; }
}
check('known path is seeded immediately and later channel updates arrive', () => {
  const s = setup(); s.publish('u1', '/known'); s.avatar.aboutToAppear();
  assert.equal(s.avatar.path, '/known'); assert.equal(s.listeners('u1'), 1);
  s.publish('u1', '/upgrade'); assert.equal(s.avatar.path, '/upgrade');
});
check('normal sender swap uses atomic fallback and unsubscribes the previous sender', () => {
  const s = setup(); s.avatar.aboutToAppear();
  s.update({ senderId: 2, initialPath: '/second' });
  assert.equal(s.avatar.path, '/second'); assert.equal(s.listeners('u1'), 0); assert.equal(s.listeners('u2'), 1);
  s.publish('u1', '/late-first'); assert.equal(s.avatar.path, '/second');
});
check('unknown new sender blanks previous pixels and receives only its own path', () => {
  const s = setup(); s.avatar.aboutToAppear(); s.update({ senderId: 2, initialPath: '' });
  assert.equal(s.avatar.path, ''); s.publish('u2', '/second'); assert.equal(s.avatar.path, '/second');
});
check('same numeric user and chat IDs are different sources', () => {
  const s = setup(); s.avatar.aboutToAppear(); s.publish('c1', '/chat');
  s.update({ senderIsUser: false, initialPath: '' });
  assert.equal(s.avatar.path, '/chat'); assert.equal(s.listeners('u1'), 0); assert.equal(s.listeners('c1'), 1);
});
check('same-sender style updates retain subscription, live path and image input', () => {
  const s = setup(); s.avatar.aboutToAppear(); s.publish('u1', '/downloaded');
  const unsub = s.avatar.unsubAvatar; const image = s.avatar.imageSpec();
  s.update({ initials: 'B', initialPath: '/stale-fallback' });
  assert.equal(s.avatar.unsubAvatar, unsub); assert.equal(s.avatar.path, '/downloaded');
  assert.equal(s.avatar.imageSpec(), image);
});
check('late fallback fills only an empty image for the same sender', () => {
  const s = setup(avatarSpec({ initialPath: '' })); s.avatar.aboutToAppear();
  s.update({ initialPath: '/late-fallback' }); assert.equal(s.avatar.path, '/late-fallback');
  s.publish('u1', '/downloaded'); s.update({ initialPath: '/older' });
  assert.equal(s.avatar.path, '/downloaded');
});
check('same-source reuse reseeds locals without duplicate subscription', () => {
  const s = setup(); s.publish('u1', '/known'); s.avatar.aboutToAppear();
  const unsub = s.avatar.unsubAvatar;
  s.avatar.avatarState = {path:'', animated:false}; s.avatar.aboutToReuse();
  assert.equal(s.avatar.path, '/known'); assert.equal(s.avatar.unsubAvatar, unsub); assert.equal(s.listeners('u1'), 1);
});
check('recycle and monitor-silent reuse reattach the new sender', () => {
  const s = setup(); s.avatar.aboutToAppear(); s.avatar.aboutToRecycle();
  assert.equal(s.listeners('u1'), 0);
  s.avatar.avatarState = {path:'', animated:false};
  s.avatar.spec = avatarSpec({ senderId: 2, initialPath: '/second' }); s.avatar.aboutToReuse();
  assert.equal(s.avatar.path, '/second'); assert.equal(s.listeners('u2'), 1);
  s.avatar.aboutToDisappear(); s.publish('u2', '/after-destroy');
  assert.equal(s.listeners('u2'), 0); assert.equal(s.avatar.path, '/second');
});
check('animation policy updates and comment avatars remain static', () => {
  const s = setup(); s.animated.add('u1'); s.avatar.aboutToAppear(); assert.equal(s.avatar.animated, true);
  s.update({ animate: false, avatarSize: 22 }); assert.equal(s.avatar.animated, false);
  s.update({ animate: true }); assert.equal(s.avatar.animated, true);
});
check('late animated-photo metadata is picked up on channel publish', () => {
  const s = setup(); s.avatar.aboutToAppear(); assert.equal(s.avatar.animated, false);
  s.animated.add('u1'); s.publish('u1', '/animated-poster'); assert.equal(s.avatar.animated, true);
});
check('avatar image policy retains bounded pinning and both sync flags', () => {
  const s = setup(); s.avatar.aboutToAppear(); const first = s.avatar.imageSpec();
  assert.equal(first.pinBounded, true); assert.equal(first.syncSmall, true); assert.equal(first.syncDisplay, true);
  s.update({ avatarSize: 22 }); const smaller = s.avatar.imageSpec();
  assert.equal(smaller.boxWidth, 22); assert.equal(smaller.boxHeight, 22); assert.equal(smaller.radius, 11);
  assert.equal(first.boxWidth, 38); assert.equal(smaller.fit, 0);
});
check('unchanged avatar skips candidate preparation across repeated reads and sender reuse', () => {
  const s = setup(); s.avatar.aboutToAppear(); const image = s.avatar.imageSpec();
  for (let i = 0; i < 1000; i++) assert.equal(s.avatar.imageSpec(), image);
  assert.equal(s.policyReads(), 1);
  // A new sender can legitimately use the same cached file and size.
  s.avatar.aboutToRecycle(); s.avatar.avatarState = { path: '', animated: false };
  s.avatar.spec = avatarSpec({ senderId: 2 }); s.avatar.aboutToReuse();
  assert.equal(s.avatar.imageSpec(), image); assert.equal(s.policyReads(), 1);
  assert.equal(s.listeners('u1'), 0); assert.equal(s.listeners('u2'), 1);
});
check('independent path updates and in-place sizes replace only the current avatar spec', () => {
  const s = setup(); s.avatar.aboutToAppear(); const old = s.avatar.imageSpec();
  Object.freeze(old);
  s.publish('u1', '/downloaded'); const downloaded = s.avatar.imageSpec();
  assert.notEqual(downloaded, old); assert.equal(downloaded.path, '/downloaded');
  s.avatar.spec.avatarSize = 22; const small = s.avatar.imageSpec();
  assert.notEqual(small, downloaded); assert.equal(small.boxWidth, 22);
  assert.equal(small.boxHeight, 22); assert.equal(small.radius, 11);
  assert.equal(old.path, '/fallback'); assert.equal(downloaded.boxWidth, 38);
  s.update({ senderId: 2, initialPath: '' }); const blank = s.avatar.imageSpec();
  assert.equal(blank.path, ''); assert.equal(blank.boxWidth, 22);
  assert.equal(s.policyReads(), 4);
});

function method(text, name) {
  const start = text.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, `missing ${name}`);
  const end = text.indexOf('\n  }', start);
  assert.ok(end > start); return text.slice(start, end + 4);
}
const newMethods = ['bubbleCornerRadius', 'isBareEmoji', 'senderAvatarSpec', 'commentAvatarSpec']
  .map(name => method(shellSource, name)).join('\n');
const ctx = vm.createContext({});
vm.runInContext(helpersJs + compile(`class After {
  cornerCache = new BubbleCornerCache(); avatarSpecCache = new SenderAvatarSpecCache();
  commentAvatarSpecCaches = []; ${newMethods} }
globalThis.after = new After();`), ctx);
check('corner geometry matches golden grouping shapes across live setting changes', () => {
  // TL, TR, BL, BR: null denotes the full configured radius. These eight
  // shapes also matched the previous component in the initial parity run.
  const shapes = [
    [false, false, false, [7, null, 7, null]],
    [false, false, true, [7, null, 2, null]],
    [false, true, false, [null, null, 7, null]],
    [false, true, true, [null, null, 2, null]],
    [true, false, false, [null, 7, null, 7]],
    [true, false, true, [null, 7, null, 2]],
    [true, true, false, [null, null, null, 7]],
    [true, true, true, [null, null, null, 2]]
  ];
  ctx.after.env = { bubbleRadius: 0 }; ctx.after.msg = { isOutgoing: false };
  ctx.after.group = { showSenderName: false, showAvatar: false };
  for (const radius of [0, 1, 2, 4, 7, 8, 12, 18, 28]) {
    for (const [outgoing, sender, avatar, corners] of shapes) {
      ctx.after.env.bubbleRadius = radius; ctx.after.msg.isOutgoing = outgoing;
      ctx.after.group.showSenderName = sender; ctx.after.group.showAvatar = avatar;
      const actual = plain(ctx.after.bubbleCornerRadius());
      assert.deepEqual([actual.topLeft, actual.topRight, actual.bottomLeft, actual.bottomRight],
        corners.map(limit => limit === null ? radius : Math.min(radius, limit)));
      assert.equal(ctx.after.bubbleCornerRadius(), ctx.after.bubbleCornerRadius());
    }
  }
});
check('content-type classification keeps all bare types with one reactive read', () => {
  for (const type of ['photo', 'video', 'text', 'emoji', 'sticker', 'customEmoji', 'videoNote', 'dice', 'unknown']) {
    let reads = 0;
    ctx.after.msg = { get contentType() { reads++; return type; } };
    assert.equal(ctx.after.isBareEmoji(), ['emoji', 'sticker', 'customEmoji', 'videoNote', 'dice'].includes(type));
    assert.equal(reads, 1);
  }
});
check('comment slots stay independent and shrink on a smaller group', () => {
  ctx.after.msg = { commentReplierIds: [1, 2, 3], commentReplierAvatarPaths: ['/a', '/b', '/c'] };
  const a = ctx.after.commentAvatarSpec(1, 0), b = ctx.after.commentAvatarSpec(2, 1);
  ctx.after.commentAvatarSpec(3, 2); assert.equal(ctx.after.commentAvatarSpec(1, 0), a);
  assert.equal(b.initialPath, '/b'); assert.equal(a.avatarSize, 22); assert.equal(a.animate, false);
  ctx.after.msg = { commentReplierIds: [4], commentReplierAvatarPaths: [] };
  const next = ctx.after.commentAvatarSpec(4, 0);
  assert.equal(next.senderId, 4); assert.equal(next.initialPath, '');
  assert.equal(ctx.after.commentAvatarSpecCaches.length, 1); assert.equal(a.initialPath, '/a');
});
check('sender input reads current data on reuse and retains policy', () => {
  ctx.after.msg = { senderId: 1, senderIsUser: true, senderAvatarPath: '/a', senderInitials: 'A' };
  const first = ctx.after.senderAvatarSpec(); assert.equal(ctx.after.senderAvatarSpec(), first);
  ctx.after.msg = { senderId: 2, senderIsUser: false, senderAvatarPath: '/b', senderInitials: 'B' };
  const next = ctx.after.senderAvatarSpec(); assert.notEqual(next, first);
  assert.equal(next.senderId, 2); assert.equal(next.avatarSize, 38); assert.equal(next.animate, true);
});
check('parser-owned segments hash text only once while reusing unchanged keys', () => {
  const textCtx = vm.createContext({});
  vm.runInContext(compile(source('../entry/src/main/ets/util/richText.ets')) +
    '\nglobalThis.parse = parseFormattedText; globalThis.keyFor = richSegmentKey;', textCtx);
  const segment = textCtx.parse('visit https://example.com', [])[0];
  let reads = 0; const original = segment.runs[0].text;
  Object.defineProperty(segment.runs[0], 'text', { get() { reads++; return original; } });
  const key = textCtx.keyFor(0, segment); const firstReads = reads; assert.ok(firstReads > 0);
  for (let i = 0; i < 10; i++) assert.equal(textCtx.keyFor(0, segment), key);
  assert.equal(reads, firstReads);
});
check('avatar path and animation publish atomically and unchanged input retains state', () => {
  const s=setup();s.animated.add('u1');s.avatar.aboutToAppear();
  assert.equal(s.avatar.animated,true);assert.equal(s.avatar.path,'/fallback');
  const state=s.avatar.avatarState;s.update({initials:'B'});assert.equal(s.avatar.avatarState,state);
  s.publish('u1','/new');assert.equal(s.avatar.animated,true);assert.equal(s.avatar.path,'/new');
  s.update({senderId:2,initialPath:'/two'});assert.equal(s.avatar.path,'/two');assert.equal(s.avatar.animated,false);
});
check('recycle/reuse clear all interaction state without replacing the gesture owner', () => {
  const hostCtx = vm.createContext({});
  vm.runInContext(compile(source('../entry/src/main/ets/util/messageDragGesture.ets') + `
    class Host {
      dragGesture = new MessageDragGesture();
      context = {gestureClaimed:true, resetInteraction(){this.gestureClaimed=false;}};
      draggingMessage=true;swipeFromEdge=true;swipeReplyX=40;editableTick=12;
      ${method(shellSource, 'clearTransientState')}
    } globalThis.host = new Host();`), hostCtx);
  const h=hostCtx.host,original=h.dragGesture;
  original.begin(1,2,1000);original.move(50,2,1600);original.claim();
  h.clearTransientState();h.clearTransientState();
  assert.equal(h.dragGesture,original);assert.equal(original.prefersDrag(2000),false);
  assert.equal(original.end(2000,false),false);assert.equal(h.context.gestureClaimed,false);
  assert.equal(h.draggingMessage,false);assert.equal(h.swipeFromEdge,false);
  assert.equal(h.swipeReplyX,0);assert.equal(h.editableTick,0);
  original.begin(3,4,3000);assert.equal(original.end(3600,false),true);
});
console.log(`Bubble presentation lifecycle: ${count} scenarios passed (including 72 corner combinations)`);

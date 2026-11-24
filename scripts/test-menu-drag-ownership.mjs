// Real gesture state plus HAP-compiled drag callbacks. Native overlay pixels
// still require device QA; these checks never send or export a real message.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const ctx = vm.createContext({ Date, Math, DragResult: { DRAG_CANCELED: 2 },
  tableScrollTouched: () => false, messageDragType: () => 'general.text',
  hitSenderAvatarColumn: () => false,
  configureMessageDrag: () => { exportsStarted++; return { extraInfo: 'test-only' }; } });
let exportsStarted = 0;
function evaluate(source) {
  return vm.runInContext(ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None
  } }).outputText, ctx);
}
evaluate(fs.readFileSync('entry/src/main/ets/util/messageDragGesture.ets', 'utf8')
  .replace('export class', 'class') + '\nglobalThis.Gesture = MessageDragGesture;');
const gesture = () => new ctx.Gesture();
for (const [dx, dy] of [[0, 0], [3, 4], [6, 6], [10, 0]]) {
  const state = gesture(); state.begin(50, 80, 1000);
  state.move(50 + dx, 80 + dy, 1600);
  assert.equal(state.end(1700, false), true, 'small motion remains a release-to-menu hold');
  assert.equal(state.canStartDrag(), false, 'late native callback cannot close that menu');
  assert.equal(state.end(1701, false), false, 'opens once');
}
for (const cancel of [state => state.end(1700, true), state => state.reset(),
  state => state.claim()]) {
  const state = gesture(); state.begin(0, 0, 1000); cancel(state);
  assert.equal(state.canStartDrag(), false);
}
const mouse = gesture(); mouse.begin(0, 0, 1000); mouse.move(30, 0, 1100);
assert.equal(mouse.canStartDrag(), true, 'native mouse drag does not require a touch long hold');
mouse.claim(); assert.equal(mouse.end(1200, false), false, 'mouse drag cannot open a menu');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/';
for (const name of ['DrawnMessageRow', 'MessageBubbleShell']) {
  const source = fs.readFileSync(root + name + '.ts', 'utf8');
  const ast = ts.createSourceFile(name + '.ts', source, ts.ScriptTarget.Latest, true);
  let start, options, parentHold;
  function visit(node) {
    if (ts.isArrowFunction(node) && node.body.getText(ast).includes('this.recordRowMenuOffset(localX)')) parentHold = node;
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)) {
      if (node.expression.name.text === 'onDragStart') start = node.arguments[0];
      if (node.expression.name.text === 'dragPreviewOptions') options = node.arguments[1];
    }
    ts.forEachChild(node, visit);
  }
  visit(ast); assert.ok(start); assert.ok(options);
  assert.equal(evaluate('(' + options.getText(ast) + ')').isLiftingDisabled, true,
    name + ' lets only the context menu own pre-drag lifting');
  const bind = evaluate('(function(preview) { return ' + start.getText(ast) + '; })');
  function host() {
    const state = gesture(); state.begin(0, 0, Date.now() - 600); state.move(40, 0, Date.now());
    return { dragGesture: state, canDragMessage: () => true, touchOnBody: true,
      claimed: false, touchRowId: 9, touchChatId: 1, rowGroup: { head: { id: 9, rowId: 9, contentType: 'text' } },
      rowData: { chatId: 1 }, data: { chatId: 1 }, msg: { id: 9, contentType: 'text' },
      context: { gestureClaimed: false, msgContextMenuShown: true }, menuShown: true,
      foreground: { press() {} } };
  }
  const row = host(), valid = bind.call(row, false);
  let canceled = 0;
  const event = { setResult: result => { assert.equal(result, 2); canceled++; } };
  const before = exportsStarted; valid(event);
  assert.equal(exportsStarted, before + 1, name + ' preserves intentional dragging');
  assert.equal(row.dragGesture.end(Date.now(), false), false, 'real drag never opens a menu');
  assert.equal(canceled, 0);
  for (const stop of [r => r.dragGesture.end(Date.now(), true), r => r.dragGesture.reset(),
    r => r.dragGesture.end(Date.now(), false), r => { r.canDragMessage = () => false; },
    r => { r.claimed = true; r.context.gestureClaimed = true; }]) {
    const stopped = host(); stop(stopped);
    const count = exportsStarted, previousCanceled = canceled;
    bind.call(stopped, false)(event);
    assert.equal(exportsStarted, count, name + ' rejected callback exports nothing');
    assert.equal(canceled, previousCanceled + 1);
    assert.equal(stopped.menuShown, true);
    assert.equal(stopped.context.msgContextMenuShown, true);
  }
  if (name === 'DrawnMessageRow') {
    for (const change of [r => { r.touchRowId++; }, r => { r.touchChatId++; }]) {
      const stale = host(); change(stale);
      const count = exportsStarted;
      bind.call(stale, false)(event);
      assert.equal(exportsStarted, count, 'reuse cannot export the new row from an old touch');
    }
    const count = exportsStarted; bind.call(host(), true)(event);
    assert.equal(exportsStarted, count, 'preview is never a drag source');
  } else {
    assert.ok(parentHold);
    let opened = 0;
    const legacy = host(); legacy.group = { showAvatar: false };
    legacy.recordRowMenuOffset = () => {};
    legacy.onLongPress = () => { opened++; };
    const hold = evaluate('(function() { return ' + parentHold.getText(ast) + '; })').call(legacy);
    hold({ fingerList: [{ localX: 50 }] });
    assert.equal(opened, 0, 'legacy outer hold must not open a menu before drag/release is resolved');
    legacy.dragGesture.reset(); hold({ fingerList: [{ localX: 50 }] });
    assert.equal(opened, 1, 'long hold in row whitespace keeps its menu');
  }
}
console.log('PASS: slight-motion menu, canceled/late/recycled drag rejection, native pre-lift isolation, valid drag preserved (both renderers).');

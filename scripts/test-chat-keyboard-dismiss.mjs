import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/chat/ChatPage.ets', import.meta.url), 'utf8');
const start = source.indexOf('  private interceptKeyboardDismiss(');
assert.ok(start >= 0);
const parsed = ts.createSourceFile('probe.ts', `class Probe {\n${source.slice(start)}`, ts.ScriptTarget.Latest, true);
const method = parsed.statements[0].members[0].getText(parsed);
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const HitTestMode = { Default: 0, Block: 1 };
const context = vm.createContext({ TouchType, HitTestMode });
vm.runInContext(ts.transpileModule(`class Probe { ${method} } globalThis.Probe = Probe;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);

function setup() {
  let dismissals = 0;
  const page = new context.Probe();
  Object.assign(page, {
    keyboardH: 280, composerFocused: true,
    composerEditorArea: { globalPosition: { x: 150, y: 420 }, width: 220, height: 60 },
    composerController: { stopEditing() { dismissals++; } }
  });
  const touch = (x, y, type = TouchType.Down) => ({
    type, changedTouches: [{ windowX: x, windowY: y }], touches: [{ windowX: x, windowY: y }]
  });
  return { page, touch, dismissals: () => dismissals };
}

test('outside press dismisses once and blocks child hit testing before release', () => {
  const { page, touch, dismissals } = setup();
  assert.equal(page.interceptKeyboardDismiss(touch(100, 300)), HitTestMode.Block);
  assert.equal(dismissals(), 1);
  assert.equal(page.composerFocused, false);
  page.interceptKeyboardDismiss(touch(100, 300, TouchType.Up));
  assert.equal(dismissals(), 1);
});

test('input interior and its top-left edge keep cursor and selection gestures', () => {
  for (const point of [[150, 420], [260, 450], [369, 479]]) {
    const { page, touch, dismissals } = setup();
    assert.equal(page.interceptKeyboardDismiss(touch(...point)), HitTestMode.Default);
    assert.equal(dismissals(), 0);
    assert.equal(page.composerFocused, true);
  }
});

test('all four input edges exclude adjacent buttons and surrounding whitespace', () => {
  for (const point of [[149, 450], [370, 450], [260, 419], [260, 480]]) {
    const { page, touch, dismissals } = setup();
    assert.equal(page.interceptKeyboardDismiss(touch(...point)), HitTestMode.Block);
    assert.equal(dismissals(), 1);
  }
});

test('closed keyboard and keyboard owned by another editor leave actions alone', () => {
  for (const patch of [{ keyboardH: 0 }, { composerFocused: false }]) {
    const { page, touch, dismissals } = setup();
    Object.assign(page, patch);
    assert.equal(page.interceptKeyboardDismiss(touch(100, 300)), HitTestMode.Default);
    assert.equal(dismissals(), 0);
  }
});

test('non-down events cannot cancel a gesture that started in the input', () => {
  const { page, touch, dismissals } = setup();
  for (const phase of [TouchType.Move, TouchType.Up, TouchType.Cancel]) {
    assert.equal(page.interceptKeyboardDismiss(touch(100, 300, phase)), HitTestMode.Default);
  }
  assert.equal(dismissals(), 0);
});

test('window coordinates honor moved layouts and split view offsets', () => {
  const { page, touch, dismissals } = setup();
  page.composerEditorArea.globalPosition = { x: 730, y: 180 };
  assert.equal(page.interceptKeyboardDismiss(touch(800, 210)), HitTestMode.Default);
  assert.equal(page.interceptKeyboardDismiss(touch(200, 450)), HitTestMode.Block);
  assert.equal(dismissals(), 1);
});

test('missing or invalid geometry and empty events do not steal editor input', () => {
  for (const area of [undefined, { globalPosition: { x: NaN, y: 0 }, width: 30, height: 30 },
    { globalPosition: { x: 0, y: 0 }, width: 0, height: 30 }]) {
    const { page, touch, dismissals } = setup();
    page.composerEditorArea = area;
    assert.equal(page.interceptKeyboardDismiss(touch(100, 300)), HitTestMode.Default);
    assert.equal(dismissals(), 0);
  }
  const { page, dismissals } = setup();
  assert.equal(page.interceptKeyboardDismiss({ type: TouchType.Down, changedTouches: [], touches: [] }), HitTestMode.Default);
  assert.equal(dismissals(), 0);
});

test('touches fallback still consumes the dismissing press', () => {
  const { page, touch, dismissals } = setup();
  const event = touch(100, 300);
  event.changedTouches = [];
  assert.equal(page.interceptKeyboardDismiss(event), HitTestMode.Block);
  assert.equal(dismissals(), 1);
});

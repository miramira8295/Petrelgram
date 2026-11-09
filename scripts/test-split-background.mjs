import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const read = path => fs.readFileSync(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8');
function method(path, name) {
  const source = read(path);
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, name);
  const parsed = ts.createSourceFile('probe.ts', `class Probe {\n${source.slice(start)}`, ts.ScriptTarget.Latest, true);
  return parsed.statements[0].members[0].getText(parsed);
}
const context = vm.createContext({
  parseSnapshot: raw => { try { return JSON.parse(raw); } catch { return null; } },
  emptyChatBackground: () => ({ colors: [], path: '', dimming: 0 })
});
const breakpoints = read('util/layoutBreakpoint.ets').replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
vm.runInContext(ts.transpileModule(`${breakpoints}
class Backdrop { ${method('pages/chat/ChatBackdrop.ets', 'suppressedByUnifiedBg')} }
class Page { ${method('pages/chat/ChatPage.ets', 'chromeBackground')} }
globalThis.Backdrop = Backdrop; globalThis.Page = Page;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);

const tablet = { isChatSlot: true, unifiedBg: true, appBgOn: false,
  widthBp: 3, heightBp: 0, forceSingle: false, portrait: false };
function suppressed(overrides = {}) {
  return Object.assign(new context.Backdrop(), tablet, overrides).suppressedByUnifiedBg();
}

test('tablet chat reveals shared canvas with either default or custom APP background', () => {
  assert.equal(suppressed(), true);
  assert.equal(suppressed({ appBgOn: true }), true);
});
test('APP canvas itself stays visible and opting out restores chat wallpaper', () => {
  assert.equal(suppressed({ isChatSlot: false }), false);
  assert.equal(suppressed({ unifiedBg: false }), false);
});
test('portrait, phone landscape and forced single column keep independent chat wallpaper', () => {
  for (const overrides of [{ portrait: true }, { widthBp: 1 },
    { widthBp: 2, heightBp: 0 }, { forceSingle: true }]) {
    assert.equal(suppressed(overrides), false);
  }
});
test('chrome follows visible shared wallpaper and returns to chat wallpaper after rotation', () => {
  const page = new context.Page();
  const own = { colors: ['#FFFFFF'], path: '', dimming: 0 };
  const shared = { colors: ['#000000'], path: '', dimming: 0.5 };
  Object.assign(page, { unifiedBackground: true, chatBg: own, appBackgroundRaw: JSON.stringify(shared) });
  assert.deepEqual(page.chromeBackground(), shared);
  page.unifiedBackground = false;
  assert.equal(page.chromeBackground(), own);
});
test('empty or invalid APP snapshot uses default canvas rather than hidden chat colors', () => {
  const page = new context.Page();
  for (const raw of ['', 'broken']) {
    Object.assign(page, { unifiedBackground: true, appBackgroundRaw: raw, chatBg: { colors: ['#000000'] } });
    assert.equal(page.chromeBackground().colors.length, 0);
  }
});

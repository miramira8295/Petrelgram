import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const util = fs.readFileSync(new URL('../entry/src/main/ets/util/chatActionBar.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\r?\n/gm, '').replace(/\bexport /g, '');
const page = fs.readFileSync(new URL('../entry/src/main/ets/pages/chat/ChatPage.ets', import.meta.url), 'utf8');
const start = page.indexOf('  private syncActionBar(');
assert.ok(start >= 0);
const parsed = ts.createSourceFile('probe.ts', `class Probe {\n${page.slice(start)}`, ts.ScriptTarget.Latest, true);
const method = parsed.statements[0].members[0].getText(parsed);
let entry;
const context = vm.createContext({ getChatStore: () => ({ entryOf: () => entry }) });
vm.runInContext(ts.transpileModule(`${util}\nclass Probe { ${method} } globalThis.Probe = Probe;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);

function sync(kind, canUnarchive = false, probe = new context.Probe()) {
  entry = kind === undefined ? undefined : { actionBar: kind, actionBarCanUnarchive: canUnarchive };
  probe.syncActionBar();
  return probe;
}

test('unsupported group actions never reserve a row, including unarchive flag', () => {
  for (const kind of ['chatActionBarInviteMembers', 'chatActionBarReportUnrelatedLocation',
    'chatActionBarJoinRequest', 'futureActionBar', '']) {
    for (const flag of [false, true]) assert.equal(sync(kind, flag).actionBarKind, '');
  }
});

test('supported actions keep their buttons and unarchive state', () => {
  for (const kind of ['chatActionBarReportAddBlock', 'chatActionBarReportSpam',
    'chatActionBarAddContact', 'chatActionBarSharePhoneNumber']) {
    const probe = sync(kind, true);
    assert.equal(probe.actionBarKind, kind);
    assert.equal(probe.actionBarCanUnarchive, true);
  }
});

test('live updates from supported to unsupported clear the displayed row', () => {
  const probe = sync('chatActionBarReportSpam');
  sync('chatActionBarInviteMembers', false, probe);
  assert.equal(probe.actionBarKind, '');
  sync('chatActionBarAddContact', false, probe);
  assert.equal(probe.actionBarKind, 'chatActionBarAddContact');
});

test('missing chat entry clears previous display state', () => {
  const probe = sync('chatActionBarReportSpam', true);
  sync(undefined, false, probe);
  assert.equal(probe.actionBarKind, '');
  assert.equal(probe.actionBarCanUnarchive, false);
});

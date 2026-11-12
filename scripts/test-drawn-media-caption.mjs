// Verify actual compiled caption/body dispatch and width inputs independently
// of native shaping. Paragraph shaping/cache tests live in the layout suite.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/MessageBubbleText.ts';
const source = fs.readFileSync(compiled, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '')
  .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/@Monitor\([^)]*\)\s*/g, '')
  .replace(/\bexport /g, '');
let rtl = false;
const ctx = vm.createContext({ ViewV2: class {}, ViewPU: class {},
  DRAWN_RICH_TEXT_ENABLED: true, textMeasureEnvironment: { epoch: 0 },
  drawnTextUsesRtlLayout: () => rtl, COLOR_PRIMARY: 'accent', bubbleTextFor: () => 'body',
  Color: { Transparent: 0 }, bubbleMaxWidth: (width, gutter) => width - gutter - 32,
  BUBBLE_AVATAR_GUTTER_VP: 44, logW() {} });
vm.runInContext(ts.transpileModule(source + '\nglobalThis.Probe = MessageBubbleText;',
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
const view = Object.create(ctx.Probe.prototype);
const richSource = { content: 'photo caption', links: [{ url: 'https://example.org' }],
  targets: new Set(['https://example.org']) };
view.presentation = { input: { text: 'photo caption', entities: [], mode: 'caption', maxWidth: 250 },
  layout: { contentWidth: 400, isGroup: false }, msg: { isOutgoing: false, translatedText: '', reactions: [] } };
view.context = { translationStatus: null, gestureClaimed: false };
view.env = { bubbleMaterialOn: false, langEpoch: 0, appearanceEpoch: 0, msgTextSize: 16, linkNavBusy: '' };
view.drawnSource = { prepare() { return richSource; } };
view.drawnLayouts = { prepare(_ui, spec) { return spec; } };
view.getUIContext = () => ({});
view.measuredTimeLayerWidth = () => 42;
view.timeReserve = () => ' 12:34';
assert.equal(view.drawnTextLayout.maxWidthVp, 234, 'single media caption subtracts its two 8vp side paddings once');
assert.equal(view.drawnTextLayout.minWidthVp, 42);
assert.equal(view.drawnTextLayout.reserve, ' 12:34');
view.presentation.input.maxWidth = 0;
assert.equal(view.drawnTextLayout.maxWidthVp, 336, 'album zero budget uses existing bubble cap, never zero paragraph width');
view.presentation.layout.isGroup = true;
assert.equal(view.drawnTextLayout.maxWidthVp, 292, 'incoming group caption reserves avatar gutter');
view.presentation.msg.isOutgoing = true;
assert.equal(view.drawnTextLayout.maxWidthVp, 336, 'outgoing caption reclaims avatar gutter');
view.presentation.input.maxWidth = 999;
assert.equal(view.drawnTextLayout.maxWidthVp, 336, 'explicit cap never exceeds row budget');
view.presentation.input.mode = 'body'; view.presentation.input.maxWidth = 280;
assert.equal(view.drawnTextLayout.maxWidthVp, 280, 'body retains its own width contract');
view.presentation.input.mode = 'translation'; assert.equal(view.drawnTextLayout, null);
view.presentation.input.mode = 'caption';
view.presentation.msg.reactions = [{}]; assert.equal(view.drawnTextLayout.reserve, '');
view.presentation.msg.reactions = [];
view.presentation.msg.translatedText = 'translation'; assert.equal(view.drawnTextLayout, null);
view.presentation.msg.translatedText = ''; view.context.translationStatus = 'pending'; assert.equal(view.drawnTextLayout, null);
view.context.translationStatus = null; view.env.bubbleMaterialOn = true; assert.equal(view.drawnTextLayout, null);
view.env.bubbleMaterialOn = false; rtl = true; assert.equal(view.drawnTextLayout, null); rtl = false;
view.env.linkNavBusy = 'https://example.org'; assert.notEqual(view.drawnTextLayout, null);
view.env.linkNavBusy = ''; assert.notEqual(view.drawnTextLayout, null);
view.drawnSource.prepare = () => null; assert.equal(view.drawnTextLayout, null, 'unsupported entities retain native renderer');
let clicks = 0;
view.actions = { onLinkTap(url, hidden) { assert.equal(url, 'https://example.org'); assert.equal(hidden, true); clicks++; } };
view.tapDrawnLink({ url: 'https://example.org', hidesUrl: true }); assert.equal(clicks, 1);
view.context.gestureClaimed = true; view.tapDrawnLink({ url: 'https://example.org', hidesUrl: true }); assert.equal(clicks, 1);
console.log('PASS: compiled caption/body width, album zero budget, group/outgoing gutters, reaction/footer reservation, native fallback and link gesture routing.');

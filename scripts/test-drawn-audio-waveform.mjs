import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript'), ts = imported.default || imported;
let invalidations = 0, nativeAllocations = 0, shapeOperations = 0, strokeUpdates = 0;
class Pen {
  constructor() { nativeAllocations++; }
  setAntiAlias() {} setCapStyle() {} setColor(color) { this.color = color; }
  setStrokeWidth(width) { this.width = width; strokeUpdates++; }
}
class Path {
  constructor() { nativeAllocations++; this.lines = []; }
  reset() { this.lines = []; shapeOperations++; }
  moveTo(x,y) { this.from = [x,y]; shapeOperations++; }
  lineTo(x,y) { this.lines.push([...this.from,x,y]); shapeOperations++; }
}
const context = vm.createContext({ DrawModifier: class { invalidate() { invalidations++; } },
  drawing: { Pen, Path, CapStyle: { ROUND_CAP: 1 } }, drawnColor: color => color });
const source = fs.readFileSync('entry/src/main/ets/pages/chat/DrawnAudioWaveform.ets', 'utf8')
  .replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
vm.runInContext(ts.transpileModule(source + '\nglobalThis.Wave = DrawnAudioWaveform;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const calls = [], clips = [];
let saves = 0, pen = null;
const canvas = { attachPen(p) { pen = p; }, detachPen() {},
  drawPath(path) { calls.push({ color: pen.color, lines: path.lines.map(p => [...p]) }); },
  save() { saves++; }, restore() { saves--; }, clipRect(rect) { clips.push({...rect}); } };
const dc = { sizeInPixel: {width:132,height:22}, canvas };
const bars = Array.from({length:34}, (_,i) => i % 20 + 3);
const wave = new context.Wave();
wave.bind(bars, 0, 1, 'active', 'idle', true); wave.drawBehind(dc);
assert.equal(calls.length, 1); assert.equal(calls[0].lines.length,34);
assert.equal(saves, 0);
for (const [x,y,xx,yy] of calls[0].lines) {
  assert.equal(x,xx); assert.ok(x>=0 && x<=132 && y>=0 && yy<=22);
}
const coldOps = shapeOperations, coldNatives = nativeAllocations, coldStroke = strokeUpdates;
const coldInvalidations = invalidations;
for (let i=0;i<1000;i++) { wave.bind(bars,0,1,'active','idle',true); wave.drawBehind(dc); }
assert.equal(invalidations,coldInvalidations);
for (let i=0;i<1000;i++) { wave.bind(bars,(i%100)/100,1,'active','idle',true); wave.drawBehind(dc); }
assert.equal(shapeOperations,coldOps,'playback never rebuilds waveform geometry');
assert.equal(nativeAllocations,coldNatives,'no per-paint native allocations');
assert.equal(strokeUpdates,coldStroke,'stroke is not reset during progress paint');
wave.bind(bars,1,1,'new-active','new-idle',true); wave.drawBehind(dc);
assert.equal(calls.at(-1).color,'new-active'); assert.ok(clips.at(-1).right<=132);
assert.equal(shapeOperations,coldOps,'color is paint-only'); assert.equal(saves,0);
wave.bind(bars,0,1,'active','idle',false); calls.length=0; wave.drawBehind(dc);
assert.equal(calls.length,2,'music retains its leading highlighted bar');
const beforeResize=shapeOperations; dc.sizeInPixel.width=70; wave.drawBehind(dc);
assert.ok(shapeOperations>beforeResize,'width changes rebuild exactly the retained path');
const beforeReuse=shapeOperations;
wave.bind([NaN,Infinity,0,30],NaN,2,'a','b',true); calls.length=0; wave.drawBehind(dc);
assert.ok(shapeOperations>beforeReuse); assert.equal(calls.length,1);
for(const line of calls[0].lines) assert.ok(line.every(Number.isFinite));
wave.bind([],1,1,'a','b',true); calls.length=0; wave.drawBehind(dc); assert.equal(calls.length,0,'recycle to empty source cannot paint old bars');
for (const name of ['VoiceBubble','MusicBubble']) {
  const ui=fs.readFileSync(`entry/src/main/ets/pages/chat/${name}.ets`,'utf8');
  assert.match(ui,/drawModifier\(this.wavePainter.bind/);
  assert.doesNotMatch(ui,/ForEach\(this\.(?:bars|waveBars)\(/,'no per-bar component tree');
}
console.log('PASS: retained audio waveform, 1000 progress draws without geometry/native allocations/stroke changes, size/source/color updates, invalid input and voice/music progress parity.');

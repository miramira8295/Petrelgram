import { RichRun } from './richText';
import { DrawnRichSource, DrawnRichBlock, buildDrawnRichSource } from './drawnRichTextPolicy';

interface DrawnFlowRange { start: number; end: number; }
const flowSources: WeakMap<DrawnRichSource, DrawnRichSource> = new WeakMap<DrawnRichSource, DrawnRichSource>();

function flowRun(run: RichRun, start: number, end: number, offset: number): RichRun {
  return { offset, text: run.text.substring(start, end), bold: run.bold, italic: run.italic,
    underline: run.underline, strike: run.strike, code: run.code, spoiler: run.spoiler,
    customEmojiId: run.customEmojiId, link: run.link, url: run.url,
    icon: run.icon, script: run.script, marked: run.marked, math: run.math };
}

// Split only at a real paragraph boundary, never at a UTF-16 budget or a soft
// wrap. A long unbroken paragraph stays native, as on modern Android. Delimiters
// in links/atomic placeholders stay in that paragraph too. Each character and
// run is visited a constant number of times; no entities are parsed per chunk.
// The full original source remains the copy/accessibility/interaction owner.
export function drawnRichFlowSource(source: DrawnRichSource): DrawnRichSource {
  if (source.blocks !== undefined || source.table !== undefined || source.content.length <= 16384) { return source; }
  const cached = flowSources.get(source);
  if (cached !== undefined) { return cached; }
  const content = source.content, runs = source.runs;
  const ranges: DrawnFlowRange[] = [];
  let start: number = 0, runIndex: number = 0;
  for (let at: number = 0; at < content.length; at++) {
    const code = content.charCodeAt(at);
    if (code !== 10 && code !== 13 && code !== 0x2028 && code !== 0x2029) { continue; }
    const delimiter = code === 13 && content.charCodeAt(at + 1) === 10 ? 2 : 1;
    while (runIndex < runs.length && runs[runIndex].offset + runs[runIndex].text.length <= at) { runIndex++; }
    const run = runs[runIndex];
    if (at - start >= 8192 && at + delimiter < content.length && run !== undefined && run.url === '' &&
      run.offset + run.text.length >= at + delimiter && run.customEmojiId === '' && run.icon === undefined && run.math === undefined) {
      ranges.push({ start, end: at }); start = at + delimiter;
    }
    at += delimiter - 1;
  }
  if (ranges.length === 0) { flowSources.set(source, source); return source; }
  ranges.push({ start, end: content.length });
  const blocks: DrawnRichBlock[] = [];
  runIndex = 0;
  for (const range of ranges) {
    const parts: RichRun[] = [];
    while (runIndex < runs.length && runs[runIndex].offset + runs[runIndex].text.length <= range.start) { runIndex++; }
    while (runIndex < runs.length && runs[runIndex].offset < range.end) {
      const run = runs[runIndex], end = run.offset + run.text.length;
      const left = Math.max(run.offset, range.start), right = Math.min(end, range.end);
      if (right > left) { parts.push(flowRun(run, left - run.offset, right - run.offset, left - range.start)); }
      if (end > range.end) { break; }
      runIndex++;
    }
    const leaf = buildDrawnRichSource(content.substring(range.start, range.end), parts);
    // Invalid/custom parser data keeps its established validation path; never
    // publish a partially segmented document.
    if (leaf === null) { flowSources.set(source, source); return source; }
    leaf.rtl = source.rtl; leaf.hasMath = source.hasMath;
    blocks.push({ source: leaf, kind: 'flow', offset: range.start, expandable: false, language: '' });
  }
  const result: DrawnRichSource = { content, runs: [], links: source.links, targets: source.targets,
    blocks, rtl: source.rtl, hasMath: source.hasMath, hasEmbed: source.hasEmbed, anchorNames: source.anchorNames };
  flowSources.set(source, result);
  return result;
}

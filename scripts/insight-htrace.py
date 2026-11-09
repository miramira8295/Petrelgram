#!/usr/bin/env python3
"""Summarise (and diff) a DevEco Studio ``*.insight`` (ArkUI template) dump.

Usage:
    scripts/insight-htrace.py DUMP.insight                 # one-dump summary
    scripts/insight-htrace.py DUMP.insight --frames        # + per-frame table
    scripts/insight-htrace.py DUMP.insight --json          # machine readable
    scripts/insight-htrace.py NEW.insight --against BASE.insight   # A/B table
    scripts/insight-htrace.py NEW.insight --against BASE.json      # A/B table

Works directly on the ``.insight`` zip; nothing is extracted to disk.

Why this exists: DevEco's own "App Frame" panel and the GPU template measure
different things (composer frames vs GPU utilisation), and neither exposes the
state-write ledger. This script reads the same artifacts the IDE reads:

  * ``manifest.json``                — pid, window, template list
  * ``trace_*.htrace``               — OHOSPROF protobuf; each packet is
                                       ``0x12 <4-byte varint len>`` with
                                       ``field 1 = ts(ns)``, ``field 2 = pid``,
                                       ``field 1109 = { field 2 = "B|tid|name" }``
  * ``*_arkui_state_variable.db``    — per-write state-variable ledger
  * ``CPU-*<pid>.cpuprofile``        — ArkTS sampling profile of the main thread

Metrics, in the order the docs use them:
  1. frames      — composer frame count/interval percentiles, slow frames
  2. main        — main-thread busy share + per-section wall-clock union
  3. rows        — Repeat node creation, BuildRecycle count/avg
  4. scroll      — fling count and travel
  5. state       — writes/vsync, invalidations/vsync, same-content writes
  6. cpu         — ArkTS sample time by module + inclusive cost of known hot calls

Caveats this script encodes (learned the hard way):
  * Section times are interval *unions*, so nested sections do not add up.
  * The state ledger only contains writes that actually fired ``fireChange``;
    V2 short-circuits ``===``, so a "same-content" row means "same content,
    new reference" (an object/array literal), not a redundant primitive write.
  * Arrays are serialised as ``[]`` in the ledger — their same-content rate is
    NOT measurable this way.
"""

from __future__ import annotations

import argparse
import collections
import os
import signal
import json
import sqlite3
import statistics
import sys
import tempfile
import unicodedata
import zipfile
from pathlib import Path

# Sections worth calling out on the summary; everything else is aggregated.
APP_SECTIONS = (
    'H:List predict v2',
    'H:ExecuteJS',
    'H:CustomNode:BuildRecycle',
    'H:CustomNode:BuildItem',
    'H:JSListItem::ExecuteDeepRender',
    'H:FlushLayoutTask',
    'H:Layout',
    'H:Measure',
    'H:Repeat.IdleTask',
    'H:OnIdle',
    'H:UIVsyncTask',
)

# Functions whose inclusive ArkTS cost is worth tracking across builds.
CPU_WATCH = (
    'resetStateVarsOnReuse',
    'updateStateVars',
    'observeComponentCreation2',
    'updateFunc',
    'onGetRid4Index',
    'preparedMessageBubble',
    'prepareMessageBubble',
    'timelineRow',
    'initialRender',
    'handleTimelineScrollIndex',
    'handleTimelineDidScroll',
    'updateFloatDate',
    'applyLiveGroup',
    'attach',
    'samePresentation',
)


# --------------------------------------------------------------------------- #
# htrace decoding
# --------------------------------------------------------------------------- #

def _varint(buf: bytes, i: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = buf[i]
        value |= (byte & 0x7F) << shift
        i += 1
        shift += 7
        if not byte & 0x80:
            return value, i


def _len4(buf: bytes, i: int) -> tuple[int, int]:
    """Lengths in this format are varints padded to 4 bytes."""
    return (_varint(buf[i:i + 5], 0)[0], i + 4)


def decode_htrace(buf: bytes) -> list[tuple[int, str]]:
    """Return [(timestamp_ns, "B|tid|H:section|...")] in file order."""
    n = len(buf)
    out: list[tuple[int, str]] = []
    i = 0
    while i < n - 6:
        if buf[i] != 0x12:
            i += 1
            continue
        size, start = _len4(buf, i + 1)
        end = start + size
        if size < 8 or size > 400_000 or end > n:
            i += 1
            continue
        p = start
        ts = None
        text = None
        while p < end:
            tag, p = _varint(buf, p)
            field, wire = tag >> 3, tag & 7
            if wire == 0:
                value, p = _varint(buf, p)
                if field == 1:
                    ts = value
            elif wire == 2:
                length, p2 = _varint(buf, p)
                if p2 + length > end:
                    p = end
                    break
                if field == 1109:
                    raw = buf[p2:p2 + length]
                    if raw[:1] == b'\x12':
                        inner_len, p3 = _varint(raw, 1)
                        text = raw[p3:p3 + inner_len].decode('utf-8', 'replace')
                p = p2 + length
            else:
                p = end
                break
        if text and ts is not None and text[:2] in ('B|', 'E|'):
            out.append((ts, text))
            i = end
        else:
            i += 1
    return out


def section_of(name: str) -> str:
    """Trace section name without its per-instance arguments."""
    return name.split('[')[0].split(',')[0].strip()


def complete_events(records: list[tuple[int, str]]) -> list[tuple[int, int, str, str]]:
    """Pair B/E records per thread -> [(start, duration, name, tid)].

    Records must be in timestamp order: the .htrace writers interleave packets
    from several threads, and pairing in raw file order mismatches a B with the
    E of a sibling section (inflating durations ~3x).
    """
    stacks: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    events = []
    for ts, text in sorted(records, key=lambda r: r[0]):
        parts = text.split('|')
        kind, tid = parts[0], parts[1]
        if kind == 'B':
            stacks[tid].append((ts, parts[2]))
        elif stacks[tid]:
            start, name = stacks[tid].pop()
            events.append((start, ts - start, name, tid))
    events.sort()
    return events


def overlap(spans: list[tuple[int, int]]) -> float:
    """Wall-clock coverage of a set of spans, so nested sections do not add up."""
    if not spans:
        return 0.0
    spans = sorted(spans)
    total = 0
    cs, ce = spans[0]
    for start, end in spans[1:]:
        if start > ce:
            total += ce - cs
            cs, ce = start, end
        else:
            ce = max(ce, end)
    return (total + ce - cs) / 1e9


# --------------------------------------------------------------------------- #
# ArkTS cpu profile
# --------------------------------------------------------------------------- #

def analyze_cpu(raw: bytes) -> dict:
    profile = json.loads(raw)
    nodes = {n['id']: n for n in profile['nodes']}
    parent: dict[int, int] = {}
    for n in profile['nodes']:
        for child in n.get('children', []):
            parent[child] = n['id']
    samples = profile.get('samples', [])
    deltas = profile.get('timeDeltas', [])
    total_us = sum(deltas) or 1

    def chain(sid: int) -> list[tuple[str, str]]:
        out = []
        while sid in nodes:
            frame = nodes[sid]['callFrame']
            out.append(((frame['functionName'] or '(anon)'),
                        (frame['url'] or '').split('/')[-1]))
            sid = parent.get(sid, -1)
        return out

    module_self = collections.Counter()
    inclusive = collections.Counter()
    for sid, delta in zip(samples, deltas):
        stack = chain(sid)
        if stack:
            module_self[stack[0][1] or '(program)'] += delta
        seen = set()
        for name, _file in stack:
            if name in CPU_WATCH and name not in seen:
                seen.add(name)
                inclusive[name] += delta

    return {
        'total_ms': total_us / 1000.0,
        'module_ms': {k: v / 1000.0 for k, v in module_self.most_common(10)},
        'inclusive_ms': {k: v / 1000.0 for k, v in inclusive.items()},
    }


# --------------------------------------------------------------------------- #
# state-variable ledger
# --------------------------------------------------------------------------- #

def analyze_state(db_path: Path) -> dict:
    db = sqlite3.connect(str(db_path))
    rows = db.execute("""
        select ifnull(component_name, '?'), ifnull(property_name, '?'), component_id,
               ifnull(value, ''), ifnull(effect_component_count, 0)
        from arkui_state_variable order by component_id, property_name, timestamp
    """).fetchall()
    if not rows:
        return {}
    vsyncs = db.execute("select count(distinct vsync_id) from arkui_state_variable").fetchone()[0] or 1

    previous: dict[tuple[int, str], str] = {}
    same = changed = same_eff = changed_eff = 0
    same_kind = collections.Counter()
    per_prop = collections.defaultdict(lambda: [0, 0, 0])   # writes, same, invalidations
    for comp, prop, cid, value, eff in rows:
        text = str(value)
        key = (cid, prop)
        bucket = per_prop[(comp, prop)]
        bucket[0] += 1
        bucket[2] += eff
        if key in previous and previous[key] == text:
            same += 1
            same_eff += eff
            bucket[1] += 1
            stripped = text.strip()
            kind = 'object' if stripped.startswith('{') else ('array' if stripped.startswith('[') else 'primitive')
            same_kind[kind] += eff
        else:
            changed += 1
            changed_eff += eff
        previous[key] = text

    total_eff = same_eff + changed_eff
    offenders = []
    for (comp, prop), (writes, dup, eff) in sorted(per_prop.items(), key=lambda kv: -kv[1][2])[:10]:
        # Arrays serialise as [] — a same-content share is meaningless there.
        offenders.append({
            'name': f'{comp}.{prop}', 'writes': writes, 'same': dup, 'invalidations': eff,
            'same_pct': round(100.0 * dup / writes, 1) if writes else 0.0,
            'array': measurand_is_array(db, comp, prop),
        })
    return {
        'writes': len(rows),
        'vsyncs': vsyncs,
        'writes_per_vsync': round(len(rows) / vsyncs, 2),
        'invalidations': total_eff,
        'invalidations_per_vsync': round(total_eff / vsyncs, 1),
        'same_writes': same,
        'same_pct': round(100.0 * same / len(rows), 1),
        'same_invalidations': same_eff,
        'same_invalidations_pct': round(100.0 * same_eff / total_eff, 1) if total_eff else 0.0,
        'same_by_kind': dict(same_kind),
        'top': offenders,
    }


def measurand_is_array(db: sqlite3.Connection, comp: str, prop: str) -> bool:
    row = db.execute("select value from arkui_state_variable where ifnull(component_name,'?')=? "
                     "and property_name=? and value like '[%' limit 1", (comp, prop)).fetchone()
    return row is not None


# --------------------------------------------------------------------------- #
# one dump
# --------------------------------------------------------------------------- #

def analyze(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive, tempfile.TemporaryDirectory() as tmp:
        names = archive.namelist()
        manifest = json.loads(archive.read('manifest.json'))
        pid = str(manifest['process']['pid'])
        htrace = next(n for n in names if n.endswith('.htrace'))
        state_db = next((n for n in names if n.endswith('_arkui_state_variable.db')), None)
        profile_name = next((n for n in names
                             if n.startswith('CPU-') and n.endswith(f'-{pid}.cpuprofile')), None)

        records = sorted(decode_htrace(archive.read(htrace)), key=lambda r: r[0])
        events = complete_events(records)
        span = (records[-1][0] - records[0][0]) / 1e9 if records else 0.0

        frames = [(s, d) for s, d, name, _tid in events if name.startswith('H:ProcessComposerFrame')]
        gaps = sorted((frames[i + 1][0] - frames[i][0]) / 1e6 for i in range(len(frames) - 1))

        app_spans = collections.defaultdict(list)
        counts = collections.Counter()
        for start, dur, name, tid in events:
            if tid != pid:
                continue
            key = section_of(name)
            app_spans[key].append((start, start + dur))
            counts[key] += 1

        result = {
            'meta': {
                'file': path.name,
                'device': manifest['device'].get('productName', ''),
                'api': manifest['device'].get('apiVersion', ''),
                'pid': pid,
                'window_s': round(manifest['time']['duration'] / 1e9, 2),
                'trace_s': round(span, 2),
            },
            'frames': {
                'count': len(frames),
                'fps': round(len(frames) / span, 1) if span else 0.0,
                'interval_median_ms': round(statistics.median(gaps), 2) if gaps else 0.0,
                'interval_p90_ms': round(gaps[int(0.90 * len(gaps))], 2) if gaps else 0.0,
                'interval_p99_ms': round(gaps[int(0.99 * len(gaps))], 2) if gaps else 0.0,
                'slow_count': sum(1 for g in gaps if g > 16.7),
                'slow_pct': round(100.0 * sum(1 for g in gaps if g > 16.7) / len(gaps), 1) if gaps else 0.0,
            },
            'main': {
                'busy_s': round(overlap([(s, s + d) for s, d, _n, t in events if t == pid]), 2),
                'busy_pct': round(100.0 * overlap([(s, s + d) for s, d, _n, t in events if t == pid]) / span, 1)
                if span else 0.0,
                'sections_s': {k: round(overlap(v), 2) for k, v in
                               sorted(app_spans.items(), key=lambda kv: -overlap(kv[1]))[:10]},
                'section_counts': dict(counts),
                'predict_avg_ms': round(1000.0 * overlap(app_spans.get('H:List predict v2', []))
                                        / max(1, counts.get('H:List predict v2', 0)), 2),
            },
            'rows': {
                'created': sum(1 for _s, _d, name, tid in events
                               if tid == pid and 'CallOnGetRid4Index' in name and 'CREATED_NEW_NODE' in name),
                'deleted': counts.get('H:aboutToBeDeleted', 0),
                'build_recycle': len([1 for _s, _d, name, tid in events
                                      if tid == pid and name.startswith('H:CustomNode:BuildRecycle')]),
                'build_recycle_avg_ms': round(statistics.mean(
                    [d for _s, d, name, tid in events
                     if tid == pid and name.startswith('H:CustomNode:BuildRecycle')]) / 1e6, 2)
                if any(name.startswith('H:CustomNode:BuildRecycle') for _s, _d, name, _t in events) else 0.0,
            },
            'scroll': {
                'flings': counts.get('H:Scrollable friction animation start', 0),
                'travel_vp': round(sum(float(name.split('initOffset:')[1].split(',')[0])
                                       for _s, _d, name, tid in events
                                       if tid == pid and name.startswith('H:HandleScroll')
                                       and 'initOffset:' in name), 0),
            },
        }

        if state_db:
            with open(Path(tmp) / 'state.db', 'wb') as handle:
                handle.write(archive.read(state_db))
            result['state'] = analyze_state(Path(tmp) / 'state.db')
        if profile_name:
            result['cpu'] = analyze_cpu(archive.read(profile_name))
    return result


# --------------------------------------------------------------------------- #
# printing
# --------------------------------------------------------------------------- #

def print_report(m: dict, frames: bool = False, event_rows=None) -> None:
    meta = m['meta']
    print(f"# {meta['file']}")
    print(f"# {meta['device']} / api {meta['api']} / pid {meta['pid']} / {meta['window_s']}s window")
    print()
    f = m['frames']
    print(f"composer frames   : {f['count']} in {meta['trace_s']}s ({f['fps']} fps)")
    print(f"frame interval ms : median {f['interval_median_ms']}  p90 {f['interval_p90_ms']}"
          f"  p99 {f['interval_p99_ms']}")
    print(f"frames > 16.7ms   : {f['slow_count']} ({f['slow_pct']}%)")
    print()
    mn = m['main']
    print(f"main-thread busy  : {mn['busy_s']}s / {meta['trace_s']}s = {mn['busy_pct']}%")
    for name, secs in mn['sections_s'].items():
        print(f'  {secs:7.2f}s  {name}')
    print()
    r = m['rows']
    print(f"row churn         : created {r['created']} / deleted {r['deleted']} / "
          f"BuildRecycle {r['build_recycle']} (avg {r['build_recycle_avg_ms']}ms)")
    s = m['scroll']
    print(f"scroll            : {s['flings']} flings, |offset| sum {s['travel_vp']:.0f}vp")
    print()
    st = m.get('state')
    if st:
        print(f"state writes      : {st['writes']} over {st['vsyncs']} vsyncs "
              f"({st['writes_per_vsync']}/vsync)")
        print(f"component invalid.: {st['invalidations']} ({st['invalidations_per_vsync']}/vsync)")
        print(f"same-content      : {st['same_writes']} ({st['same_pct']}%) -> "
              f"{st['same_invalidations']} invalid. ({st['same_invalidations_pct']}%)")
        print(f'  {"writes":>7}{"same":>8}{"invalid":>9}  component.property')
        for o in st['top']:
            dup = '   n/a' if o['array'] else f"{o['same_pct']:6.0f}%"
            print(f"  {o['writes']:>7}{dup:>8}{o['invalidations']:>9}  {o['name']}")
        print()
    cpu = m.get('cpu')
    if cpu:
        print(f"arkts samples     : {cpu['total_ms']:.0f}ms")
        for name, ms in list(cpu['module_ms'].items())[:6]:
            print(f'  {ms:7.0f}ms  self  {name}')
        for name in CPU_WATCH:
            if name in cpu['inclusive_ms']:
                print(f"  {cpu['inclusive_ms'][name]:7.0f}ms  incl  {name}")
        print()
    if frames and event_rows:
        print(f'{"t(s)":>7}{"interval_ms":>13}{"dur_ms":>9}')
        base = event_rows[0][0]
        for i, (start, dur) in enumerate(event_rows):
            gap = (start - event_rows[i - 1][0]) / 1e6 if i else 0.0
            print(f'{(start - base) / 1e9:7.2f}{gap:13.2f}{dur / 1e6:9.2f}')


ROWS = [
    ('帧中位间隔', ('frames', 'interval_median_ms'), 'ms', False),
    ('帧 p90', ('frames', 'interval_p90_ms'), 'ms', True),
    ('>16.7ms 帧占比', ('frames', 'slow_pct'), '%', True),
    ('主线程 busy', ('main', 'busy_pct'), '%', True),
    ('List predict v2', ('main', 'sections_s', 'H:List predict v2'), 's', True),
    ('predict 单次', ('main', 'predict_avg_ms'), 'ms', True),
    ('ExecuteJS', ('main', 'sections_s', 'H:ExecuteJS'), 's', True),
    ('行构建 BuildRecycle', ('main', 'sections_s', 'H:CustomNode:BuildRecycle'), 's', True),
    ('BuildRecycle 单行', ('rows', 'build_recycle_avg_ms'), 'ms', True),
    ('state writes/vsync', ('state', 'writes_per_vsync'), '', True),
    ('组件失效/vsync', ('state', 'invalidations_per_vsync'), '', True),
    ('同内容写占比', ('state', 'same_pct'), '%', True),
    ('同内容引发的失效', ('state', 'same_invalidations_pct'), '%', True),
    ('reuse 重置总耗时', ('cpu', 'inclusive_ms', 'resetStateVarsOnReuse'), 'ms', True),
    ('组件创建 observe', ('cpu', 'inclusive_ms', 'observeComponentCreation2'), 'ms', True),
    ('stateMgmt 自耗时', ('cpu', 'module_ms', 'stateMgmt.js'), 'ms', True),
    ('profiler getHash', ('cpu', 'module_ms', 'util_js.js'), 'ms', True),
]

# 归一化指标：两次录制的滚动时长/行数不同，绝对值不可直接比。
NORMALIZED = [
    ('写次数/行', lambda m: m['state']['writes'] / m['rows']['build_recycle'], '', True),
    ('组件失效/行', lambda m: m['state']['invalidations'] / m['rows']['build_recycle'], '', True),
    ('reuse 重置/行', lambda m: m['cpu']['inclusive_ms'].get('resetStateVarsOnReuse', 0)
     / m['rows']['build_recycle'], 'ms', True),
    ('组件创建/行', lambda m: m['cpu']['inclusive_ms'].get('observeComponentCreation2', 0)
     / m['rows']['build_recycle'], 'ms', True),
]


def pick(metrics: dict, path: tuple):
    node = metrics
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return None
        node = node[key]
    return node


def pad(text: str, width: int, right: bool = True) -> str:
    cells = sum(2 if unicodedata.east_asian_width(ch) in 'WF' else 1 for ch in text)
    gap = max(0, width - cells)
    return (' ' * gap + text) if right else (text + ' ' * gap)


def print_compare(base: dict, new: dict) -> None:
    print(f"baseline : {base['meta']['file']}")
    print(f"new      : {new['meta']['file']}")
    print()
    print(pad('metric', 20, False) + pad('baseline', 11) + pad('new', 11) + pad('delta', 11)
          + '   verdict')
    for label, path, unit, lower_better in ROWS:
        b = pick(base, path)
        n = pick(new, path)
        if b is None or n is None:
            continue
        delta = n - b
        pct = (100.0 * delta / b) if b else 0.0
        if abs(pct) < 5:
            verdict = '持平'
        elif (pct < 0) == lower_better:
            verdict = '↓ 更好' if delta < 0 else '↑ 更好'
        else:
            verdict = '↓ 变差' if delta < 0 else '↑ 变差'
        print(pad(label, 20, False) + pad(f'{b:.2f}', 11) + pad(f'{n:.2f}', 11)
              + pad(f'{delta:+.2f}', 11) + f'   {verdict} {pct:+.0f}%')
    print()
    print(pad('归一化（每行）', 20, False) + pad('baseline', 11) + pad('new', 11) + pad('delta', 11)
          + '   verdict')
    for label, fn, unit, lower_better in NORMALIZED:
        try:
            b, n = fn(base), fn(new)
        except (KeyError, TypeError, ZeroDivisionError):
            continue
        delta = n - b
        pct = (100.0 * delta / b) if b else 0.0
        if abs(pct) < 5:
            verdict = '持平'
        elif (pct < 0) == lower_better:
            verdict = '↓ 更好' if delta < 0 else '↑ 更好'
        else:
            verdict = '↓ 变差' if delta < 0 else '↑ 变差'
        print(pad(label, 20, False) + pad(f'{b:.2f}', 11) + pad(f'{n:.2f}', 11)
              + pad(f'{delta:+.2f}', 11) + f'   {verdict} {pct:+.0f}%')
    print()
    for title in ('state', 'cpu'):
        bs, ns = base.get(title), new.get(title)
        if not bs or not ns:
            continue
        print(f'--- {title}: 前 5 项 ---')
        if title == 'state':
            for o in bs['top'][:5]:
                print(f"  base  {o['invalidations']:>7}  {o['name']}")
            for o in ns['top'][:5]:
                print(f"  new   {o['invalidations']:>7}  {o['name']}")
        else:
            for name in CPU_WATCH:
                b = bs['inclusive_ms'].get(name)
                n = ns['inclusive_ms'].get(name)
                if b is None and n is None:
                    continue
                print(f'  {name:34} base {b if b is not None else "-":>8}'
                      f'   new {n if n is not None else "-":>8}')
        print()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('insight', type=Path)
    parser.add_argument('--frames', action='store_true', help='print per-frame table')
    parser.add_argument('--json', action='store_true', help='dump metrics as JSON')
    parser.add_argument('--save', type=Path, help='write metrics JSON here')
    parser.add_argument('--against', type=Path,
                        help='compare against a .insight dump or a --save JSON')
    args = parser.parse_args(argv)

    new = json.loads(args.insight.read_text()) if args.insight.suffix == '.json' \
        else analyze(args.insight)
    if args.save:
        args.save.write_text(json.dumps(new, indent=2, ensure_ascii=False))
        print(f'saved {args.save}')

    if args.against:
        if args.against.suffix == '.json':
            base = json.loads(args.against.read_text())
        else:
            base = analyze(args.against)
        print_compare(base, new)
        return 0

    if args.json:
        print(json.dumps(new, indent=2, ensure_ascii=False))
        return 0

    frame_rows = None
    if args.frames:
        with zipfile.ZipFile(args.insight) as archive:
            name = next(n for n in archive.namelist() if n.endswith('.htrace'))
            records = sorted(decode_htrace(archive.read(name)), key=lambda r: r[0])
        frame_rows = [(s, d) for s, d, nm, _t in complete_events(records)
                      if nm.startswith('H:ProcessComposerFrame')]
    print_report(new, args.frames, frame_rows)
    return 0


if __name__ == '__main__':
    # 允许 `... --frames | head`：不然管道被关掉时 Python 会以 120 退出并刷一条
    # BrokenPipeError（内容本身是对的，只是收尾难看）。
    if hasattr(signal, 'SIGPIPE'):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raise SystemExit(main(sys.argv[1:]))

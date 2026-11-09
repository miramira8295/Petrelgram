#!/usr/bin/env python3
"""Drive a fixed scroll gesture and read the in-app RowProbe counters from hilog.

Why: a DevEco *Insight* recording made by hand has ~25% run-to-run noise on the
row-pipeline metrics (measured 2026-11-09: 22.9 vs 25.2 invalidations/row, p90
9.6 vs 15.7ms on the *same* build). This script removes the human from both ends:

  * the gesture is the same sequence of `dircfling` calls every run;
  * the metric comes from the app's own probe (`util/rowProbe.ets`), which logs
    one line per 60 vsyncs — no profiler attached, no state-recording overhead.

Metrics per 0.5s window (RowProbe resets its counters on every line):
  row   rows built            -> rows/s   = row * 2
  max   peak rows per frame
  prep  prepareMessageBubble ms
  prepares  number of prepare calls

Usage:
    scripts/chat-bench.py                       # 12 flings up, 800ms apart
    scripts/chat-bench.py --flings 16 --interval 600 --direction down
    scripts/chat-bench.py --runs 3              # median of 3 runs

Requires: the app open on a chat page, device unlocked, `devecocli` on PATH.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

PROBE = re.compile(r'RowProbe:? f=(\d+) row=(\d+) max=(\d+) prep=(\d+) prepares=(\d+)')


def find_hdc() -> str:
    candidates = [
        Path.home() / 'Library/OpenHarmony/Sdk',
        Path('/Applications/DevEco-Studio.app/Contents/sdk'),
    ]
    for root in candidates:
        if not root.exists():
            continue
        for path in sorted(root.glob('**/toolchains/hdc')):
            if path.is_file():
                return str(path)
    return 'hdc'


def header_title(device: str | None) -> str:
    """当前会话标题；只有在聊天页才拿得到（列表页首行也会落在同一 y 区间）。

    判据：聊天页的标题下方一定跟着"9.3K 位成员，485 人在线"这种副标题。
    """
    cmd = ['devecocli', 'ui', 'layout', '--format', 'json']
    if device:
        cmd += ['--device', device]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    start = out.find('[')
    if start < 0:
        return ''
    tree = json.loads(out[start:])
    titles: list[str] = []
    has_subtitle = False
    def walk(node):
        nonlocal has_subtitle
        if isinstance(node, list):
            for item in node:
                walk(item)
            return
        text = node.get('text') or ''
        y = node.get('bounds', [0, 0, 0, 0])[1]
        if '位成员' in text or '在线' in text:
            has_subtitle = True
        if text and y < 400 and not (node.get('bounds', [0, 0, 0, 0])[0] < 200):
            titles.append(text)
        for child in node.get('children', []):
            walk(child)
    walk(tree)
    if not has_subtitle:
        return ''
    return titles[0] if titles else ''


def dump_probe(hdc: str) -> list[str]:
    """Non-blocking dump of the buffer, filtered to the RowProbe tag.

    Streaming + kill loses hdc's stdio buffer, so the gesture is followed by a
    one-shot `-x` dump instead; the buffer is cleared right before the gesture
    so the dump only contains this run.
    """
    out = subprocess.run([hdc, 'shell', 'hilog', '-x', '-T', 'RowProbe'],
                         capture_output=True, text=True, timeout=30)
    return out.stdout.splitlines()


def fling(device: str, direction: str, interval_ms: int, count: int) -> None:
    for _ in range(count):
        subprocess.run(['devecocli', 'ui', 'dircfling', direction, '--device', device],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        time.sleep(interval_ms / 1000.0)


def parse(lines: list[str]) -> list[dict]:
    windows = []
    for line in lines:
        m = PROBE.search(line)
        if not m:
            continue
        f, row, mx, prep, prepares = (int(x) for x in m.groups())
        windows.append({'frames': f, 'row': row, 'max': mx, 'prep': prep, 'prepares': prepares})
    return windows


def summarise(windows: list[dict], label: str) -> dict:
    if not windows:
        print(f'{label}: 没有 RowProbe 数据（应用没在前台？或没滚动）', file=sys.stderr)
        return {}
    rows = [w['row'] for w in windows]
    preps = [w['prep'] for w in windows]
    prepares = sum(w['prepares'] for w in windows)
    total_row = sum(rows)
    result = {
        'label': label,
        'windows': len(windows),
        'rows_per_s': round(statistics.median(rows) * 2, 1),
        'rows_total': total_row,
        'max_rows_per_frame': max(w['max'] for w in windows),
        'prep_ms_per_s': round(statistics.median(preps) * 2, 2),
        'prep_ms_per_row': round(sum(preps) / max(1, prepares), 3),
        'prepares_per_row': round(prepares / max(1, total_row), 2),
    }
    return result


def print_result(r: dict) -> None:
    if not r:
        return
    print(f"# {r['label']}")
    print(f"  窗口数（0.5s/窗）   : {r['windows']}")
    print(f"  建行速度            : {r['rows_per_s']}/s（中位），共 {r['rows_total']} 行")
    print(f"  单帧峰值建行        : {r['max_rows_per_frame']}")
    print(f"  prepare 时间        : {r['prep_ms_per_s']} ms/s")
    print(f"  prepare 单行        : {r['prep_ms_per_row']} ms/行")
    print(f"  prepare 次数/行     : {r['prepares_per_row']}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--device', default=None, help='设备 serial（只连一台可省略）')
    parser.add_argument('--flings', type=int, default=12, help='甩动次数')
    parser.add_argument('--interval', type=int, default=800, help='两次甩动间隔 ms')
    parser.add_argument('--direction', default='up', choices=['up', 'down'])
    parser.add_argument('--runs', type=int, default=1, help='重复几轮，输出中位')
    parser.add_argument('--settle', type=int, default=1500, help='开始前的静置 ms')
    parser.add_argument('--out', type=Path, help='原始 hilog 存这里')
    parser.add_argument('--expect-chat', default=None,
                        help='开测前校验当前会话标题（子串）；不匹配就中止，避免测到别的群')
    args = parser.parse_args(argv)

    hdc = find_hdc()
    device = args.device
    if device is None:
        # `hdc list targets` 一行一个 serial，比解析 `devecocli device list` 的表格
        # 可靠（那张表的名字列含空格，按空格取第 2 列会拿到 "Mate"）。
        out = subprocess.run([hdc, 'list', 'targets'], capture_output=True, text=True).stdout
        serials = [line.strip() for line in out.splitlines()
                   if line.strip() and 'Empty' not in line]
        if len(serials) != 1:
            print(f'需要 --device（可用目标：{serials}）', file=sys.stderr)
            return 2
        device = serials[0]

    results = []
    for run in range(args.runs):
        label = f'run{run + 1}' if args.runs > 1 else 'run'
        if args.expect_chat:
            title = header_title(device)
            if title == '' or args.expect_chat not in title:
                print(f'当前不在 {args.expect_chat!r}（标题={title!r}），中止本轮', file=sys.stderr)
                return 3
            print(f'  会话校验通过：{title}')
        subprocess.run([hdc, 'shell', 'hilog', '-r'], capture_output=True, timeout=30)
        time.sleep(args.settle / 1000.0)
        fling(device, args.direction, args.interval, args.flings)
        time.sleep(1.5)
        lines = dump_probe(hdc)
        windows = parse(lines)
        result = summarise(windows, f'{label} ({args.flings} flings {args.direction})')
        print_result(result)
        if result:
            results.append(result)
        if args.out:
            args.out.write_text('\n'.join(lines))
            print(f'  原始日志 -> {args.out}')
        print()

    if len(results) > 1:
        print('# 多轮中位')
        for key in ('rows_per_s', 'prep_ms_per_row', 'prepares_per_row', 'max_rows_per_frame'):
            values = [r[key] for r in results]
            print(f'  {key:20}: {statistics.median(values)}  (各轮 {values})')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Open a chat by name instead of by pixel coordinates.

Why: clicking the chat list by a hard-coded y coordinate breaks the moment a
new message reorders the list — during the 2026-11-09 benchmarks that silently
opened the wrong chat and made two runs non-comparable. The accessibility layout
tree carries the visible text, so match the row by name and click the centre of
its bounds.

Usage:
    scripts/open-chat.py "小白鸿蒙交流群"
    scripts/open-chat.py 小白 --device 3EV0224B16014691 --index 0

`--index` picks the n-th match (0 = first) when several rows contain the name.
Exit code 0 means the click was dispatched; verify with `devecocli ui layout`.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time


def layout_tree(device: str | None) -> dict:
    cmd = ['devecocli', 'ui', 'layout', '--format', 'json']
    if device:
        cmd += ['--device', device]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    start = out.find('[')
    if start < 0:
        raise RuntimeError(f'no layout json in output: {out[:200]}')
    return json.loads(out[start:])


def walk(node):
    if isinstance(node, list):
        for item in node:
            yield from walk(item)
        return
    yield node
    for child in node.get('children', []):
        yield from walk(child)


def find_matches(tree, needle: str, rows_only: bool = False) -> list[dict]:
    hits = []
    for node in walk(tree):
        text = node.get('text') or node.get('description') or ''
        if needle in text:
            # 会话行在列表里、y 在头部区域以下；标题栏里的同名文本是"已经在这个会话里"。
            if rows_only and node.get('bounds', [0, 0, 0, 0])[1] < 400:
                continue
            hits.append(node)
    return hits


def in_chat(tree, needle: str) -> bool:
    """头部出现该名字 = 已经进了这个会话。"""
    for node in walk(tree):
        text = node.get('text') or node.get('description') or ''
        if needle in text and node.get('bounds', [0, 0, 0, 0])[1] < 400:
            return True
    return False


def centre(bounds: list[int]) -> tuple[int, int]:
    left, top, right, bottom = bounds
    return (left + right) // 2, (top + bottom) // 2


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('name', help='聊天名（子串匹配）')
    parser.add_argument('--device', default=None)
    parser.add_argument('--index', type=int, default=0, help='第几个匹配（默认 0）')
    parser.add_argument('--dry-run', action='store_true', help='只打印候选，不点击')
    parser.add_argument('--scroll', type=int, default=0,
                        help='找不到时往下翻几次（会话列表按时间排序，冷启动后目标常在折叠线以下）')
    args = parser.parse_args(argv)

    tree = layout_tree(args.device)
    if in_chat(tree, args.name):
        print(f'已经在 {args.name!r} 里')
        return 0
    hits = find_matches(tree, args.name, rows_only=True)
    for _ in range(args.scroll):
        if hits:
            break
        cmd = ['devecocli', 'ui', 'dircfling', 'down']
        if args.device:
            cmd += ['--device', args.device]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        time.sleep(0.8)
        tree = layout_tree(args.device)
        hits = find_matches(tree, args.name, rows_only=True)
    if not hits:
        print(f'没找到包含 {args.name!r} 的节点', file=sys.stderr)
        return 1
    for i, node in enumerate(hits[:5]):
        print(f'  [{i}] {node.get("type"):14} {node.get("bounds")} '
              f'{(node.get("text") or node.get("description") or "")[:36]!r}')
    if args.dry_run:
        return 0
    if args.index >= len(hits):
        print(f'--index {args.index} 越界（命中 {len(hits)} 个）', file=sys.stderr)
        return 1

    x, y = centre(hits[args.index]['bounds'])
    cmd = ['devecocli', 'ui', 'click', str(x), str(y)]
    if args.device:
        cmd += ['--device', args.device]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    print(f'clicked ({x}, {y}) for {args.name!r}')
    time.sleep(2.0)
    if in_chat(layout_tree(args.device), args.name):
        print('opened')
        return 0
    print('点击后没有进入目标会话', file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))

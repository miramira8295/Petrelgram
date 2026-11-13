#!/usr/bin/env python3
"""Compare real-device fixture PNGs. Never creates or approves a baseline.
Requires Pillow: python -m pip install Pillow
Inputs: baseline/current folders with environment.json and <case-id>.png.
Run: python scripts/drawn-golden.py BASE CURRENT --output RESULT
"""
import argparse
import json
import re
from pathlib import Path
from PIL import Image, ImageChops


def compare(baseline, current, output, cases, tolerance=2):
    ids = [case['id'] for case in cases]
    if not ids or len(set(ids)) != len(ids) or any(not re.fullmatch(r'[a-z][a-z0-9-]*', name) for name in ids):
        raise ValueError('empty, duplicate or invalid fixture ids')
    # Fail closed on mismatched/missing device, density, font or renderer config.
    a = json.loads((baseline / 'environment.json').read_text())
    b = json.loads((current / 'environment.json').read_text())
    for key in ['device', 'os', 'resolution', 'density', 'fontScale', 'font', 'theme', 'language', 'renderer', 'timezone', 'renderOptions']:
        if key not in a or key not in b or a[key] != b[key]:
            raise ValueError(f'environment mismatch/missing: {key}')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for case in cases:
        name = case['id']
        with Image.open(baseline / f'{name}.png') as image:
            before = image.convert('RGBA')
        with Image.open(current / f'{name}.png') as image:
            after = image.convert('RGBA')
        if before.size != after.size:
            results.append({'id': name, 'pass': False, 'reason': 'size', 'before': before.size, 'after': after.size})
            continue
        # Capture only the fixture component, excluding clocks/status/navigation.
        diff = ImageChops.difference(before, after)
        maximum = diff.getchannel('R')
        for channel in ['G', 'B', 'A']:
            maximum = ImageChops.lighter(maximum, diff.getchannel(channel))
        mask = maximum.point(lambda v: 255 if v > tolerance else 0)
        bad = mask.histogram()[255]
        results.append({'id': name, 'pass': bad == 0, 'differentPixels': bad, 'pixels': before.width * before.height,
                        'maxChannelDelta': maximum.getextrema()[1]})
        if bad:
            # Save the exact magnitude and a high-contrast location mask.
            diff.save(output / f'{name}-diff.png')
            mask.save(output / f'{name}-mask.png')
    report = {'pass': all(item['pass'] for item in results), 'tolerance': tolerance, 'cases': results}
    (output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('current', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('drawn-golden-cases.json'))
    parser.add_argument('--tolerance', type=int, default=2)
    args = parser.parse_args()
    if not 0 <= args.tolerance <= 16:
        parser.error('tolerance must be 0..16; large tolerances hide seams/baselines')
    report = compare(args.baseline, args.current, args.output, json.loads(args.manifest.read_text())['cases'], args.tolerance)
    print(f"DRAWN PIXELS: {'PASS' if report['pass'] else 'FAIL'} ({len(report['cases'])} cases)")
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Summarize nativehook snapshots separately; never sum periodic snapshots.

Input: trace_streamer SQLite output. Reports native allocation events, NOT
paragraph counts, object counts, leaks, GC duration or frame performance.
"""
import argparse
import collections
import json
import sqlite3
from pathlib import Path


def analyze(path):
    with sqlite3.connect(path) as db:
        db.row_factory = sqlite3.Row
        names = dict(db.execute('SELECT id, data FROM data_dict'))
        latest = {}
        for row in db.execute('SELECT * FROM native_hook_statistic ORDER BY ts, id'):
            key = (row['ipid'], row['callchain_id'], row['type'], row['sub_type_id'])
            previous = latest.get(key)
            # Fully released chains may reset. These are snapshot counters,
            # not safely additive session totals.
            latest[key] = dict(row)
        if not latest:
            raise ValueError('No nativehook statistic records; check capture configuration')
        frames = collections.defaultdict(list)
        for row in db.execute('SELECT * FROM native_hook_frame ORDER BY depth'):
            frames[row['callchain_id']].append({'symbol': names.get(row['symbol_id'], ''), 'file': names.get(row['file_id'], '')})
        final_ts = max(row['ts'] for row in latest.values())
        totals = collections.defaultdict(lambda: [0, 0, 0, 0])
        for row in latest.values():
            if row['ts'] != final_ts:
                continue
            js = [frame for frame in frames[row['callchain_id']] if '.ts:' in frame['file'] or '.ts:' in frame['symbol']]
            if not js:
                continue
            leaf = js[-1]
            key = (row['ipid'], leaf['symbol'] + ' ' + leaf['file'])
            for i, field in enumerate(('apply_count', 'release_count', 'apply_size', 'release_size')):
                totals[key][i] += row[field]
        sites = sorted([dict(ipid=k[0], site=k[1], allocations=v[0], releases=v[1], bytes=v[2], released_bytes=v[3])
                        for k, v in totals.items()], key=lambda x: x['allocations'], reverse=True)
        return {'counter_mode': 'final timestamp snapshot only; counters may reset after complete release; NOT session totals',
                'snapshot_ts': final_ts,
                'processes': [dict(row) for row in db.execute('SELECT ipid, pid, name FROM process')],
                'sites': sites, 'chains': [{**row, 'frames': frames[row['callchain_id']]} for row in latest.values()]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = analyze(args.database)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result['sites'][:12], indent=2, ensure_ascii=False))

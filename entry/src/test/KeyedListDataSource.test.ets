import { describe, it, expect } from '@ohos/hypium';
import { KeyedListDataSource } from '../main/ets/pages/common/KeyedListDataSource';

// 通用 LazyForEach 数据源（联系人等列表共用）。钉住的规则与首页会话列表一致：
//   追加 / 前插 / 删除 → 增量 ADD/DELETE；重排 → RELOAD；只改内容 → 只对那几行 CHANGE。

interface Row {
  id: number;
  label: string;
}

function rows(list: number[]): Row[] {
  return list.map((id: number): Row => {
    const r: Row = { id: id, label: `r${id}` };
    return r;
  });
}

function idsOf(list: number[]): string[] {
  return list.map((id: number): string => `${id}`);
}

// 默认按 id 生成 key；bump 让某一行在身份不变的前提下换一个内容签名。
function keysOf(list: number[], bump: number = -1): string[] {
  return list.map((id: number): string => id === bump ? `k${id}_v2` : `k${id}`);
}

class Recording implements DataChangeListener {
  batches: string[] = [];
  addedKeys: string[] = [];
  changedIndexes: number[] = [];
  deleted: number[] = [];
  onDataReloaded(): void {}
  onDataAdd(_index: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDelete(_index: number): void {}
  onDataChange(_index: number): void {}
  onDataAdded(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDatasetChange(operations: DataOperation[]): void {
    const kinds: string[] = [];
    for (const op of operations) {
      if (op.type === DataOperationType.ADD) {
        kinds.push('add');
        const k = (op as DataAddOperation).key;
        if (k !== undefined) {
          for (const one of k as string[]) {
            this.addedKeys.push(one);
          }
        }
      } else if (op.type === DataOperationType.DELETE) {
        kinds.push('delete');
        this.deleted.push((op as DataDeleteOperation).count ?? 0);
      } else if (op.type === DataOperationType.CHANGE) {
        kinds.push('change');
        this.changedIndexes.push((op as DataChangeOperation).index);
      } else if (op.type === DataOperationType.RELOAD) {
        kinds.push('reload');
      }
    }
    this.batches.push(kinds.join(','));
  }
}

function seeded(list: number[]): KeyedListDataSource<Row> {
  const ds = new KeyedListDataSource<Row>('test');
  ds.update(rows(list), idsOf(list), keysOf(list));
  return ds;
}

export default function keyedListDataSourceTest() {
  describe('KeyedListDataSource', () => {
    it('首次灌数据是一次 ADD，带齐全部 key', 0, () => {
      const ds = new KeyedListDataSource<Row>('test');
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([1, 2, 3]), idsOf([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('k1,k2,k3');
      expect(ds.totalCount()).assertEqual(3);
      expect(ds.getData(1).id).assertEqual(2);
    });

    it('追加一页只发 ADD，不整表 RELOAD', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([1, 2, 3, 4, 5]), idsOf([1, 2, 3, 4, 5]), keysOf([1, 2, 3, 4, 5]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('k4,k5');
    });

    it('删除中间一条只发 DELETE', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([1, 3]), idsOf([1, 3]), keysOf([1, 3]));
      expect(rec.batches.join('|')).assertEqual('delete');
      expect(rec.deleted.join(',')).assertEqual('1');
    });

    it('清空是一次 DELETE', 0, () => {
      const ds = seeded([1, 2]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update([], [], []);
      expect(rec.batches.join('|')).assertEqual('delete');
      expect(rec.deleted.join(',')).assertEqual('2');
    });

    it('重排是 RELOAD——同一下标换了身份，不能报 CHANGE', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([3, 1, 2]), idsOf([3, 1, 2]), keysOf([3, 1, 2]));
      expect(rec.batches.join('|')).assertEqual('reload');
    });

    it('身份不变、只有内容变：只对那一行发 CHANGE', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([1, 2, 3]), idsOf([1, 2, 3]), keysOf([1, 2, 3], 2));
      expect(rec.batches.join('|')).assertEqual('change');
      expect(rec.changedIndexes.join(',')).assertEqual('1');
    });

    it('什么都没变：不发任何通知', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([1, 2, 3]), idsOf([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.length).assertEqual(0);
    });

    it('前插的同时尾部幸存行内容变了：先 ADD，再按新下标 CHANGE', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(rows([0, 1, 2, 3]), idsOf([0, 1, 2, 3]), keysOf([0, 1, 2, 3], 3));
      expect(rec.batches.join('|')).assertEqual('add|change');
      expect(rec.addedKeys.join(',')).assertEqual('k0');
      expect(rec.changedIndexes.join(',')).assertEqual('3');
    });

    it('isFresh：新出现的身份在窗口内算新到，过了窗口就不算', 0, () => {
      let clock: number = 1000;
      const ds = new KeyedListDataSource<Row>('test', (): number => clock);
      ds.update(rows([1, 2]), idsOf([1, 2]), keysOf([1, 2]));
      expect(ds.isFresh('1')).assertTrue();
      clock += 601;
      expect(ds.isFresh('1')).assertFalse();
    });

    it('isFresh：追加的行算新到，只改内容的幸存行不算', 0, () => {
      let clock: number = 1000;
      const ds = new KeyedListDataSource<Row>('test', (): number => clock);
      ds.update(rows([1, 2, 3]), idsOf([1, 2, 3]), keysOf([1, 2, 3]));
      clock += 1000;
      ds.update(rows([1, 2, 3, 4]), idsOf([1, 2, 3, 4]), keysOf([1, 2, 3, 4], 2));
      expect(ds.isFresh('4')).assertTrue();
      expect(ds.isFresh('2')).assertFalse();
    });

    it('isFresh：重排和删除不产生新到，也不续上一次的窗口', 0, () => {
      let clock: number = 1000;
      const ds = new KeyedListDataSource<Row>('test', (): number => clock);
      ds.update(rows([1, 2, 3]), idsOf([1, 2, 3]), keysOf([1, 2, 3]));
      clock += 1000;
      ds.update(rows([3, 1, 2]), idsOf([3, 1, 2]), keysOf([3, 1, 2]));
      ds.update(rows([3, 1]), idsOf([3, 1]), keysOf([3, 1]));
      expect(ds.isFresh('1')).assertFalse();
      expect(ds.isFresh('3')).assertFalse();
    });
  });
}

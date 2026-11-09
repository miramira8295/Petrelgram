import { describe, expect, it } from '@ohos/hypium';
import { coalesceKeyOf } from '../main/ets/tdkit/tdUpdateFilter';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function updateFileOf(id: number | undefined): TdObject {
  const file: Record<string, Object> = {};
  if (id !== undefined) {
    file['id'] = id;
  }
  const u: Record<string, Object> = { '@type': 'updateFile' };
  u['file'] = file;
  return u;
}

export default function tdUpdateFilterTest() {
  describe('tdUpdateFilter', () => {
    it('updateFile 按 file.id 合并', 0, (): void => {
      expect(coalesceKeyOf(updateFileOf(123))).assertEqual('file:123');
      expect(coalesceKeyOf(updateFileOf(456))).assertEqual('file:456');
    });
    it('缺 id 或缺 file 的 updateFile 直通', 0, (): void => {
      expect(coalesceKeyOf(updateFileOf(undefined))).assertEqual('');
      const noFile: Record<string, Object> = { '@type': 'updateFile' };
      expect(coalesceKeyOf(noFile)).assertEqual('');
    });
    it('其他更新一律直通（顺序语义是铁律）', 0, (): void => {
      const newMsg: Record<string, Object> = { '@type': 'updateNewMessage' };
      expect(coalesceKeyOf(newMsg)).assertEqual('');
      // 响应对象（带 @extra 的 file）也直通：@type 是 file 不是 updateFile。
      const response: Record<string, Object> = { '@type': 'file' };
      response['@extra'] = 'req_1';
      expect(coalesceKeyOf(response)).assertEqual('');
    });
  });
}

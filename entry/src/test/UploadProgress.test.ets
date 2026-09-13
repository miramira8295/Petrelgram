import { describe, it, expect } from '@ohos/hypium';
import { uploadPercentOf } from '../main/ets/util/uploadProgress';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function fileWith(size: number, remote: TdObject | undefined): TdObject {
  const f: TdObject = { '@type': 'file' };
  f['id'] = 1; f['size'] = size; f['expected_size'] = size;
  if (remote !== undefined) { f['remote'] = remote; }
  return f;
}
function remote(active: boolean, uploaded: number, completed: boolean = false): TdObject {
  const r: TdObject = { '@type': 'remoteFile' };
  r['is_uploading_active'] = active; r['uploaded_size'] = uploaded; r['is_uploading_completed'] = completed;
  return r;
}

export default function uploadProgressTest(): void {
  describe('uploadProgress', (): void => {
    it('上传中：uploaded_size / size 取整百分比', 0, (): void => {
      expect(uploadPercentOf(fileWith(1000, remote(true, 456)))).assertEqual(45);
    });
    it('不在上传（没有 remote / is_uploading_active=false）→ -1', 0, (): void => {
      expect(uploadPercentOf(fileWith(1000, undefined))).assertEqual(-1);
      expect(uploadPercentOf(fileWith(1000, remote(false, 0)))).assertEqual(-1);
    });
    it('上传完成 → 100，即使 uploaded_size 没跟上', 0, (): void => {
      expect(uploadPercentOf(fileWith(1000, remote(false, 10, true)))).assertEqual(100);
    });
    it('总大小未知 → 0（转圈而不是乱算）；越界夹到 0–100', 0, (): void => {
      expect(uploadPercentOf(fileWith(0, remote(true, 500)))).assertEqual(0);
      expect(uploadPercentOf(fileWith(100, remote(true, 5000)))).assertEqual(100);
    });
  });
}

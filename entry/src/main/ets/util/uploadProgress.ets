import { TdObject } from '../tdkit/TdTypes';

// 出站文件的上传进度（issue #201 第 6 条）。
//
// 下载进度在 file.local（downloaded_size），上传进度在 **file.remote**：
// is_uploading_active / uploaded_size / is_uploading_completed。出站文件的
// local 一上来就是"已下载完成"（它本来就在本机），所以只看 local 永远算不出
// 发送进度——这就是发送中的文件和发完的长得一模一样的原因。
//
// 返回 -1 = 这个文件此刻不在上传（调用方什么都不做）；0–100 = 上传百分比。
export function uploadPercentOf(file: TdObject): number {
  const remote = file['remote'] as TdObject | undefined;
  if (remote === undefined) {
    return -1;
  }
  if ((remote['is_uploading_completed'] as boolean | undefined) ?? false) {
    return 100;
  }
  if (!((remote['is_uploading_active'] as boolean | undefined) ?? false)) {
    return -1;
  }
  const size: number = ((file['size'] as number | undefined) ?? 0) ||
    ((file['expected_size'] as number | undefined) ?? 0);
  const uploaded: number = (remote['uploaded_size'] as number | undefined) ?? 0;
  if (size <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.floor((uploaded / size) * 100)));
}

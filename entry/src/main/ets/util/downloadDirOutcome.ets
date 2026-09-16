// 「默认下载路径」点一下之后到底发生了什么，以及该给用户什么提示。
//
// 2026-09-16 用户反馈「有些人点了没反应」。#189 那次（09-13 修、随 1.4.8-pv1 发布）修掉的是「能力位不支持就直接
// 什么都不做」，但还剩两条仍然静默：
//   ① 选择器返回空数组、又不是用户取消——系统自己把选择器关掉了，界面上什么都没发生；
//   ② 选择器的 Promise 迟迟不回，设置页那一行一直转圈且不可点，之后再点都没反应。
// 前者在这里给出提示，后者由页面侧的看门狗兜底。用户主动取消**不提示**：那是他自己的操作。
export const DOWNLOAD_DIR_CHANGED: string = 'changed';
export const DOWNLOAD_DIR_CANCELLED: string = 'cancelled';
export const DOWNLOAD_DIR_EMPTY: string = 'empty';
export const DOWNLOAD_DIR_UNSUPPORTED: string = 'unsupported';

// 返回要弹的字符串资源名；'' = 不弹。
export function downloadDirToast(status: string): string {
  if (status === DOWNLOAD_DIR_CHANGED) {
    return 'ds_download_path_changed';
  }
  if (status === DOWNLOAD_DIR_CANCELLED) {
    return '';
  }
  if (status === DOWNLOAD_DIR_EMPTY || status === DOWNLOAD_DIR_UNSUPPORTED) {
    return 'ds_download_picker_unsupported';
  }
  return 'media_cannot_open_location';
}

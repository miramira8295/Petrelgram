// Helpers for turning a picked media/document URI into something sendable.
//
// These are the decidable parts of the attach-and-send flow, split out from
// ChatPage so they can be exercised directly: the picker, the file copy and the
// send request all need a UI context / TDLib and stay in the page.

// Container formats the app sends as video rather than as a photo.
//
// Single source of truth on purpose: this rule used to be written twice with
// different contents — the multi-select send path accepted mp4/mov/mkv/avi/webm
// while the "replace this message's media" path accepted only mp4/mov, so
// replacing a message with an .mkv silently sent it as a photo.
const VIDEO_EXTENSIONS: string[] = ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', '3gp'];

// Extension of `path`, lowercased, without the dot. '' when there is none.
export function fileExtension(path: string): string {
  const slash: number = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  const name: string = slash >= 0 ? path.substring(slash + 1) : path;
  const dot: number = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

export function isVideoPath(path: string): boolean {
  return VIDEO_EXTENSIONS.indexOf(fileExtension(path)) >= 0;
}

// 必须作为 animation（GIF）而不是 photo 发出去的格式。
//
// **为什么这条规则要存在。** 从图库选一张 GIF，原来走的是 inputMessagePhoto——
// 服务器按静态图存下来，动画帧就此丢失。现象是发出去之后自己看不动，用官版看
// 同一条也不动、而且没有 GIF 角标（issue #105 的报告人正是这么验证的）。
// 这不是播放器的问题，是发送时就已经压成了图片，收多少次都救不回来。
//
// 只列 gif：判据是"能从扩展名断定它是动画"。webp/apng 也可能是动画，但同样的
// 扩展名下静态的居多，误判成 animation 会把一张普通贴图变成 GIF。
const ANIMATION_EXTENSIONS: string[] = ['gif'];

export function isAnimationPath(path: string): boolean {
  return ANIMATION_EXTENSIONS.indexOf(fileExtension(path)) >= 0;
}

// Last path segment of a URI, percent-decoded. Falls back to the raw segment
// when the URI is malformed — decodeURIComponent throws on a stray '%', and a
// pick should not fail over a filename.
export function fileNameFromUri(uri: string): string {
  const raw: string = uri.substring(uri.lastIndexOf('/') + 1);
  try {
    return decodeURIComponent(raw);
  } catch (e) {
    return raw;
  }
}

// Destination for the copy into the app cache. `seq` disambiguates files picked
// within the same millisecond — selecting nine photos at once does exactly
// that, and a timestamp alone would collide.
export function cacheDestPath(cacheDir: string, uri: string, seq: number, nowMs: number): string {
  return `${cacheDir}/send_${nowMs}_${seq}_${fileNameFromUri(uri)}`;
}

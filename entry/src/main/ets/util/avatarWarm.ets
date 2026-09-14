// 首屏发送者头像的预热。
//
// 【为什么】#137 为了不让头像先闪一下首字母，给 38vp 的头像开了**同步解码**
// （CachedImage.syncSmall → pixelCache.loadPixelMapSync，主线程阻塞）。代价在
// 2026-09-14 的 Frame trace 里量到了：进会话那一秒里 `aboutToAppear` 共 91 次
// 19.9ms，单次最大 3.12ms，而且它发生在 **Measure 阶段内部**——首屏那几行每
// 出现一个新发送者就多掏一次。
//
// 预热不改变"不闪首字母"这个结论，只是把解码挪到首屏挂树之前的空档：
// 行真正挂上来时 cachedPixelMap 直接命中，同步那一支根本不会被走到。
import { AlbumGroup } from './collapseAlbums';
import { cachedPixelMap, loadPixelMap, PixelRequest } from './pixelCache';

// 一次最多预热几张。首屏可见的行就那么几条，多出来的是白花解码。
export const AVATAR_WARM_MAX: number = 12;
// 头像盒子是 38vp（见 LightweightSenderAvatar / LiveSenderAvatar）。
const AVATAR_BOX_VP: number = 38;

// 去重 + 封顶 + 跳过已在缓存里的。**纯函数**，可单测；真正的解码在下面。
export function planAvatarWarm(
  paths: string[], isCached: (path: string) => boolean, max: number = AVATAR_WARM_MAX
): string[] {
  const out: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const path of paths) {
    if (path === '' || seen.has(path) || isCached(path)) {
      continue;
    }
    seen.add(path);
    out.push(path);
    if (out.length >= max) {
      break;
    }
  }
  return out;
}

function requestFor(path: string, sidePx: number): PixelRequest {
  return { path: path, width: sidePx, height: sidePx };
}

// 即发即忘：解出来的那份留在 pixelCache 里（不 retain，所以照样可被淘汰）。
export function warmSenderAvatars(paths: string[], sidePx: number = 0): void {
  const side: number = sidePx > 0 ? sidePx : vp2px(AVATAR_BOX_VP);
  const wanted: string[] = planAvatarWarm(paths,
    (path: string): boolean => cachedPixelMap(requestFor(path, side)) !== undefined);
  for (const path of wanted) {
    loadPixelMap(requestFor(path, side)).catch((): void => {});
  }
}

// 锚点上下这些行算"首屏"。不按真实视口高度算：那要量布局，而这一刻的目的
// 恰恰是**别碰布局**；多预热几张的代价只是几次后台解码。
export const AVATAR_WARM_RADIUS: number = 8;

// 首屏可见那一段的发送者头像路径（按靠近锚点的顺序，封顶交给 planAvatarWarm）。
export function initialAvatarPaths(
  groups: AlbumGroup[], anchorIndex: number, radius: number = AVATAR_WARM_RADIUS
): string[] {
  if (groups.length === 0) {
    return [];
  }
  const center: number = anchorIndex >= 0 && anchorIndex < groups.length
    ? anchorIndex : groups.length - 1;
  const from: number = Math.max(0, center - radius);
  const to: number = Math.min(groups.length - 1, center + radius);
  const out: string[] = [];
  // 从锚点往两边交替取：先要的是用户一眼看到的那几行。
  for (let step = 0; step <= radius; step++) {
    const up: number = center - step;
    const down: number = center + step;
    if (up >= from) {
      out.push(groups[up].head.senderAvatarPath);
    }
    if (step > 0 && down <= to) {
      out.push(groups[down].head.senderAvatarPath);
    }
  }
  return out;
}

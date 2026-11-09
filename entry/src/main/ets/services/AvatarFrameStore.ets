import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AvatarFrameAsset, AvatarFrameLease, AvatarFramePool } from '../util/avatarFramePool';
import { avatarFramePlan, avatarFrameSize, AVATAR_CACHE_MAX_BYTES,
  AVATAR_FRAME_MAX_BYTES, AVATAR_SOURCE_MAX_BYTES } from '../util/avatarFramePlan';
import { logI, logW } from '../util/log';

function dispose(asset: AvatarFrameAsset<image.PixelMap>): void {
  for (const frame of asset.frames) { frame.release().catch((): void => {}); }
}
const pool = new AvatarFramePool<image.PixelMap>(AVATAR_CACHE_MAX_BYTES, AVATAR_FRAME_MAX_BYTES, dispose);
const unsupported: Map<string, number> = new Map();

function rejectSource(key: string): void {
  if (unsupported.size >= 64) { unsupported.delete(unsupported.keys().next().value); }
  unsupported.set(key, Date.now() + 600000);
}
function emptyLease(): AvatarFrameLease<image.PixelMap> {
  return { ready: Promise.resolve(null), release: (): void => {} };
}

async function decode(path: string, size: number, fileBytes: number, key: string,
  cancelled: () => boolean): Promise<AvatarFrameAsset<image.PixelMap> | null> {
  let file: fs.File | null = null;
  let generator: media.AVImageGenerator | null = null;
  const frames: image.PixelMap[] = [];
  let accepted = false;
  const began = Date.now();
  try {
    if (cancelled()) { return null; }
    file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(fileBytes);
    const read = await fs.read(file.fd, buffer);
    const plan = read === fileBytes ? avatarFramePlan(buffer, size) : null;
    if (plan === null) { rejectSource(key); return null; }
    if (cancelled()) { return null; }
    generator = await media.createAVImageGenerator();
    generator.fdSrc = { fd: file.fd, offset: 0, length: fileBytes };
    let bytes = 0;
    for (const time of plan.timesUs) {
      if (cancelled() || Date.now() - began > 8000) { return null; }
      const frame = await generator.fetchScaledFrameByTime(time,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST, { width: size, height: size });
      frames.push(frame);
      const info = await frame.getImageInfo();
      bytes += frame.getPixelBytesNumber();
      if (info.size.width !== size || info.size.height !== size || bytes > AVATAR_FRAME_MAX_BYTES) {
        rejectSource(key);
        return null;
      }
    }
    if (cancelled()) { return null; }
    accepted = true;
    logI(`[AvatarFrames] ready frames=${frames.length} size=${size} bytes=${bytes} prepareMs=${Date.now() - began}`);
    return { frames: frames, durationsMs: plan.durationsMs, size: size, bytes: bytes };
  } catch (error) {
    rejectSource(key);
    logW(`[AvatarFrames] prepare failed: ${error}`);
    return null;
  } finally {
    if (generator !== null) { try { await generator.release(); } catch (_) {} }
    if (file !== null) { try { await fs.close(file); } catch (_) {} }
    if (!accepted) { for (const frame of frames) { try { await frame.release(); } catch (_) {} } }
  }
}

export async function acquireAvatarFrames(path: string, pixels: number): Promise<AvatarFrameLease<image.PixelMap>> {
  const size = avatarFrameSize(pixels);
  if (size === 0 || path === '') { return emptyLease(); }
  try {
    const stat = await fs.stat(path);
    if (stat.size < 8 || stat.size > AVATAR_SOURCE_MAX_BYTES) { return emptyLease(); }
    // 路径可能被重新下载覆盖；大小和修改时间一起隔离旧帧。不同显示尺寸按32px归桶。
    const key = `${path}|${stat.size}|${stat.mtime}|${size}`;
    if ((unsupported.get(key) ?? 0) > Date.now()) { return emptyLease(); }
    return pool.acquire(key, (cancelled: () => boolean): Promise<AvatarFrameAsset<image.PixelMap> | null> =>
      decode(path, size, stat.size, key, cancelled));
  } catch (_) { return emptyLease(); }
}

export function trimAvatarFrames(): void { pool.clearIdle(); }

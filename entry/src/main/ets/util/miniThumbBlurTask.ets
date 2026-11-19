import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { effectKit } from '@kit.ArkGraphics2D';
import { MINI_PLACEHOLDER_BLUR } from './miniThumbPlaceholder';

// Decode and CPU-filter only the inline miniature, never the full photograph.
// ArkUI blur and EffectKit both use px. The caller supplies physical display
// dimensions so scaling back to miniature pixels preserves the old radius.
@Concurrent
export async function blurMiniThumb(sourceUrl: string, boxW: number, boxH: number, contain: boolean): Promise<string> {
  let source: image.ImageSource | undefined;
  let original: image.PixelMap | undefined;
  let filtered: image.PixelMap | undefined;
  let packer: image.ImagePacker | undefined;
  try {
    const prefix = 'data:image/';
    const separator = sourceUrl.indexOf(';base64,');
    if (!sourceUrl.startsWith(prefix) || separator < 0 || sourceUrl.length > 65536) { return ''; }
    const base64 = new util.Base64Helper();
    const bytes = base64.decodeSync(sourceUrl.substring(separator + 8));
    source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    const info = await source.getImageInfo();
    const w = info.size.width, h = info.size.height;
    if (w < 1 || h < 1 || w > 256 || h > 256 || !(boxW > 0 && boxH > 0)) { return ''; }
    original = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const displayScale = contain ? Math.min(boxW / w, boxH / h) : Math.max(boxW / w, boxH / h);
    const filter = effectKit.createEffect(original);
    filtered = await filter.blur(Math.max(0.1, Math.min(64, MINI_PLACEHOLDER_BLUR / displayScale))).getEffectPixelMap();
    packer = image.createImagePacker();
    const encoded = await packer.packing(filtered, { format: 'image/png', quality: 100 });
    return 'data:image/png;base64,' + base64.encodeToStringSync(new Uint8Array(encoded));
  } finally {
    // Results cross the TaskPool boundary as immutable text, so native ownership stays here.
    packer?.release();
    if (filtered !== undefined && filtered !== original) { filtered.release(); }
    original?.release();
    source?.release();
  }
}

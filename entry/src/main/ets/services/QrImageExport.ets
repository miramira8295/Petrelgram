import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { systemShare } from '@kit.ShareKit';
import { saveMediaToGallery } from '../util/mediaSaver';

// 独立位图，避免弹窗到期刷新/关闭时release正在编码的PixelMap。
// 分享接收方可能异步读文件，分享缓存保留24小时，在后续导出时清理。
export async function exportQrImage(context: common.UIAbilityContext, link: string, title: string,
  share: boolean, anchor: systemShare.ShareControllerAnchor, current: () => boolean): Promise<void> {
  const directory = `${context.cacheDir}/qr_exports`;
  if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
  const cutoff = Date.now() / 1000 - 86400;
  for (const name of fs.listFileSync(directory)) {
    const file = `${directory}/${name}`;
    try { if (fs.statSync(file).mtime < cutoff) { fs.unlinkSync(file); } } catch (_) {}
  }
  const path = `${directory}/qr_${Date.now()}_${Math.floor(Math.random() * 1000000)}.png`;
  let pixels: image.PixelMap | null = null;
  let packer: image.ImagePacker | null = null;
  let file: fs.File | null = null;
  let shared: boolean = false;
  try {
    pixels = await generateBarcode.createBarcode(link, {
      scanType: scanCore.ScanType.QR_CODE, width: 512, height: 512,
      margin: 10, backgroundColor: 0xFFFFFF, pixelMapColor: 0x000000
    });
    if (!current()) { return; }
    packer = image.createImagePacker();
    file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    await packer.packToFile(pixels, file.fd, { format: 'image/png', quality: 100 });
    fs.closeSync(file); file = null;
    if (!current()) { return; }
    if (share) {
      const data = new systemShare.SharedData({ utd: 'general.image', uri: fileUri.getUriFromPath(path), title });
      const controller = new systemShare.ShareController(data);
      await controller.show(context, { previewMode: systemShare.SharePreviewMode.DETAIL, anchor });
      shared = true;
    } else {
      await saveMediaToGallery(context, path, false);
    }
  } finally {
    if (file !== null) { try { fs.closeSync(file); } catch (_) {} }
    if (packer !== null) { await packer.release().catch((): void => {}); }
    if (pixels !== null) { await pixels.release().catch((): void => {}); }
    if (!shared) { try { if (fs.accessSync(path)) { fs.unlinkSync(path); } } catch (_) {} }
  }
}

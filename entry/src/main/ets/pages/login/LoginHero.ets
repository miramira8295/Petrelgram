import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TgsStickerView } from '../chat/TgsStickerView';
import { logE } from '../../util/log';

const UTYA_PHONE_RAW: string = 'login_utya_phone.tgs';
const UTYA_WAVE_RAW: string = 'login_utya_wave.tgs';

// The authentication mascot uses the Utya Duck Animated TGS stickers linked
// by Telegram's own sticker documentation. Raw resources are copied once to
// the app files directory because the existing TGS player consumes a file path.
@Component
export struct LoginHero {
  @Prop mode: string = 'phone';
  @Prop active: boolean = false;
  @State tgsPath: string = '';
  @State failed: boolean = false;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.prepareSticker();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private rawName(): string {
    return this.mode === 'phone' ? UTYA_PHONE_RAW : UTYA_WAVE_RAW;
  }

  private async prepareSticker(): Promise<void> {
    const rawName = this.rawName();
    const context = getContext(this) as common.UIAbilityContext;
    const target = `${context.filesDir}/${rawName}`;
    try {
      const stat = fs.statSync(target);
      if (stat.size > 0) {
        if (!this.disposed) { this.tgsPath = target; }
        return;
      }
    } catch (_) {
      // First use: copy the packaged TGS below.
    }
    try {
      const bytes = await context.resourceManager.getRawFileContent(rawName);
      const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, bytes.buffer);
      fs.closeSync(file);
      if (!this.disposed) { this.tgsPath = target; }
    } catch (caught) {
      logE(`LoginHero.prepareSticker(${rawName}) failed: ${caught}`);
      if (!this.disposed) { this.failed = true; }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.tgsPath !== '') {
        TgsStickerView({
          tgsPath: this.tgsPath,
          boxWidth: 154,
          boxHeight: 154
        });
      } else if (this.failed) {
        Text('🦆').fontSize(78);
      } else {
        LoadingProgress().width(30).height(30).color('#3390EC');
      }
    }
    .width(160)
    .height(160)
    .scale({
      x: this.mode === 'password' && this.active ? 1.04 : 1,
      y: this.mode === 'password' && this.active ? 1.04 : 1
    })
    .animation({ duration: 180, curve: Curve.EaseOut });
  }
}

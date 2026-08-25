import { COLOR_TEXT_SECONDARY } from '../../util/theme';
import { TgsStickerView } from './TgsStickerView';
import { str } from '../../util/strings';

// 骰子/飞镖/篮球等（messageDice）：直接播 TDLib 下发的官方 TGS 结果动画
// （动画播完定格在结果上）。动画未就绪时显示 emoji 占位。
@Component
export struct DiceBubble {
  @Prop emoji: string = '🎲';
  @Prop value: number = 0;
  @Prop hasFinalState: boolean = false;
  @Prop successFrame: number = 0;
  @Prop stickerPath: string = '';
  // 🎰 老虎机 5 层（背景/左中右转轮/拉杆，已按 z 序排列），全就绪才叠层播放。
  @Prop layerPaths: string[] = [];

  private safeEmoji(): string {
    return this.emoji.trim() !== '' ? this.emoji : '🎲';
  }

  private slotLayersReady(): boolean {
    return this.layerPaths.length === 5 &&
      this.layerPaths.every((path: string): boolean => path !== '');
  }

  build() {
    Column({ space: 2 }) {
      if (this.slotLayersReady()) {
        Stack() {
          ForEach(this.layerPaths, (path: string) => {
            TgsStickerView({
              tgsPath: path,
              boxWidth: 150,
              boxHeight: 150,
              powerCategory: 'sticker',
              chatTimeline: true,
              playOnce: true
            });
          }, (path: string, index: number): string => `slot_${index}_${path}`);
        }
        .width(150).height(150);
      } else if (this.stickerPath !== '') {
        TgsStickerView({
          tgsPath: this.stickerPath,
          boxWidth: 150,
          boxHeight: 150,
          powerCategory: 'sticker',
          chatTimeline: true,
          playOnce: true
        });
      } else {
        Stack() {
          Text(this.safeEmoji()).fontSize(96);
          if (!this.hasFinalState || this.value <= 0) {
            LoadingProgress().width(20).height(20)
              .position({ x: 118, y: 118 });
          }
        }
        .width(150).height(150);
      }
    }
    .padding({ right: 24, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(this.value > 0
      ? str('dice_result', this.safeEmoji(), this.value) : str('dice_waiting', this.safeEmoji()));
  }
}

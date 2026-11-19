import { DrawnMediaPlaceholder } from './DrawnMediaPlaceholder';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { promptAction } from '@kit.ArkUI';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { TgsStickerView } from './TgsStickerView';
import { str } from '../../util/strings';

// 骰子/飞镖/篮球等（messageDice）：直接播 TDLib 下发的官方 TGS 结果动画
// （动画播完定格在结果上）。动画未就绪时显示 emoji 占位。
// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct DiceBubble {
  @Param emoji: string = '🎲';
  @Param value: number = 0;
  @Param hasFinalState: boolean = false;
  @Param successFrame: number = 0;
  @Param stickerPath: string = '';
  // 🎰 老虎机 5 层（背景/左中右转轮/拉杆，已按 z 序排列），全就绪才播：交给一个播放器、
  // 由原生合成一张（2026-10-10；原来 5 个播放器叠着各播各的，又卡又对不齐）。
  @Param layerPaths: string[] = [];
  // 这条骰子消息的身份（会话:消息 id）。结果动画只摇一次，见 util/stickerPlayedOnce。
  @Param playKey: string = '';
  @Param compact: boolean = false;
  @Param animationSide: number = 150;
  @Event onBeforeOpen: () => boolean = (): boolean => true;
  @Event canInteract: () => boolean = (): boolean => true;
  @Event onSendSame: (emoji: string) => void = (_emoji: string): void => {};
  @Local private replayToken: number = 0;
  private menuGeneration: number = 0;
  private menuOpen: boolean = false;

  aboutToDisappear(): void { this.menuGeneration++; this.menuOpen = false; }
  aboutToRecycle(): void { this.menuGeneration++; this.menuOpen = false; }

  @Monitor('playKey')
  onMessageChanged(): void {
    this.menuGeneration++;
    this.menuOpen = false;
    this.replayToken = 0;
  }

  private async showActions(): Promise<void> {
    if (!this.canInteract() || this.menuOpen || !this.onBeforeOpen()) { return; }
    const identity = this.playKey;
    const emoji = this.safeEmoji();
    const generation = ++this.menuGeneration;
    const canReplay = this.hasFinalState && (this.slotLayersReady() || this.stickerPath !== '');
    const options: promptAction.ActionMenuOptions = {
      buttons: canReplay
        ? [{ text: str('player_replay'), color: COLOR_TEXT_SECONDARY as string },
          { text: `${str('send')} ${emoji}`, color: COLOR_TEXT_SECONDARY as string }]
        : [{ text: `${str('send')} ${emoji}`, color: COLOR_TEXT_SECONDARY as string }]
    };
    this.menuOpen = true;
    try {
      const result = await this.getUIContext().getPromptAction().showActionMenu(options);
      if (generation !== this.menuGeneration || identity !== this.playKey || !this.canInteract()) { return; }
      if (canReplay && result.index === 0) {
        this.replayToken++;
      } else if (result.index === (canReplay ? 1 : 0)) {
        this.onSendSame(emoji);
      }
    } catch (_) {
      // Dismissing the menu is not an action.
    } finally {
      if (generation === this.menuGeneration) { this.menuOpen = false; }
    }
  }

  private safeEmoji(): string {
    return this.emoji.trim() !== '' ? this.emoji : '🎲';
  }

  // 只有结果动画才记「播过」：还没出结果时播的是等待动画，结果到了要接着摇。
  // 带上路径：同一条消息从等待动画换成结果动画，是另一段。
  private resultPlayKey(source: string): string {
    return this.playKey !== '' && this.hasFinalState ? `${this.playKey}:${source}` : '';
  }

  private slotLayersReady(): boolean {
    return this.layerPaths.length === 5 &&
      this.layerPaths.every((path: string): boolean => path !== '');
  }

  build() {
    Column({ space: 2 }) {
      if (this.slotLayersReady()) {
        TgsStickerView({
          tgsPath: this.layerPaths[0],
          layerPaths: this.layerPaths,
          replayToken: this.replayToken,
          playKey: this.resultPlayKey(this.layerPaths.join('|')),
          boxWidth: this.animationSide,
          boxHeight: this.animationSide,
          powerCategory: 'sticker',
          chatTimeline: true,
          playOnce: true
        });
      } else if (this.stickerPath !== '') {
        TgsStickerView({
          tgsPath: this.stickerPath,
          replayToken: this.replayToken,
          playKey: this.resultPlayKey(this.stickerPath),
          boxWidth: this.animationSide,
          boxHeight: this.animationSide,
          powerCategory: 'sticker',
          chatTimeline: true,
          playOnce: true
        });
      } else {
        Stack() {
          DrawnMediaPlaceholder({ primary: this.safeEmoji(), primarySize: this.animationSide * 0.64, primaryColor: COLOR_TEXT_PRIMARY,
            boxWidth: this.animationSide, boxHeight: this.animationSide });
          if (!this.hasFinalState || this.value <= 0) {
            DrawnLoadingSpinner({ ringSize: 20, ringColor: $r('app.color.primary') })
              .position({ x: this.animationSide - 32, y: this.animationSide - 32 });
          }
        }
        .width(this.animationSide).height(this.animationSide);
      }
    }
    .onClick((): void => { this.showActions(); })
    .padding({ right: this.compact ? 0 : 24, bottom: this.compact ? 0 : 8 })
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(this.value > 0
      ? str('dice_result', this.safeEmoji(), this.value) : str('dice_waiting', this.safeEmoji()));
  }
}

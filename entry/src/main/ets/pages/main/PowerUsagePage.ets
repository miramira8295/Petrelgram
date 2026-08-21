import { router } from '@kit.ArkUI';
import {
  KEY_BATTERY_PERCENT,
  KEY_POWER_ACTIVE,
  KEY_POWER_CALL_ANIMATIONS,
  KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_CHAT,
  KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS,
  KEY_POWER_EFFECT_BACKGROUND,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_POWER_ANIMATED_AVATAR,
  KEY_POWER_STICKERS,
  KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_STICKER_LOOP,
  KEY_POWER_THRESHOLD,
  POWER_THRESHOLD_DEFAULT,
  powerAnimationDuration,
  refreshPowerSavingState,
  setBoolean,
  setNumber
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { HdsSubPage } from '../common/HdsSubPage';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const THRESHOLDS: number[] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 101];
const STICKER_KEYS: string[] = [KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP];
const EMOJI_KEYS: string[] = [KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS, KEY_POWER_EMOJI_STATUS];
const EFFECT_KEYS: string[] = [
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_BACKGROUND
];

@Entry
@Component
struct PowerUsagePage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_POWER_THRESHOLD) threshold: number = POWER_THRESHOLD_DEFAULT;
  @StorageProp(KEY_POWER_ACTIVE) active: boolean = false;
  @StorageProp(KEY_BATTERY_PERCENT) batteryPercent: number = 100;
  @StorageLink(KEY_POWER_ANIMATED_AVATAR) animatedAvatar: boolean = true;
  @StorageLink(KEY_POWER_STICKERS) animatedStickers: boolean = true;
  @StorageLink(KEY_POWER_EMOJI) animatedEmoji: boolean = true;
  @StorageLink(KEY_POWER_CHAT_EFFECTS) chatEffects: boolean = true;
  @StorageLink(KEY_POWER_CALL_ANIMATIONS) callAnimations: boolean = true;
  @StorageLink(KEY_POWER_PARTICLES) particles: boolean = true;
  @StorageLink(KEY_POWER_SMOOTH_TRANSITIONS) smoothTransitions: boolean = true;
  @StorageLink(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageLink(KEY_POWER_STICKER_LOOP) stickerLoop: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_CHAT) emojiChat: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_REACTIONS) emojiReactions: boolean = true;
  @StorageLink(KEY_POWER_EMOJI_STATUS) emojiStatus: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_MESSAGE) effectMessage: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_REACTION) effectReaction: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_REPLY) effectReply: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_MENU) effectMenu: boolean = true;
  @StorageLink(KEY_POWER_EFFECT_BLUR) effectBlur: boolean = false;
  @StorageLink(KEY_POWER_EFFECT_BACKGROUND) effectBackground: boolean = false;
  @State expandedKey: string = '';
  @State leavingPage: boolean = false;
  private leaveTimer: number = -1;

  aboutToAppear(): void {
    refreshPowerSavingState();
  }

  aboutToDisappear(): void {
    if (this.leaveTimer !== -1) {
      clearTimeout(this.leaveTimer);
      this.leaveTimer = -1;
    }
    this.leavingPage = false;
    this.expandedKey = '';
  }

  private leavePage(): void {
    if (this.leavingPage) {
      return;
    }
    this.leavingPage = true;
    this.leaveTimer = setTimeout((): void => {
      this.leaveTimer = -1;
      this.leavingPage = false;
    }, 500);
    router.back();
  }

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.985 })
  }

  private thresholdIndex(): number {
    const index = THRESHOLDS.indexOf(this.threshold);
    return index >= 0 ? index : 1;
  }

  private thresholdTitle(): string {
    if (this.threshold === 0) {
      return str('power_off');
    }
    if (this.threshold === 101) {
      return str('night_always_on');
    }
    return str('power_below_pct', this.threshold);
  }

  private thresholdDescription(): string {
    if (this.threshold === 0) {
      return str('power_auto_off_note');
    }
    if (this.threshold === 101) {
      return str('power_always_on_note');
    }
    return str('power_threshold_note', this.threshold);
  }

  private featureValue(key: string): boolean {
    if (key === KEY_POWER_ANIMATED_AVATAR) { return this.animatedAvatar; }
    if (key === KEY_POWER_STICKERS) { return this.animatedStickers; }
    if (key === KEY_POWER_EMOJI) { return this.animatedEmoji; }
    if (key === KEY_POWER_CHAT_EFFECTS) { return this.chatEffects; }
    if (key === KEY_POWER_CALL_ANIMATIONS) { return this.callAnimations; }
    if (key === KEY_POWER_PARTICLES) { return this.particles; }
    return this.smoothTransitions;
  }

  private subFeatureValue(key: string): boolean {
    if (key === KEY_POWER_STICKER_AUTOPLAY) { return this.stickerAutoplay; }
    if (key === KEY_POWER_STICKER_LOOP) { return this.stickerLoop; }
    if (key === KEY_POWER_EMOJI_CHAT) { return this.emojiChat; }
    if (key === KEY_POWER_EMOJI_REACTIONS) { return this.emojiReactions; }
    if (key === KEY_POWER_EMOJI_STATUS) { return this.emojiStatus; }
    if (key === KEY_POWER_EFFECT_MESSAGE) { return this.effectMessage; }
    if (key === KEY_POWER_EFFECT_REACTION) { return this.effectReaction; }
    if (key === KEY_POWER_EFFECT_REPLY) { return this.effectReply; }
    if (key === KEY_POWER_EFFECT_MENU) { return this.effectMenu; }
    if (key === KEY_POWER_EFFECT_BLUR) { return this.effectBlur; }
    return this.effectBackground;
  }

  private groupKeys(key: string): string[] {
    if (key === KEY_POWER_STICKERS) { return STICKER_KEYS; }
    if (key === KEY_POWER_EMOJI) { return EMOJI_KEYS; }
    if (key === KEY_POWER_CHAT_EFFECTS) { return EFFECT_KEYS; }
    return [];
  }

  private groupCount(key: string): number {
    return this.groupKeys(key).filter(
      (subKey: string): boolean => this.subFeatureValue(subKey)
    ).length;
  }

  private setGroup(key: string, value: boolean): void {
    setBoolean(key, value);
    for (const subKey of this.groupKeys(key)) {
      setBoolean(subKey, value);
    }
  }

  private setSubFeature(groupKey: string, key: string, value: boolean): void {
    setBoolean(key, value);
    let anyEnabled = value;
    if (!anyEnabled) {
      anyEnabled = this.groupKeys(groupKey).some(
        (subKey: string): boolean => subKey !== key && this.subFeatureValue(subKey)
      );
    }
    setBoolean(groupKey, anyEnabled);
  }

  private setThresholdIndex(index: number): void {
    const safeIndex = Math.max(0, Math.min(THRESHOLDS.length - 1, Math.round(index)));
    setNumber(KEY_POWER_THRESHOLD, THRESHOLDS[safeIndex]);
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44).borderRadius(22)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .enabled(!this.leavingPage)
      .accessibilityText($r('app.string.back_to_settings'))
      .onClick((): void => { this.leavePage(); });
      Text($r('app.string.settings_power')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(56).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  modeCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text($r('app.string.power_mode')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
        Text(this.active ? 'ON' : 'OFF')
          .fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(this.active ? Color.White : COLOR_PRIMARY)
          .backgroundColor(this.active ? COLOR_PRIMARY : '#DCEEFF')
          .borderRadius(5).padding({ left: 7, right: 7, top: 3, bottom: 3 });
        Blank();
        Text(str('power_current_pct', this.batteryPercent))
          .fontSize(13).fontColor(this.active ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Row() {
        Text($r('app.string.power_off')).fontSize(14)
          .fontColor(this.threshold === 0 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
        Blank();
        Row({ space: 5 }) {
          Text(this.thresholdTitle()).fontSize(15).fontColor(COLOR_PRIMARY);
          SymbolGlyph($r('sys.symbol.battery_100percent')).fontSize(17).fontColor([COLOR_PRIMARY]);
        }
        Blank();
        Text($r('app.string.power_on')).fontSize(14)
          .fontColor(this.threshold === 101 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Slider({
        value: this.thresholdIndex(),
        min: 0,
        max: THRESHOLDS.length - 1,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor(COLOR_PRIMARY)
        .blockColor(COLOR_PRIMARY)
        .onChange((value: number): void => { this.setThresholdIndex(value); });
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 15, bottom: 14 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  @Builder
  featureRow(icon: string, title: string, key: string, total: number) {
    Row({ space: 13 }) {
      Row({ space: 13 }) {
        SymbolGlyph($r(icon)).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]).width(30);
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      }
      .height(48)
      .layoutWeight(1)
      .borderRadius(10)
      .stateStyles({
        normal: this.rowNormalStyle,
        pressed: this.rowPressedStyle
      })
      .accessibilityText(str('a11y_toggle_state', title, this.featureValue(key) ? str('state_on') : str('state_off')))
      .onClick((): void => {
        const next = !this.featureValue(key);
        if (total > 0) {
          this.setGroup(key, next);
        } else {
          setBoolean(key, next);
        }
      });
      if (total > 0) {
        Row({ space: 7 }) {
          Text(`${this.groupCount(key)}/${total}`)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([COLOR_TEXT_PRIMARY])
            .rotate({ angle: this.expandedKey === key ? 180 : 0 })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
              curve: Curve.EaseOut
            });
        }
        .height(42).padding({ left: 8, right: 8 })
        .borderRadius(10)
        .stateStyles({
          normal: this.rowNormalStyle,
          pressed: this.rowPressedStyle
        })
        .accessibilityText(str('a11y_expand_details', this.expandedKey === key ? str('collapse') : str('expand'), title))
        .onClick((): void => {
          this.expandedKey = this.expandedKey === key ? '' : key;
        });
        Divider().vertical(true).height(30).strokeWidth(0.7).color($r('app.color.divider'))
          .margin({ left: 2, right: 1 });
      }
      Toggle({ type: ToggleType.Switch, isOn: this.featureValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .accessibilityText(str('a11y_switch_for', title))
        .onChange((value: boolean): void => {
          if (total > 0) {
            this.setGroup(key, value);
          } else {
            setBoolean(key, value);
          }
        });
    }
    .width('100%').height(56).padding({ left: 16, right: 13 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  subFeatureRow(groupKey: string, key: string, title: string) {
    Row({ space: 10 }) {
      Circle({ width: 5, height: 5 }).fill(COLOR_PRIMARY);
      Text(title)
        .fontSize(14)
        .fontColor(COLOR_TEXT_PRIMARY)
        .height(40)
        .layoutWeight(1)
        .borderRadius(8)
        .stateStyles({
          normal: this.rowNormalStyle,
          pressed: this.rowPressedStyle
        })
        .accessibilityText(str('a11y_toggle_state', title, this.subFeatureValue(key) ? str('state_on') : str('state_off')))
        .onClick((): void => {
          this.setSubFeature(groupKey, key, !this.subFeatureValue(key));
        });
      Toggle({ type: ToggleType.Switch, isOn: this.subFeatureValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .accessibilityText(str('a11y_switch_for', title))
        .onChange((value: boolean): void => {
          this.setSubFeature(groupKey, key, value);
        });
    }
    .width('100%').height(46)
    .padding({ left: 62, right: 13 })
    .backgroundColor($r('app.color.surface_alt'))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -4 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  featuresCard() {
    Column() {
      Text($r('app.string.power_options'))
        .width('100%').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .padding({ left: 16, right: 16, top: 13, bottom: 5 });
      this.featureRow('sys.symbol.person_crop_circle', str('power_animated_avatar'),
        KEY_POWER_ANIMATED_AVATAR, 0);
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.face_smiling', str('power_animated_stickers'), KEY_POWER_STICKERS, 2);
      if (this.expandedKey === KEY_POWER_STICKERS) {
        this.subFeatureRow(KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, str('power_animated_stickers_sub'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_STICKERS, KEY_POWER_STICKER_LOOP, str('power_loop_stickers'));
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.face_smiling_fill', str('power_animated_emoji'), KEY_POWER_EMOJI, 3);
      if (this.expandedKey === KEY_POWER_EMOJI) {
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_CHAT, str('power_emoji_messages'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS, str('power_emoji_reactions'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_EMOJI, KEY_POWER_EMOJI_STATUS, str('power_emoji_status'));
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.message', str('power_chat_effects'), KEY_POWER_CHAT_EFFECTS, 6);
      if (this.expandedKey === KEY_POWER_CHAT_EFFECTS) {
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MESSAGE, str('power_new_message_anim'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_REACTION, str('power_reaction_anim'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_REPLY, str('power_reply_anim'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU, str('power_menu_anim'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BLUR, str('power_blur_scale'));
        Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 62 });
        this.subFeatureRow(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND, str('power_background_anim'));
      }
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.phone', str('power_call_anim'), KEY_POWER_CALL_ANIMATIONS, 0);
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 58 });
      this.featureRow('sys.symbol.gift', str('power_particles'), KEY_POWER_PARTICLES, 0);
    }
    .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  @Builder
  smoothCard() {
    Row({ space: 12 }) {
      Text($r('app.string.power_smooth'))
        .fontSize(16)
        .fontColor(COLOR_TEXT_PRIMARY)
        .height(48)
        .layoutWeight(1)
        .borderRadius(10)
        .stateStyles({
          normal: this.rowNormalStyle,
          pressed: this.rowPressedStyle
        })
        .accessibilityText(str('a11y_toggle_state', str('power_smooth'), this.smoothTransitions ? str('state_on') : str('state_off')))
        .onClick((): void => {
          setBoolean(KEY_POWER_SMOOTH_TRANSITIONS, !this.smoothTransitions);
        });
      Toggle({ type: ToggleType.Switch, isOn: this.smoothTransitions })
        .selectedColor(COLOR_PRIMARY)
        .accessibilityText($r('app.string.power_smooth_switch'))
        .onChange((value: boolean): void => {
          setBoolean(KEY_POWER_SMOOTH_TRANSITIONS, value);
        });
    }
    .width('100%').height(58).padding({ left: 18, right: 13 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      HdsSubPage({ title: $r('app.string.settings_power'), scroller: this.hdsScroller, onBack: (): void => { this.leavePage(); } }) {
      Scroll(this.hdsScroller) {
        Column({ space: 12 }) {
          this.modeCard();
          Text(this.thresholdDescription())
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 15, right: 15 });
          this.featuresCard();
          this.smoothCard();
          Text($r('app.string.power_smooth_note'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 15, right: 15 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off)
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

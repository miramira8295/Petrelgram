import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU,
  KEY_REDUCE_ANIM, powerGroupAnimationDuration
} from '../../store/AppSettings';
import { accentSoft, COLOR_ICON_SECONDARY, COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { StickerPicker, StickerItem, ClassicPack } from './StickerPicker';
import { GifPicker, GifItem } from './GifPicker';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { EMOJI_CONTENT_HEIGHT, EMOJI_DRAWER_HEIGHT, EMOJI_TAB_BAR_HEIGHT } from '../../util/drawerMetrics';

// 内容区顶部这条带子归包切换条（贴纸/表情两页都有），横滑要留给它自己滚，
// 不能被"切换表情/贴纸/GIF"抢走。切页手势是 parallelGesture 挂在面板根上的
// ——它和子组件不争，谁都会触发，所以拦不住只能按落点划线。
const PACK_ROW_BAND: number = 44;

interface EmojiSection {
  title: string;
  emoji: string[];
}

const SECTIONS: EmojiSection[] = [
  {
    title: str('emoji_group_smileys'),
    emoji: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊',
      '😇', '🥰', '😍', '🤩', '😘', '😗', '☺️', '😚', '😙', '🥲', '😋', '😛',
      '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑',
      '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷',
      '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳',
      '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳',
      '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
      '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️',
      '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖'
    ]
  },
  {
    title: str('emoji_group_gestures'),
    emoji: [
      '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘',
      '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛',
      '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🫶',
      '👀', '👁️', '👄', '🧠', '🦾', '🦵'
    ]
  },
  {
    title: str('emoji_group_symbols'),
    emoji: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕',
      '💞', '💓', '💗', '💖', '💘', '💝', '💟', '💯', '💢', '💥', '💫', '💦',
      '💨', '🕳️', '💣', '💬', '💤', '🔥', '✨', '⭐', '🌟', '⚡', '☄️', '💎'
    ]
  },
  {
    title: str('emoji_group_nature'),
    emoji: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮',
      '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🦆', '🦅',
      '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪲', '🦋', '🐢', '🐍', '🐙',
      '🦀', '🐬', '🐳', '🦈', '🌸', '🌹', '🌻', '🌈', '🌙', '☀️'
    ]
  },
  {
    title: str('emoji_group_food'),
    emoji: [
      '🍎', '🍊', '🍋', '🍉', '🍇', '🍓', '🍑', '🍍', '🥭', '🥑', '🍅', '🌽',
      '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🍜', '🍣', '🍦', '🍰', '🎂', '🍫',
      '☕', '🍺', '🍷', '🥂', '⚽', '🏀', '🏈', '🎾', '🎮', '🎲', '🎯', '🎁',
      '🎉', '🎊', '🎈', '🏆', '🥇', '🚀'
    ]
  }
];

// 横滑切页的触发阈值。比 PanGesture 的 distance 大一截：那个只决定"算不算
// 一次拖动"，这个决定"这次拖动算不算翻页"，太小会让轻轻蹭一下就换页。
const SWIPE_TAB_THRESHOLD: number = 60;

const CLASSIC_PACKS: ClassicPack[] = SECTIONS.map((s: EmojiSection): ClassicPack => ({
  title: s.title,
  icon: s.emoji[0],
  emoji: s.emoji
}));

// Unified emoji/sticker/GIF panel. Tabs stay mounted once visited so switching
// categories doesn't restart requests; the page owns the selected category and
// remembers it after the panel is closed and reopened.
@Component
export struct EmojiPanel {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onPick: (emoji: string) => void = (): void => {};
  onPickCustomEmoji: (emoji: string, customEmojiId: string) => void = (): void => {};
  onPickSticker: (s: StickerItem, x: number, y: number) => void = (): void => {};
  onPickGif: (g: GifItem) => void = (): void => {};
  // 单向入 + 回调出，而不是 @Link：@Link 只能被 V1 状态变量初始化，页面迁到
  // 状态管理 V2 之后就接不上了。这里的写回照旧先改本地副本（@Prop 允许），
  // 再把新值交给页面，页面回灌同一个值，语义与双向同步等价。
  @Prop tab: number;
  onTabChange: (tab: number) => void = (): void => {};
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  @State stickerMounted: boolean = false;
  @State gifMounted: boolean = false;

  aboutToAppear(): void {
    this.stickerMounted = this.tab === 1;
    this.gifMounted = this.tab === 2;
  }

  private panelDuration(duration: number): number {
    if (this.reduceAnimations || this.powerSaving) {
      return 0;
    }
    return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU, duration);
  }

  // 按下点的 y（相对面板根），用来判断这一划是不是起于包切换条。
  private panDownY: number = 0;

  private switchTab(idx: number): void {
    // 越界就什么也不做——滑到第一页再往右滑不该跳到 GIF。
    if (idx < 0 || idx > 2 || idx === this.tab) {
      return;
    }
    if (idx === 1) {
      this.stickerMounted = true;
    } else if (idx === 2) {
      this.gifMounted = true;
    }
    animateTo({ duration: this.panelDuration(150), curve: Curve.EaseOut }, (): void => {
      this.tab = idx;
      this.onTabChange(idx);
    });
  }

  // 主分类始终带图标和文字，让三个页面看起来属于同一个抽屉。
  // 淡主色底是「当前模式」的状态，不是再塞一层卡片。
  @Builder
  modeTab(symbol: Resource, label: string, idx: number) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(17)
        .fontColor([this.tab === idx ? COLOR_PRIMARY : COLOR_ICON_SECONDARY]);
      Text(label)
        .fontSize(13)
        .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.tab === idx ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1).height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.tab === idx ? accentSoft() : Color.Transparent)
    .animation({ duration: this.panelDuration(140), curve: Curve.EaseOut })
    .accessibilityText(str('a11y_option_state', label, this.tab === idx ? str('a11y_selected') : ''))
    .onClick(() => { this.switchTab(idx); });
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        this.modeTab($r('sys.symbol.face_smiling'), str('emoji_tab'), 0);
        this.modeTab($r('sys.symbol.gift'), str('sticker_tab'), 1);
        this.modeTab($r('sys.symbol.video'), 'GIF', 2);
      }
      .width('100%').height(EMOJI_TAB_BAR_HEIGHT)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') });
      Stack() {
        Column() {
          StickerPicker({
            active: this.tab === 0,
            stickerType: 'custom_emoji',
            includeTrending: true,
            classicPacks: CLASSIC_PACKS,
            onPick: (s: StickerItem): void => {
              if (s.customEmojiId !== '') {
                this.onPickCustomEmoji(s.emoji, s.customEmojiId);
              } else if (s.emoji !== '') {
                this.onPick(s.emoji);
              }
            }
          });
        }
        .width('100%').height('100%')
        .visibility(this.tab === 0 ? Visibility.Visible : Visibility.Hidden);
        if (this.stickerMounted) {
          Column() {
            StickerPicker({
              active: this.tab === 1,
              onPick: (s: StickerItem, x: number, y: number): void => { this.onPickSticker(s, x, y); }
            });
          }
          .width('100%').height('100%')
          .visibility(this.tab === 1 ? Visibility.Visible : Visibility.Hidden);
        }
        if (this.gifMounted) {
          Column() {
            GifPicker({
              active: this.tab === 2,
              onPick: (g: GifItem): void => { this.onPickGif(g); }
            });
          }
          .width('100%').height('100%')
          .visibility(this.tab === 2 ? Visibility.Visible : Visibility.Hidden);
        }
      }
      // Keep the content viewport explicit. A layoutWeight chain inside the
      // empty-GIF state could otherwise propagate through Stack and make the
      // overlay consume the whole chat page after switching tabs.
      .width('100%').height(EMOJI_CONTENT_HEIGHT)
      // 记落点。PanGesture 的 event 只给位移，给不了起点在哪一条带子上。
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down && event.touches.length > 0) {
          this.panDownY = event.touches[0].y;
        }
      })
      // 左右滑动切页。只认横向：里面的网格是纵向滚动的，PanDirection.Horizontal
      // 让纵向拖动压根不满足这个识别器，直接落到网格自己身上。
      // parallelGesture 而不是 gesture：不抢子组件的点击（点表情要照常发出去）。
      .parallelGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 24 })
          .onActionEnd((event: GestureEvent): void => {
            const dx: number = event.offsetX;
            // Emoji and sticker pages reserve their first 44vp for the pack
            // scroller. A horizontal drag there belongs to that scroller, not
            // to the primary Emoji / Sticker / GIF switch.
            if ((this.tab !== 2 && this.panDownY < PACK_ROW_BAND) ||
              Math.abs(dx) < SWIPE_TAB_THRESHOLD) {
              return;
            }
            // 手指向左 = 看下一页。
            this.switchTab(dx < 0 ? this.tab + 1 : this.tab - 1);
          })
      );
    }
    .width('100%').height(EMOJI_DRAWER_HEIGHT)
    .constraintSize({ minHeight: EMOJI_DRAWER_HEIGHT, maxHeight: EMOJI_DRAWER_HEIGHT })
    // 透明：底色由抽屉卡片提供（毛玻璃/沉浸光感在那一层）。这里再涂一层
    // 不透明的 surface，就是把玻璃整个盖死——表情面板背景一直是死深色的原因。
    .backgroundColor(Color.Transparent)
    .accessibilityText($r('app.string.emoji_panel_a11y'));
  }
}

import {
  BG_BLUR_DEFAULT, BG_PATTERN_DEFAULT, KEY_APP_BG_BLUR, KEY_APP_BG_DIM, KEY_APP_BG_PATTERN_DARK,
  KEY_APP_BG_PATTERN_LIGHT, KEY_APP_BG_STATE_DARK, KEY_APP_BG_STATE_LIGHT
} from '../../store/AppSettings';
import { KEY_APP_DARK } from '../../util/theme';
import { appWallpaperActive } from '../../util/localWallpaper';
import {
  ChatBackgroundState, emptyChatBackground, parseSnapshot
} from '../../store/ChatBackgroundStore';
import { ChatBackdrop } from '../chat/ChatBackdrop';

// APP 背景图：铺在**主界面**（会话列表等）背后的壁纸。
//
// 【为什么直接复用 ChatBackdrop】它已经会画渐变、图案、整图、暗化、模糊，还带
// 栅格缓存和快照防闪——那是一堆真机趟出来的东西。APP 槽位把壁纸存成**序列化的
// ChatBackgroundState**（与聊天壁纸同一种数据），于是「原生壁纸也能给 APP 用」
// 不需要任何新代码：把状态传进去就画得出来。上一版自己贴 Image 的实现只支持本机
// 图片，已经整个删掉。
//
// 【为什么 APP 槽位存本地、聊天槽位不存】聊天壁纸由 TDLib 下发、账号级同步，本地
// 再存一份两边会打架；而 Telegram 协议里根本没有「APP 背景」这个概念，它只能是
// 本机设置。
//
// 【分栏下不铺】右栏被聊天壁纸盖住，这张图只能从左栏那条窄缝里露出来，既不好看
// 也没意义；设置项在分栏下也一并藏掉（用户："pad 没有这个选项"）。
@Component
export struct AppBackdrop {
  @Prop split: boolean = false;
  @StorageProp(KEY_APP_DARK) appDark: boolean = false;
  @StorageProp(KEY_APP_BG_STATE_LIGHT) stateLight: string = '';
  @StorageProp(KEY_APP_BG_STATE_DARK) stateDark: string = '';
  @StorageProp(KEY_APP_BG_BLUR) blurAmount: number = BG_BLUR_DEFAULT;
  @StorageProp(KEY_APP_BG_DIM) dimAmount: number = 0;
  @StorageProp(KEY_APP_BG_PATTERN_LIGHT) patternLight: number = BG_PATTERN_DEFAULT;
  @StorageProp(KEY_APP_BG_PATTERN_DARK) patternDark: number = BG_PATTERN_DEFAULT;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('screenHeightVp') screenH: number = 780;

  private rawState(): string {
    return this.appDark ? this.stateDark : this.stateLight;
  }

  private wallpaperOn(): boolean {
    return appWallpaperActive(this.rawState(), this.split);
  }

  // 解析失败时给一份空状态：ChatBackdrop 对「没有填充也没有图」的状态什么都不画，
  // 正是我们要的降级——脏数据不该让主界面白屏。
  private slotState(): ChatBackgroundState {
    const parsed: ChatBackgroundState | null = parseSnapshot(this.rawState());
    return parsed !== null ? parsed : emptyChatBackground();
  }

  private patternNow(): number {
    return this.appDark ? this.patternDark : this.patternLight;
  }

  build() {
    Stack() {
      if (this.wallpaperOn()) {
        ChatBackdrop({
          chatBg: this.slotState(),
          screenW: this.screenW,
          screenH: this.screenH,
          bgBlur: this.blurAmount,
          bgPattern: this.patternNow(),
          chatDim: this.dimAmount
        });
      }
    }
    .width('100%').height('100%')
    // 纯装饰层，不该吃任何手势——上面就是会话列表。
    .hitTestBehavior(HitTestMode.None);
  }
}

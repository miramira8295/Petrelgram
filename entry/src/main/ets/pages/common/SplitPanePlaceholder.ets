import { KEY_SPLIT_UNIFIED_BG } from '../../util/localWallpaper';
import { COLOR_TEXT_SECONDARY } from '../../util/theme';

// ComponentContent 的空态独立订阅开关，让整窗壁纸能透过右栏。
@Component
export struct SplitPanePlaceholder {
  @Prop message: ResourceStr = '';
  @Prop chatList: boolean = false;
  @StorageProp(KEY_SPLIT_UNIFIED_BG) private unifiedBg: boolean = true;

  build() {
    Column({ space: 12 }) {
      Image(this.chatList ? $r('app.media.ic_split_placeholder') : $r('app.media.foreground'))
        .width(this.chatList ? 72 : 64).height(this.chatList ? 72 : 64)
        .opacity(this.chatList ? 0.9 : 0.45)
        .draggable(false);
      Text(this.message).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.unifiedBg ? Color.Transparent : $r('app.color.page_bg'));
  }
}

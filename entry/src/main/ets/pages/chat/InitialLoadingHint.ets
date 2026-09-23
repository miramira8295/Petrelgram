import { getConnectionState, getTdClient } from '../../tdkit/Globals';
import { TdObject } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { INITIAL_HINT_DELAY_MS, initialHintLabelKey } from '../../util/initialLoadingHint';
import { str } from '../../util/strings';

// 会话首屏还一行都没有、正在加载时的居中提示（#219-10，判据见
// util/initialLoadingHint）。挂载后等 INITIAL_HINT_DELAY_MS 才出现：本地命中时
// 内容几十毫秒就到，组件随之卸载，什么都不画。
//
// 连接状态自己订阅：updateConnectionState 是一次性推送，所以先读 Globals 的缓存
// 再订阅后续变化（同 ChatListPage / ProxyPage）。
@ComponentV2
export struct InitialLoadingHint {
  @Local private shown: boolean = false;
  @Local private connectionState: string = '';
  private timer: number = -1;
  private unsubConn: (() => void) | null = null;

  aboutToAppear(): void {
    this.connectionState = getConnectionState();
    this.unsubConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject): void => {
      const st = u['state'] as TdObject | undefined;
      this.connectionState = st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '';
    });
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.shown = true;
    }, INITIAL_HINT_DELAY_MS);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.unsubConn !== null) {
      this.unsubConn();
      this.unsubConn = null;
    }
  }

  build() {
    Column({ space: 10 }) {
      if (this.shown) {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        if (initialHintLabelKey(this.connectionState) !== '') {
          Text(str(initialHintLabelKey(this.connectionState)))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
    }
    .alignItems(HorizontalAlign.Center);
  }
}

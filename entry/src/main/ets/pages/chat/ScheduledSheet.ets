import { promptAction } from '@kit.ArkUI';
import { formatPreview } from '../../util/formatPreview';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { monthDayTime } from '../../util/intlFormat';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';

// "定时消息" list, extracted from ChatPage.
//
// Fully self-contained: the page only decides whether the sheet is up. Loading,
// "send now" and delete all talk to TDLib directly and re-read the list after
// each mutation, exactly as they did inline.
@Component
export struct ScheduledSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 单向入 + 回调出，而不是 @Link（@Link 只能被 V1 状态变量初始化，页面迁到
  // 状态管理 V2 之后就接不上了）：点遮罩是从这里关的。
  @Prop show: boolean;
  onShowChange: (show: boolean) => void = (): void => {};
  chatId: number = 0;

  @State ids: number[] = [];
  @State previews: string[] = [];    // 与 ids 平行
  @State timeLabels: string[] = [];  // 与 ids 平行
  @State loadState: string = 'idle'; // idle | loading | ready | error

  // Guards continuations against a sheet closed while a request is in flight.
  private seq: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.seq++;
  }

  private load(): void {
    this.loadState = 'loading';
    const seq: number = ++this.seq;
    const req: TdRequest = { '@type': 'getChatScheduledMessages' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((res: TdObject): void => {
      if (seq !== this.seq) {
        return;
      }
      const messages: TdObject[] = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      const previews: string[] = [];
      const timeLabels: string[] = [];
      for (const message of messages) {
        const id: number = (message['id'] as number | undefined) ?? 0;
        if (id === 0) {
          continue;
        }
        ids.push(id);
        previews.push(formatPreview(message));
        const scheduling = message['scheduling_state'] as TdObject | undefined;
        const schedulingType: string = scheduling !== undefined
          ? ((scheduling['@type'] as string | undefined) ?? '') : '';
        if (schedulingType === 'messageSchedulingStateSendWhenOnline') {
          timeLabels.push(str('sched_when_online'));
        } else {
          const sendDate: number = scheduling !== undefined
            ? ((scheduling['send_date'] as number | undefined) ?? 0) : 0;
          // Date and time in one Intl formatter: the separator and the order
          // are locale business, and a hand-built "M月D日 HH:mm" is wrong in
          // every language but this one.
          timeLabels.push(sendDate > 0 ? monthDayTime(new Date(sendDate * 1000)) : '');
        }
      }
      this.ids = ids;
      this.previews = previews;
      this.timeLabels = timeLabels;
      this.loadState = 'ready';
    }).catch((e: TdError): void => {
      if (seq !== this.seq) {
        return;
      }
      logE(`ScheduledSheet.load failed: ${e.message}`);
      this.loadState = 'error';
    });
  }

  // 立即发送：不带 scheduling_state 的 editMessageSchedulingState。
  private sendNow(messageId: number): void {
    const req: TdRequest = { '@type': 'editMessageSchedulingState' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    getTdClient().send(req).then((): void => {
      this.load();
    }).catch((e: TdError): void => {
      logE(`ScheduledSheet.sendNow failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.send_failed_retry'), duration: 1700 });
    });
  }

  private remove(messageId: number): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [messageId];
    req['revoke'] = true;
    getTdClient().send(req).then((): void => {
      this.load();
    }).catch((e: TdError): void => {
      logE(`ScheduledSheet.remove failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.delete_failed_retry_soon'), duration: 1700 });
    });
  }

  build() {
    Column() {
      Column().layoutWeight(1).onClick((): void => {
        this.show = false;
        this.onShowChange(false);
      });
      Column({ space: 10 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Text($r('app.string.sched_title')).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        if (this.loadState === 'loading') {
          LoadingProgress().width(28).height(28).margin({ top: 24, bottom: 24 });
        } else if (this.loadState === 'error') {
          Text($r('app.string.sched_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else if (this.ids.length === 0) {
          Text($r('app.string.sched_empty')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else {
          List({ space: 6 }) {
            ForEach(this.ids, (id: number, itemIndex: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(this.previews[itemIndex] ?? '')
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(this.timeLabels[itemIndex] ?? '')
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  Button($r('app.string.sched_send_now')).fontSize(12).height(30)
                    .onClick((): void => this.sendNow(id));
                  Row() {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(17)
                      .fontColor(['#E5484D']);
                  }
                  .width(34).height(34).borderRadius(17)
                  .justifyContent(FlexAlign.Center)
                  .onClick((): void => this.remove(id));
                }
                .width('100%').padding({ top: 6, bottom: 6 });
              }
            }, (id: number): string => `scheduled_${id}`);
          }
          .constraintSize({ maxHeight: 320 });
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 24 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 16, topRight: 16 });
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000');
  }
}

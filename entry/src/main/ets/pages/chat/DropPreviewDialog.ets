import { ComponentContent, UIContext } from '@kit.ArkUI';
import { SharedItem, SharedPayload } from '../../util/sharedContent';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

export interface DropSendResult {
  remaining: SharedPayload | null;
  uncertain: boolean;
  error: string;
}

@Component
export struct DropPreviewDialog {
  onClose: () => void = (): void => {};
  payload: SharedPayload = { caption: '', media: [] };
  target: string = '';
  active: () => boolean = (): boolean => false;
  onSend: (payload: SharedPayload) => Promise<DropSendResult> = async (): Promise<DropSendResult> => {
    return { remaining: null, uncertain: false, error: '' };
  };
  @State caption: string = '';
  @State view: SharedPayload = { caption: '', media: [] };
  @State error: string = '';
  @State uncertain: boolean = false;
  @State sending: boolean = false;
  @StorageProp('appIsForeground') @Watch('onForeground') foreground: boolean = true;
  @StorageProp('tdSessionEpoch') @Watch('close') epoch: number = 0;
  aboutToAppear(): void { this.caption = this.payload.caption; this.view = this.payload; }
  private close(): void { this.onClose(); }
  private onForeground(): void { if (!this.foreground) { this.close(); } }
  private send(): void {
    if (this.sending || this.uncertain || !this.foreground || !this.active()) { this.close(); return; }
    this.sending = true;
    this.onSend({ caption: this.caption, media: this.view.media }).then((result: DropSendResult): void => {
      if (result.remaining === null || !this.active()) { this.close(); return; }
      this.view = result.remaining; this.caption = result.remaining.caption;
      this.error = result.error; this.uncertain = result.uncertain;
    }).catch((): void => { this.uncertain = true; })
      .finally((): void => { this.sending = false; });
  }
  build() {
    Column({ space: 12 }) {
      Text($r('app.string.share_to')).fontSize(16).fontWeight(FontWeight.Medium);
      Text(this.target).fontSize(15).maxLines(2);
      List({ space: 8 }) {
        ForEach(this.view.media, (item: SharedItem): void => {
          ListItem() {
            Row({ space: 10 }) {
              if (item.kind === 'image') {
                Image(`file://${item.uri}`).width(56).height(56).objectFit(ImageFit.Contain).draggable(false);
              } else {
                SymbolGlyph(item.kind === 'video' ? $r('sys.symbol.video') : $r('sys.symbol.doc'))
                  .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]).width(56);
              }
              Text(item.title).fontSize(14).maxLines(2).layoutWeight(1);
            }.width('100%').constraintSize({ minHeight: 56 });
          }
        }, (item: SharedItem): string => item.uri);
      }.height(Math.min(280, this.view.media.length * 64)).width('100%');
      if (this.error !== '') { Text(this.error).fontSize(13).fontColor(COLOR_TEXT_SECONDARY); }
      if (this.uncertain) { Text($r('app.string.share_result_unknown')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY); }
      TextArea({ text: this.caption }).height(80).enabled(!this.sending).allowDrop(null)
        .onChange((value: string): void => { this.caption = value; });
      Row({ space: 12 }) {
        Button($r('app.string.cancel')).layoutWeight(1).enabled(!this.sending)
          .onClick((): void => { this.close(); });
        Button($r('app.string.send')).layoutWeight(1).backgroundColor(COLOR_PRIMARY).enabled(!this.sending && !this.uncertain)
          .onClick((): void => { this.send(); });
      }.width('100%');
    }.padding(20).width('90%').constraintSize({ maxWidth: 480 })
      .backgroundColor($r('app.color.surface')).borderRadius(24);
  }
}

interface DropPreviewParams {
  payload: SharedPayload;
  target: string;
  active: () => boolean;
  onSend: (payload: SharedPayload) => Promise<DropSendResult>;
  onClose: () => void;
}

@Builder
function dropPreviewLayer(params: DropPreviewParams) {
  DropPreviewDialog({ payload: params.payload, target: params.target, active: params.active,
    onSend: params.onSend, onClose: params.onClose });
}

export function openDropPreview(ui: UIContext, payload: SharedPayload, target: string,
  active: () => boolean, send: (payload: SharedPayload) => Promise<DropSendResult>,
  onClosed: () => void): () => void {
  let content: ComponentContent<DropPreviewParams> | null = null;
  let opened = false;
  let closeRequested = false;
  let sending = false;
  const close = (): void => {
    closeRequested = true;
    if (content !== null && opened) {
      ui.getPromptAction().closeCustomDialog(content).catch((): void => {});
    }
  };
  const params: DropPreviewParams = { payload: payload, target: target, active: active, onClose: close,
    onSend: async (pending: SharedPayload): Promise<DropSendResult> => {
      sending = true;
      try { return await send(pending); } finally { sending = false; }
    } };
  const node = new ComponentContent(ui, wrapBuilder(dropPreviewLayer), params);
  content = node;
  const dispose = (): void => {
    if (content === null) { return; }
    content = null; node.dispose(); onClosed();
  };
  ui.getPromptAction().openCustomDialog(node, {
    autoCancel: false, alignment: DialogAlignment.Center,
    onWillDismiss: (action: DismissDialogAction): void => { if (!sending) { action.dismiss(); } },
    onDidDisappear: dispose
  }).then((): void => {
    opened = true;
    if (closeRequested || !active()) { close(); }
  }).catch((): void => { dispose(); });
  return close;
}

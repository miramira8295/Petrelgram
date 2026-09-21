// 全屏编辑（反馈②「输入框无全屏编辑功能」）。
//
// 【为什么是"编辑同一段草稿"而不是"另开一个编辑器"】改完要能回到输入条继续
// 挑表情、加附件、选回复对象。所以这里每敲一下就把文字回写给输入条（onCommit），
// 关掉面板等于什么都没发生——不存在"改了半天没保存"这种失败模式，也不需要
// 一个"放弃修改"的确认框。
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@ComponentV2
export struct ComposerFullscreenSheet {
  // 打开那一刻的正文。面板内部自己持有编辑中的值：把 @Param 直接喂回
  // TextArea 会让每次 onCommit 反弹回来重设一次 text，光标被丢到末尾
  // （和⑤那个光标乱跳是同一类问题）。
  @Param initialText: string = '';
  @Param placeholder: string = '';
  @Param maxLength: number = 4096;
  @Param accentColor: ResourceColor = Color.Blue;
  @Event onCommit: (text: string) => void = (): void => {};
  @Event onSend: () => void = (): void => {};

  @Local private text: string = '';
  private controller: TextAreaController = new TextAreaController();

  aboutToAppear(): void {
    this.text = this.initialText;
  }

  build() {
    Column() {
      // 【这里只剩字数，关闭交给 bindSheet 的系统 ×】（issue #210，用户定的形态）
      // 原来左上角还有一个「收起」文字按钮：它做的事和系统 × 完全一样——正文每
      // 敲一下就 onCommit 回写草稿，所以无论怎么关，文字都已经在输入框里了。
      // 两个入口摆在同一条边上只是在问用户"这俩有什么区别"。
      Row() {
        Blank();
        Text(`${this.text.length}/${this.maxLength}`)
          .fontSize(13)
          .fontColor(this.text.length >= this.maxLength ? Color.Red : COLOR_TEXT_SECONDARY);
      }
      .width('100%').height(40)
      .alignItems(VerticalAlign.Center);

      TextArea({ text: this.text, placeholder: this.placeholder, controller: this.controller })
        .width('100%').layoutWeight(1)
        .maxLength(this.maxLength)
        .fontSize(16)
        .fontColor(COLOR_TEXT_PRIMARY)
        .caretColor(this.accentColor)
        .backgroundColor(Color.Transparent)
        .padding({ left: 2, right: 2, top: 6, bottom: 6 })
        .barState(BarState.Auto)
        .key('chat_composer_fullscreen')
        .defaultFocus(true)
        .onChange((value: string): void => {
          this.text = value;
          this.onCommit(value);
        });

      // 【底部只有发送】原来还并排一个「完成」，它和左上角「收起」调的是同一个
      // onClose——三个按钮两种叫法一件事，用户直接说"功能好像也没啥用"。
      Button($r('app.string.send'))
        .fontSize(16).fontColor(Color.White)
        .backgroundColor(this.accentColor)
        .width('100%').height(44).borderRadius(12)
        .enabled(this.text.trim() !== '')
        .onClick((): void => {
          // 先把最后一次改动交回输入条，再让页面走它自己的发送路径
          // （附件、回复、编辑态都挂在那条路上，这里不重复实现）。
          this.onCommit(this.text);
          this.onSend();
        })
        .margin({ top: 10 });
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 16 });
  }
}

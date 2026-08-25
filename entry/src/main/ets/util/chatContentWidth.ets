// 聊天内容列的宽度（vp）。
//
// **为什么不能用 screenWidthVp。** 那是窗口宽。分栏之前它就是聊天页的宽，
// 分栏之后聊天页只有右栏那么宽（MatePad Pro 13：窗口 1440vp，右栏 960vp）。
// 气泡、媒体框、相册占位一直按窗口宽算，于是 bubbleMaxWidth = 0.78×1440 =
// 1123vp，比整个右栏还宽——「字多的文本框右侧显示不全」（issue #107）。
// 同一根因的另一半是壁纸按窗口宽铺、溢出到左栏吃触摸（#108/#109），见
// ChatBackdrop。
//
// 由 ChatBackdrop 量到后发布：它是铺满聊天列的那一层，width('100%')，量到的
// 就是内容列宽；而且它本来就在量（修 #108 时加的），不必再让 ChatPage 多一个
// onAreaChange。放进 AppStorage 而不是一路 @Prop 传下去：气泡有三种实现、
// 相册数据源在 UI 树之外算占位高，逐个传等于改十几处签名。
//
// 手机单栏下它恒等于窗口宽，行为逐字不变。
export const CHAT_CONTENT_WIDTH_KEY: string = 'chatContentWidthVp';

// 当前内容列宽。还没发布过（第一帧之前、或在聊天页之外算占位）时退回窗口宽
// ——那正是此前一直在用的值，不会比以前更差。
export function chatContentWidth(): number {
  const published: number = AppStorage.get<number>(CHAT_CONTENT_WIDTH_KEY) ?? 0;
  if (published > 0) {
    return published;
  }
  return AppStorage.get<number>('screenWidthVp') ?? 0;
}

// 同值不写：AppStorage 即便同值也会惊动全部订阅方，而 onAreaChange 在键盘
// 升降、分栏拖动时会连着来几次。
export function publishChatContentWidth(widthVp: number): void {
  if (!(widthVp > 0)) {
    return;
  }
  if (AppStorage.get<number>(CHAT_CONTENT_WIDTH_KEY) !== widthVp) {
    AppStorage.setOrCreate<number>(CHAT_CONTENT_WIDTH_KEY, widthVp);
  }
}

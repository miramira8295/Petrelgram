// 「这次旁路更新是不是译文到货」的判据。纯函数。
//
// 【为什么需要单独判】messageRowPresentationChannel 是**所有**展示态更新的公共
// 通道：下载完成/失败、缩略图路径、发送态、译文，都从这一条进来
// （见那个文件的头注释）。给译文加出现动画时，不能把整条通道都包进 animateTo
// ——那样一次下载进度跳动也会让气泡跟着动一下。
//
// 所以只在**译文这一维真的变了**的时候才动画。

export interface TranslationPresentation {
  text: string;
  hidden: boolean;
}

// 译文从无到有、或者被用户折叠/展开——这两种才值得动画。
// 译文内容本身变了（重新翻译成另一种语言）也算。
export function translationLanded(before: TranslationPresentation,
  after: TranslationPresentation): boolean {
  return before.text !== after.text || before.hidden !== after.hidden;
}

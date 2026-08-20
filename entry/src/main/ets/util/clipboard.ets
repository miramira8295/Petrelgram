// 往剪贴板放一段纯文本，成功后提示一句。
//
// 会话页里有六处要复制（号码、验证码、名片、消息正文、代码块…），此前各自
// 调一遍剪贴板 API 是不现实的，所以本来就收在一个私有方法里；它不碰任何页面
// 状态，放在页面里只是历史原因。

import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

export function copyPlainText(text: string, successMessage: ResourceStr): void {
  // 空串不进剪贴板，也不弹提示——否则用户会以为复制成功了。
  if (text === '') {
    return;
  }
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  pasteboard.getSystemPasteboard().setData(data).then((): void => {
    promptAction.showToast({ message: successMessage, duration: 1200 });
  }).catch((e: Object): void => {
    console.error(`copyPlainText failed: ${JSON.stringify(e)}`);
  });
}

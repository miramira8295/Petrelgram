// 翻译在这个会话里到底开没开，以及一次翻译请求该落到哪个显示态。
//
// "开没开"有两个互不相干的真相来源，取哪一个取决于总开关：
//   - 总开关开着：整个 app 都翻，会话级别只剩"排除名单"（本地存的 optOut）；
//   - 总开关关着：会话自己的启用位 —— 服务端的 chat.is_translatable **或**
//     本地的加入名单，任一为真即算开。本地那一份是必需的：写服务端靠的是
//     toggleChatIsTranslatable，那是 Telegram 的自动翻译能力（会员相关），
//     非会员账号未必落盘、失败也不一定报错，用户看到的就是"这次开了，下次
//     进来又是关的"。本地记一份，谁都不依赖。
// 两者的极性是反的——一个是"排除"，一个是"启用"。这里最容易写错的就是在
// 总开关模式下忘了取反，表现为开关点一下就跳回去。
//
// 抽出来是因为同一份判断在页面里出现过三次（读取、切换、切换后的善后），
// 每次都手写一遍这个三元表达式。

export const TRANSLATE_LOADING: string = 'loading';
export const TRANSLATE_DONE: string = 'done';
export const TRANSLATE_FAILED: string = 'failed';
export const TRANSLATE_EMPTY: string = 'empty';

export function translationActive(
  globalEnabled: boolean, chatOptOut: boolean, chatIsTranslatable: boolean,
  chatOptIn: boolean = false
): boolean {
  return globalEnabled ? !chatOptOut : (chatIsTranslatable || chatOptIn);
}

// 用户在这个会话里点了"翻译"开关之后，该往哪个字段写、写什么。
// 总开关模式下写的是排除名单（取反），否则写会话自己的启用位。
export interface TranslateToggle {
  // 切换后是否处于"翻译中"。
  active: boolean;
  // 总开关模式：要写进本地排除名单的值。
  optOut: boolean;
  // 非总开关模式：要发给服务端的 is_translatable。
  translatable: boolean;
  // 走哪一路。分开表达，免得调用方再判一次总开关。
  writesOptOut: boolean;
}

export function toggleTranslation(
  globalEnabled: boolean, chatOptOut: boolean, chatIsTranslatable: boolean,
  chatOptIn: boolean = false
): TranslateToggle {
  const next: boolean =
    !translationActive(globalEnabled, chatOptOut, chatIsTranslatable, chatOptIn);
  return {
    active: next,
    optOut: !next,
    translatable: next,
    writesOptOut: globalEnabled
  };
}

// 一次翻译请求回来之后落到哪个显示态。null 是真失败；空串和"跟原文一模一样"
// 都算没东西可看——后者是服务端对已经是目标语言的文本的常见回法，当成成功
// 展示会让用户以为翻译坏了。
export function sheetStateOf(text: string | null, original: string): string {
  if (text === null) {
    return TRANSLATE_FAILED;
  }
  return (text === '' || text === original) ? TRANSLATE_EMPTY : TRANSLATE_DONE;
}

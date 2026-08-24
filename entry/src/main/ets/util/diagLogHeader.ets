// 诊断日志的环境抬头。

// 抬头里要交代的那几项。抽成接口是为了让拼装逻辑脱离 deviceInfo 可单测——
// deviceInfo 是设备常量，宿主单测里读不到真值。
export interface DiagEnvironment {
  appVersion: string;
  // deviceInfo.sdkApiVersion。**这一项是本文件存在的理由**：多个功能按它开关
  // （沉浸光感要 26、桌面图标自选要 26、半模态生命周期联动要 20），用户报
  // 「某个设置不见了」时，不知道这个数就无从判断是设备不够格还是真的坏了。
  // issue #123 正是这样一份日志：24 行里没有任何一项能回答「这台机器是几」。
  apiVersion: number;
  // 机型与系统版本。同一个 API 版本在不同机型上仍有差异（比如有没有 VP9
  // 解码器），报上来的问题常常要按机型分组才看得出规律。
  deviceModel: string;
  osFullName: string;
}

// 拼成日志开头的几行。
//
// **英文**：这几行是给维护者看的机器信息，不是界面文案，没有本地化的意义；
// 而且日志正文里的诊断行本来就全是英文，抬头跟着走读起来才连贯。
//
// **只放设备与版本，不放任何身份信息**——不取序列号、UDID、账号、手机号。
// 这份文件是用户自己导出去发给别人的，多一项标识就多一分它被转发出去之后
// 追得到人的可能。机型和系统版本在任何一张截图的状态栏里也看得出来，属于
// 用户已经在公开的信息。
export function diagLogHeader(env: DiagEnvironment): string {
  const unknown: string = 'unknown';
  const lines: string[] = [
    '=== Petrelgram diagnostics ===',
    `app: ${env.appVersion === '' ? unknown : env.appVersion}`,
    `api: ${env.apiVersion > 0 ? `${env.apiVersion}` : unknown}`,
    `model: ${env.deviceModel === '' ? unknown : env.deviceModel}`,
    `os: ${env.osFullName === '' ? unknown : env.osFullName}`,
    '=============================='
  ];
  return `${lines.join('\n')}\n\n`;
}

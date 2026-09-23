import { BreakpointType } from './layoutBreakpoint';

// 大屏上消息正文适度放大（官方多设备适配规格 SPEC-13，2026-09-23 用户确认实施）。
//
// P0 上限：折叠屏展开态（md）≤ 1.2 倍，平板（lg 起）≤ 1.5 倍，且都不小于 1 倍。
// 取偏保守的 1.1 / 1.2：放大是为了远一点的阅读距离，不是为了把字铺满大屏。
//
// **只作用在会话环境镜像上**（chatEnvMirror 里算 chatEnv.msgTextSize）：AppStorage 里
// 存的仍是用户在设置里拖出来的原值，设置页的滑块与预览照旧显示原值。
// 会话列表行不走这里：平板分栏时它已经换成宽松档（util/chatRowMetrics）。

export const TEXT_SCALE_CAP_FOLD: number = 1.2;
export const TEXT_SCALE_CAP_TABLET: number = 1.5;

const MSG_TEXT_SCALE: BreakpointType<number> = new BreakpointType<number>(1, 1.1, 1.2);

export function msgTextScale(widthBp: number): number {
  return MSG_TEXT_SCALE.getValue(widthBp);
}

// 半 vp 取整：乘出来的小数（17.6、19.2）没有意义，只会让行高估算和实排差一点点。
export function scaledMsgTextSize(raw: number, widthBp: number): number {
  if (!(raw > 0)) {
    return raw;
  }
  return Math.round(raw * msgTextScale(widthBp) * 2) / 2;
}

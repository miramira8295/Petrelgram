import { ROW_PAD_V } from './theme';

// 会话行的两套尺寸（2026-09-18）。
//
// 手机（含平板「强制单栏」）用紧凑档 60，平板分栏时左栏窄、行又多，保留原来的
// 72——判据沿用 util/layoutBreakpoint.isSplitByBreakpoint，和 dock 那次「只分手机与平板分栏、
// 强制单栏算手机」是同一条线，不另立标准。
//
// 【四个数是一组的，别单独改】撑高一行的不是头像而是**文字那一列**：
//   头像列   = avatar + ROW_PAD_V * 2
//   文字列   ≈ 标题字号(17) + titleGap + previewFont，再加 ROW_PAD_V * 2
// 两列都必须落在 minHeight 以内，否则行会被文字顶回去、minHeight 形同虚设
// （72 那一版就是这样：改小 minHeight 而不动文字，行高纹丝不动）。
//
// 「消息预览显示两行」（KEY_THREE_LINES）打开时行本来就该更高，minHeight 不拦它。

export interface ChatRowSpec {
  minHeight: number;
  avatar: number;
  // 标题与预览之间。
  titleGap: number;
  previewFont: number;
}

// 手机档：62 = 46 + 8 + 8；文字列 17 + 3 + 13 = 33，加 16 = 49，卡得进去。
const CHAT_ROW_COMPACT: ChatRowSpec = {
  minHeight: 62, avatar: 46, titleGap: 3, previewFont: 13
};
// 平板分栏档：72 = 56 + 8 + 8；文字列 17 + 6 + 14 = 37，加 16 = 53。
const CHAT_ROW_ROOMY: ChatRowSpec = {
  minHeight: 72, avatar: 56, titleGap: 6, previewFont: 14
};

export function chatRowSpec(split: boolean): ChatRowSpec {
  return split ? CHAT_ROW_ROOMY : CHAT_ROW_COMPACT;
}

// 头像那一列占的高度。单测拿它钉住「头像 + 上下内边距 == 行高」这条不变式。
export function chatRowAvatarColumnHeight(spec: ChatRowSpec): number {
  return spec.avatar + ROW_PAD_V * 2;
}

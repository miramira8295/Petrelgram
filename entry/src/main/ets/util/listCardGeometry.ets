import { HOME_CARD_MARGIN_PHONE_VP, PAGE_MARGIN_PHONE_VP } from './pageMargin';

// 列表卡片的横向几何：联系人页（整块卡片 + 内列表，ContactsPage / ContactRowView）与首页会话卡片
// （一行一张，ChatRow / MainTabBody 归档行）共用同一条内容起始线。
//
// 2026-09-15 用户先要首页和联系人统一成整块卡片，同日改回首页一行一张卡片，但头像仍要对齐顶部标题
// （「之前平铺的状态就是对齐的」——整块卡片那版头像在 12 + 4 = 16vp，用户真机看过是齐的）。
//
// 起始线 = 卡片外边距 + 卡片内缩：底色比内容往外多铺 4vp，头像、图标、卡片标题都落在同一条线上。这条线要和
// HDS 标题栏里标题的起始位置重合——真机量出来对不上，只改 LIST_CARD_MARGIN_VP / LIST_CARD_INSET_VP 两个数。

// 卡片外沿离屏幕边（手机值）。大屏按断点加宽，页面上用的是 util/pageMargin.pageMarginVp。
export const LIST_CARD_MARGIN_VP: number = PAGE_MARGIN_PHONE_VP;
// 头像（行首内容）离卡片外沿。
export const LIST_CARD_INSET_VP: number = 4;
// 行尾内容离卡片外沿。
export const LIST_CARD_TRAIL_VP: number = 14;
// 首页会话卡片（一行一张）：卡片外沿 6、头像内缩 8。
//
// 2026-09-18 用户把外沿从 8 收到 4、当天又放回 6（上下间距同步，见 ChatRow 的 margin），
// **并明确选择头像跟着一起左移**：头像落在 6 + 8 = 14vp，不再和顶部大标题的 16vp
// 起始线重合——那条对齐是 09-15 定的，这次有意放弃，换卡片内四周 8vp 的均匀留白。
// 所以下面那条 listContentStartVp() 只管联系人页，首页不再参与。
// 手机值；大屏按断点加宽，卡片上用的是 util/pageMargin.homeCardMarginVp（2026-09-23 SPEC-07）。
export const HOME_CARD_MARGIN_VP: number = HOME_CARD_MARGIN_PHONE_VP;
export const HOME_CARD_INSET_VP: number = 8;

// 内容起始线离屏幕边。
export function listContentStartVp(): number {
  return LIST_CARD_MARGIN_VP + LIST_CARD_INSET_VP;
}

// 行内分隔线的起点（相对卡片外沿）：跳过头像和它后面的间距，从文字列开始。
export function cardDividerStartVp(avatarSize: number, gap: number): number {
  return LIST_CARD_INSET_VP + avatarSize + gap;
}

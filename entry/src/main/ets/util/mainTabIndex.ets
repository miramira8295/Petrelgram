// 主页四个页签的「逻辑下标 ↔ 物理下标」映射。
//
// **为什么需要它。** 迁到 HdsTabs 之后，底栏是 HDS 按 **TabContent 的个数**均分
// 画出来的——把隐藏那一格的 tabBar 画成空**不会去掉槽位**，屏幕上就是「聊天」
// 和「设置」之间空出一大块（真机 2026-09-03 截图）。要去掉槽位只能不渲染那个
// TabContent，而那会让后面的下标整体前移。
//
// 逻辑下标（0 会话 / 1 联系人 / 2 设置 / 3 我的）是**全应用的契约**：它存在
// AppStorage 的 mainTabIndex 里跨重建存活，profileNav / chatNav / settingsNav
// 三个文件都按这套编号往里推，MyProfilePage 也用 `tab === 3` 判活跃。所以
// 逻辑编号一个都不能动，只在**喂给 HdsTabs 和读它的 onChange 时**做一次换算。
//
// 联系人关掉时：物理 0=会话、1=设置、2=我的。

export const TAB_CHATS: number = 0;
export const TAB_CONTACTS: number = 1;
export const TAB_SETTINGS: number = 2;
export const TAB_PROFILE: number = 3;

// 逻辑 → 物理。联系人开着时是恒等映射。
export function physicalTabIndex(logical: number, contactsShown: boolean): number {
  if (contactsShown) {
    return logical;
  }
  if (logical <= TAB_CHATS) {
    return TAB_CHATS;
  }
  // 联系人本身被关掉时没有对应的物理槽位，落到会话——和 MainScreen 原来
  // 「关掉联系人时若正停在它上面就退回会话」的兜底一致。
  if (logical === TAB_CONTACTS) {
    return TAB_CHATS;
  }
  return logical - 1;
}

// 物理 → 逻辑。onChange 报的是物理下标。
export function logicalTabIndex(physical: number, contactsShown: boolean): number {
  if (contactsShown) {
    return physical;
  }
  if (physical <= TAB_CHATS) {
    return TAB_CHATS;
  }
  return physical + 1;
}

// 实际渲染几个 TabContent。
export function visibleTabCount(contactsShown: boolean): number {
  return contactsShown ? 4 : 3;
}

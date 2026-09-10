import { AlbumGroup } from './collapseAlbums';

// Repeat 的**模板名**：它分的是 ListItem 外壳的缓存池。
//
// 【和 rowReuseId 的分工，别混】
//   · rowReuseId  → 分**内层气泡**（@ReusableV2）的池，取值空间开放（十几个
//     结构布尔的组合），任意字符串都行。
//   · rowTemplateId → 分 **ListItem 外壳**的池。Repeat 要求每个模板名都**预先
//     用 .template() 注册**，所以它必须是**可枚举的小集合**。
// 2026-09-10 我一度拿前者的取值空间去否定后者，是把两件事搞混了。
//
// 【外壳到底有几种形状】timelineRow 里真正影响外壳结构的只有三件事：
//   ① 是不是首屏占位行（deferred：只画一个定高 Column，别的都没有）
//   ② 多选让位栏在不在（多一列 20vp 的勾选框）
//   ③ 里面是轻量文本气泡还是富气泡（两条完全不同的子树）
// 三者组合共 5 种（占位行不受多选影响），全部枚举得出来。
//
// 【漏一个的后果】装过富气泡的壳被拿去装轻量文本行——正是要治的那类串行。
// 所以新增结构分支时**必须同步加模板名**，宁可多分一档也不要合并。

export const ROW_TEMPLATE_DEFERRED: string = 'deferred';
export const ROW_TEMPLATE_PLAIN: string = 'plain';
export const ROW_TEMPLATE_PLAIN_SEL: string = 'plain-sel';
export const ROW_TEMPLATE_RICH: string = 'rich';
export const ROW_TEMPLATE_RICH_SEL: string = 'rich-sel';

// 注册用的全集。调用方遍历它逐个 .template()，避免"加了枚举忘了注册"。
export const ROW_TEMPLATE_IDS: string[] = [
  ROW_TEMPLATE_DEFERRED, ROW_TEMPLATE_PLAIN, ROW_TEMPLATE_PLAIN_SEL,
  ROW_TEMPLATE_RICH, ROW_TEMPLATE_RICH_SEL
];

export function rowTemplateId(
  group: AlbumGroup, lightweight: boolean, selectionGutter: boolean
): string {
  if (group.initialDeferred === true) {
    return ROW_TEMPLATE_DEFERRED;
  }
  if (lightweight) {
    return selectionGutter ? ROW_TEMPLATE_PLAIN_SEL : ROW_TEMPLATE_PLAIN;
  }
  return selectionGutter ? ROW_TEMPLATE_RICH_SEL : ROW_TEMPLATE_RICH;
}

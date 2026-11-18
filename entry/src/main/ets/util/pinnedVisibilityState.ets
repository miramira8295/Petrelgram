// 置顶条显隐的持久化键。设置页那一行、聊天页菜单项、顶栏箭头全部落到这一条：
// 唯一写入口是 AppSettings.setBoolean(key, value)（AppStorage + @Trace 镜像 + 磁盘）。
export const KEY_HIDE_PINNED_DEFAULT: string = 'hidePinnedByDefault';

@ObservedV2
export class PinnedVisibilityDefaults {
  @Trace hidden: boolean = false;
}

export const pinnedVisibilityDefaults: PinnedVisibilityDefaults = new PinnedVisibilityDefaults();

// 置顶条显隐是**一个全局开关**（2026-11-18 用户口径：外观设置里的开关、聊天页
// 功能菜单里的「隐藏置顶」、聊天页顶栏那颗上/下箭头，是同一个状态的三个入口，
// 状态必须同步）。
//
// 迁移前这里还有一层按 account:chatId 的覆写（PinnedVisibilityStorage）。只要某个
// 会话被点过一次，覆写就永远盖住全局值——设置页关掉置顶条，那个会话仍然不跟着
// 变，三个入口于是各说各话。现在这一层取消：所有会话统一读
// pinnedVisibilityDefaults.hidden，写只走 AppSettings.setBoolean。
//
// 旧版本写进 pinned_visibility 这个 preferences 文件的 per-chat 记录不做清理，
// 也不再被读——它们不会复活，只是留在磁盘上。
@ObservedV2
export class PinnedVisibility {
  get hidden(): boolean {
    return pinnedVisibilityDefaults.hidden;
  }
}

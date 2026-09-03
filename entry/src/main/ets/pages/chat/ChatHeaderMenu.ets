import { ComponentContent, UIContext } from '@kit.ArkUI';
import { actionMenuRow } from './ActionMenuRow';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

let nextMenuId: number = 1;

export function createChatHeaderMenuId(): string {
  return `chat_header_menu_${nextMenuId++}`;
}

export interface ChatHeaderMenuParams {
  isMuted: boolean;
  muteUpdating: boolean;
  isGroup: boolean;
  isChannel: boolean;
  liveLocationActive: boolean;
  translationActive: boolean;
  canClearHistory: boolean;
  canLeaveChat: boolean;
  onSearch: () => void;
  onToggleMute: () => void;
  onAddToFolder: () => void;
  onAutoDelete: () => void;
  onJumpToDate: () => void;
  onStopLocation: () => void;
  onToggleTranslation: () => void;
  onClearHistory: () => void;
  onLeaveChat: () => void;
}

@Component
struct ChatHeaderMenu {
  isMuted: boolean = false;
  muteUpdating: boolean = false;
  isGroup: boolean = false;
  isChannel: boolean = false;
  liveLocationActive: boolean = false;
  translationActive: boolean = false;
  canClearHistory: boolean = false;
  canLeaveChat: boolean = false;
  onSearch: () => void = (): void => {};
  onToggleMute: () => void = (): void => {};
  onAddToFolder: () => void = (): void => {};
  onAutoDelete: () => void = (): void => {};
  onJumpToDate: () => void = (): void => {};
  onStopLocation: () => void = (): void => {};
  onToggleTranslation: () => void = (): void => {};
  onClearHistory: () => void = (): void => {};
  onLeaveChat: () => void = (): void => {};

  build() {
    Column() {
      // **分隔线一律跟在它所分隔的那一组后面，条件项自带自己的那一条。**
      // 原来是"每项之间无条件插一条"，于是非群聊时 if(isGroup) 两侧的两条会
      // 并排出现，画成一条双线。
      actionMenuRow('sys.symbol.magnifyingglass', str('cp_search'), false, this.onSearch);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        this.muteUpdating ? str('cp_updating_notifications') :
          (this.isMuted ? str('cp_unmute') : str('cp_mute')),
        false, this.onToggleMute);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      if (this.isGroup) {
        actionMenuRow('sys.symbol.folder_badge_plus', str('cl_add_to_folder'), false, this.onAddToFolder);
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
      }
      actionMenuRow('sys.symbol.clock', str('cp_auto_delete'), false, this.onAutoDelete);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.calendar_badge_clock', str('cp_jump_to_date'), false, this.onJumpToDate);
      if (this.liveLocationActive) {
        actionMenuRow('sys.symbol.stop_circle', str('cp_stop_location'), true, this.onStopLocation);
      }
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.translate',
        this.translationActive ? str('cp_translate_chat_off') : str('cp_translate_chat_on'),
        false, this.onToggleTranslation);
      if (this.canClearHistory) {
        actionMenuRow('sys.symbol.xmark_circle', str('cp_clear_history'), false, this.onClearHistory);
      }
      if (this.canLeaveChat) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
        actionMenuRow('sys.symbol.trash',
          this.isChannel ? str('cp_leave_channel') : str('cp_leave_group'), true, this.onLeaveChat);
      }
    }
    // 176 = 左右内边距 16×2 + 图标 19 + 图标与文字间距 14 + 最长中文标签 6 字
    // ×16（「正在更新通知」「添加到文件夹」「清空聊天记录」都是 6 字）≈ 161，
    // 再留 15 的余量。**224 是从消息长按菜单抄来的数**，那个菜单的条目更长；
    // 搬到这里右边就空出一大片（用户报「弹出的菜单有点过于宽」）。
    // 拉丁语系里最长的那两条（Updating notifications）本来在 224 上也放不下、
    // 照样折行，所以这一刀没有让任何语言变差。
    .width(176)
    .padding({ top: 6, bottom: 6 })
    .clip(true);
  }
}

@Builder
function chatHeaderMenuLayer(params: ChatHeaderMenuParams) {
  ChatHeaderMenu({
    isMuted: params.isMuted,
    muteUpdating: params.muteUpdating,
    isGroup: params.isGroup,
    isChannel: params.isChannel,
    liveLocationActive: params.liveLocationActive,
    translationActive: params.translationActive,
    canClearHistory: params.canClearHistory,
    canLeaveChat: params.canLeaveChat,
    onSearch: params.onSearch,
    onToggleMute: params.onToggleMute,
    onAddToFolder: params.onAddToFolder,
    onAutoDelete: params.onAutoDelete,
    onJumpToDate: params.onJumpToDate,
    onStopLocation: params.onStopLocation,
    onToggleTranslation: params.onToggleTranslation,
    onClearHistory: params.onClearHistory,
    onLeaveChat: params.onLeaveChat
  })
}

export class ChatHeaderMenuController {
  private content: ComponentContent<ChatHeaderMenuParams> | null = null;
  private uiContext: UIContext | null = null;
  private pendingAction: (() => void) | null = null;
  private onVisibilityChange: (visible: boolean) => void = (): void => {};

  isOpen(): boolean {
    return this.content !== null;
  }

  open(uiContext: UIContext, targetId: string, topBannerHeight: number, params: ChatHeaderMenuParams,
    onVisibilityChange: (visible: boolean) => void): void {
    if (this.content !== null) {
      return;
    }
    const wrapped: ChatHeaderMenuParams = this.wrapActions(params);
    try {
      const node: ComponentContent<ChatHeaderMenuParams> =
        new ComponentContent(uiContext, wrapBuilder(chatHeaderMenuLayer), wrapped);
      this.content = node;
      this.uiContext = uiContext;
      this.onVisibilityChange = onVisibilityChange;
      this.onVisibilityChange(true);
      uiContext.getPromptAction().openMenu(node, { id: targetId }, {
        mask: false,
        // 右上角目标若沿用默认 BottomLeft 会横向越界，系统改位后 offset 会失效。
        // 明确从目标右下弹出，placement 已计入标题栏，只需再越过 bottomBuilder。
        placement: Placement.BottomRight,
        offset: { x: 0, y: topBannerHeight },
        // ── 照《沉浸光感》最佳实践「菜单栏适配沉浸光感」那段的原文写法 ──
        //
        //   { mask: false, backgroundBlurStyle: BlurStyle.COMPONENT_THICK }
        //   再由 getMaterialOptions 在 API≥26 且设备支持时叠上 systemMaterial
        //
        // 两条要点，我们原来两条都错了：
        //   1. **模糊是基底、无条件给**，不是"有材质就不给"（containerBlur 就是
        //      为这一条加的，见 overlayMaterial）；
        //   2. **官方那份里根本没有 backgroundColor 这一项**。我们显式给
        //      Color.Transparent，很可能正是模糊出不来的原因——它把容器的
        //      背景（模糊就画在那儿）清掉了。所以这里也不设。
        backgroundBlurStyle: containerBlur('menu'),
        systemMaterial: overlayMaterial('menu'),
        onDidDisappear: (): void => { this.finish(node); }
      }).catch((error: Object): void => {
        this.finish(node);
        logE(`ChatHeaderMenu open failed: ${error}`);
      });
    } catch (error) {
      this.onVisibilityChange(false);
      logE(`ChatHeaderMenu create failed: ${error}`);
    }
  }

  close(action?: () => void): void {
    const node: ComponentContent<ChatHeaderMenuParams> | null = this.content;
    const uiContext: UIContext | null = this.uiContext;
    this.pendingAction = action ?? null;
    if (node === null || uiContext === null) {
      this.runPendingAction();
      return;
    }
    try {
      uiContext.getPromptAction().closeMenu(node)
        .then((): void => { this.runPendingAction(); })
        .catch((error: Object): void => {
          this.finish(node);
          logE(`ChatHeaderMenu close failed: ${error}`);
        });
    } catch (error) {
      this.finish(node);
      logE(`ChatHeaderMenu close failed: ${error}`);
    }
  }

  private wrapActions(params: ChatHeaderMenuParams): ChatHeaderMenuParams {
    return {
      isMuted: params.isMuted,
      muteUpdating: params.muteUpdating,
      isGroup: params.isGroup,
      isChannel: params.isChannel,
      liveLocationActive: params.liveLocationActive,
      translationActive: params.translationActive,
      canClearHistory: params.canClearHistory,
      canLeaveChat: params.canLeaveChat,
      onSearch: (): void => { this.close(params.onSearch); },
      onToggleMute: (): void => { this.close(params.onToggleMute); },
      onAddToFolder: (): void => { this.close(params.onAddToFolder); },
      onAutoDelete: (): void => { this.close(params.onAutoDelete); },
      onJumpToDate: (): void => { this.close(params.onJumpToDate); },
      onStopLocation: (): void => { this.close(params.onStopLocation); },
      onToggleTranslation: (): void => { this.close(params.onToggleTranslation); },
      onClearHistory: (): void => { this.close(params.onClearHistory); },
      onLeaveChat: (): void => { this.close(params.onLeaveChat); }
    };
  }

  private finish(node: ComponentContent<ChatHeaderMenuParams>): void {
    if (this.content !== node) {
      return;
    }
    this.content = null;
    this.uiContext = null;
    this.onVisibilityChange(false);
    this.onVisibilityChange = (): void => {};
    node.dispose();
    this.runPendingAction();
  }

  private runPendingAction(): void {
    const action: (() => void) | null = this.pendingAction;
    this.pendingAction = null;
    action?.();
  }
}

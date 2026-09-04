import { ComponentContent, UIContext } from '@kit.ArkUI';
import { actionMenuRow } from './ActionMenuRow';
import { FolderChoice, chatFolderChoices, toggleChatFolder } from '../../store/ChatActions';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { COLOR_BUBBLE_TEXT } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { menuWidthFor } from '../../util/menuWidth';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

let nextMenuId: number = 1;

export const PANEL_MAIN: string = 'main';
export const PANEL_FOLDERS: string = 'folders';

// 子面板最高多少。23 个文件夹一行 44 左右，全展开会顶到屏幕外，所以设上限让它滚。
const FOLDER_PANEL_MAX_H: number = 320;

// 与 actionMenuRow 同一套按压反馈（那边是 @Styles，跨文件用不了，这里同参数复制）。
@Styles
function menuRowNormalStyle() {
  .opacity(1)
  .scale({ x: 1, y: 1 })
}

@Styles
function menuRowPressedStyle() {
  .opacity(0.72)
  .scale({ x: 0.97, y: 0.94 })
}

export function createChatHeaderMenuId(): string {
  return `chat_header_menu_${nextMenuId++}`;
}

export interface ChatHeaderMenuParams {
  chatId: number;
  // 当前显示哪一面板。'folders' = 文件夹子菜单。
  //
  // **为什么是"换一个菜单"而不是就地展开**：菜单走的是 promptAction.openMenu +
  // ComponentContent，弹出那一刻就把尺寸和位置量定了，之后内部 @State 让内容
  // 变高**不会**让菜单跟着重新量——实测点下去 choices=23 都拿到了、folderOpen
  // 也翻了，画面一行没多（被菜单容器裁掉）。所以子菜单只能靠关掉再开一次来
  // 重新量尺寸。顺带也解决了 23 个文件夹塞进下拉菜单的问题：子面板自己滚。
  panel: string;
  onOpenFolders: () => void;
  onBackToMain: () => void;
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
  chatId: number = 0;
  panel: string = 'main';
  onOpenFolders: () => void = (): void => {};
  onBackToMain: () => void = (): void => {};
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

  // 文件夹子面板的勾选状态。面板是每次打开重建的，所以在 aboutToAppear 里播种。
  @State private folderChoices: FolderChoice[] = [];

  aboutToAppear(): void {
    if (this.panel === PANEL_FOLDERS) {
      this.folderChoices = chatFolderChoices(this.chatId);
    }
  }

  private enterFolders(): void {
    if (chatFolderChoices(this.chatId).length === 0) {
      // 一个文件夹都没有时保持老路径：收菜单、由调用方提示「还没有文件夹」。
      this.onAddToFolder();
      return;
    }
    this.onOpenFolders();
  }

  // 勾选就地更新：切完不收面板，用户常要连着改好几个。
  private onFolderTap(id: number): void {
    const next: boolean = toggleChatFolder(this.chatId, id);
    this.folderChoices = this.folderChoices.map((c: FolderChoice): FolderChoice =>
      c.id === id ? { id: c.id, title: c.title, checked: next } : c);
  }

  // 带 ▸ 的父项。和 actionMenuRow 同一套尺寸，只多一个尾部箭头。
  @Builder
  folderParentRow() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.folder_badge_plus')).fontSize(19).fontColor([COLOR_BUBBLE_TEXT]);
      Text(str('cl_add_to_folder')).fontSize(16).fontColor(COLOR_BUBBLE_TEXT).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14).fontColor([COLOR_BUBBLE_TEXT]).opacity(0.5);
    }
    .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .stateStyles({ normal: menuRowNormalStyle, pressed: menuRowPressedStyle })
    .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
    .onClick((): void => { this.enterFolders(); });
  }

  // 子面板的一行：勾选的带 ✓。
  @Builder
  folderChildRow(choice: FolderChoice) {
    Row({ space: 14 }) {
      Text(choice.title).fontSize(16).fontColor(COLOR_BUBBLE_TEXT)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16)
        .fontColor([COLOR_BUBBLE_TEXT])
        .visibility(choice.checked ? Visibility.Visible : Visibility.Hidden);
    }
    .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .stateStyles({ normal: menuRowNormalStyle, pressed: menuRowPressedStyle })
    .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
    .onClick((): void => { this.onFolderTap(choice.id); });
  }

  // 文件夹子面板。23 个文件夹是真实数据（用户实测），所以必须能滚。
  @Builder
  folderPanel() {
    Column() {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(19).fontColor([COLOR_BUBBLE_TEXT]);
        Text(str('cl_add_to_folder')).fontSize(16).fontColor(COLOR_BUBBLE_TEXT)
          .fontWeight(FontWeight.Medium).layoutWeight(1);
      }
      .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
      .alignItems(VerticalAlign.Center)
      .borderRadius(10)
      .stateStyles({ normal: menuRowNormalStyle, pressed: menuRowPressedStyle })
      .onClick((): void => { this.onBackToMain(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      Scroll() {
        Column() {
          ForEach(this.folderChoices, (choice: FolderChoice): void => {
            this.folderChildRow(choice);
          }, (choice: FolderChoice): string => `folder_${choice.id}`);
        }
        .width('100%');
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: FOLDER_PANEL_MAX_H });
    }
  }

  // 菜单里所有可能出现的标签，交给 menuWidthFor 取最宽的那条。
  // 条件项也一并算进去：菜单宽度不该随着"这个会话是不是群"跳来跳去。
  private menuWidth(): number {
    return menuWidthFor([
      str('cp_search'),
      str('cp_updating_notifications'), str('cp_unmute'), str('cp_mute'),
      str('cl_add_to_folder'), str('cp_auto_delete'), str('cp_jump_to_date'),
      str('cp_stop_location'),
      str('cp_translate_chat_off'), str('cp_translate_chat_on'),
      str('cp_clear_history'), str('cp_leave_channel'), str('cp_leave_group')
    ], true);
  }

  build() {
    if (this.panel === PANEL_FOLDERS) {
      Column() {
        this.folderPanel();
      }
      .width(this.menuWidth())
      .padding({ top: 6, bottom: 6 })
      .clip(true);
    } else {
      this.mainPanel();
    }
  }

  @Builder
  mainPanel() {
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
        this.folderParentRow();
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
    // 宽度按**当前语言的实际标签**算，不再写死（见 util/menuWidth）。
    // 写死的 176 是按中文六个字手算的，两个问题：拉丁语系最长的那几条本来就
    // 折行；而「添加到文件夹」那行加了子菜单的 ▸ 之后多占 28，六个字也放不下了
    // （用户实测折行）。上下限 176–280 保住了两头的观感。
    .width(this.menuWidth())
    .padding({ top: 6, bottom: 6 })
    .clip(true);
  }
}

@Builder
function chatHeaderMenuLayer(params: ChatHeaderMenuParams) {
  ChatHeaderMenu({
    chatId: params.chatId,
    panel: params.panel,
    onOpenFolders: params.onOpenFolders,
    onBackToMain: params.onBackToMain,
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
  // 换面板要把菜单关掉重开（尺寸只在弹出那一刻量一次，见 ChatHeaderMenuParams.panel
  // 上的说明），所以打开时的这几个入参必须留着。
  private lastTarget: string = '';
  private lastBanner: number = 0;
  private lastParams: ChatHeaderMenuParams | null = null;

  isOpen(): boolean {
    return this.content !== null;
  }

  open(uiContext: UIContext, targetId: string, topBannerHeight: number, params: ChatHeaderMenuParams,
    onVisibilityChange: (visible: boolean) => void): void {
    if (this.content !== null) {
      return;
    }
    this.lastTarget = targetId;
    this.lastBanner = topBannerHeight;
    this.lastParams = params;
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

  // 切到另一面板：关掉再开一次，让菜单按新内容重新量尺寸。
  //
  // 不走 update()：ComponentContent.update 只换 params，菜单容器的尺寸是弹出
  // 那一刻定死的，内容变高会被裁掉（实测：folderOpen 翻了、23 个选项也拿到了，
  // 画面一行没多）。
  private swapPanel(panel: string): void {
    const base: ChatHeaderMenuParams | null = this.lastParams;
    const uiContext: UIContext | null = this.uiContext;
    const target: string = this.lastTarget;
    const banner: number = this.lastBanner;
    const visibility: (visible: boolean) => void = this.onVisibilityChange;
    if (base === null || uiContext === null) {
      return;
    }
    const next: ChatHeaderMenuParams = base;
    next.panel = panel;
    this.close((): void => {
      this.open(uiContext, target, banner, next, visibility);
    });
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
      chatId: params.chatId,
      panel: params.panel,
      // 面板切换不经过 close(action)：那条路是"收菜单再执行动作"，而这里要的是
      // 换一面板继续开着。
      onOpenFolders: (): void => { this.swapPanel(PANEL_FOLDERS); },
      onBackToMain: (): void => { this.swapPanel(PANEL_MAIN); },
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

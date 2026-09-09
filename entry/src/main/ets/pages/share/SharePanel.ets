import { common, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { initShareHandoff, writeShareHandoff } from '../../services/ShareHandoff';
import { initShareSendMode, readShareSendMode, writeShareSendMode } from '../../services/ShareSendModeStore';
import { ShareSendMode, isAutoSend } from '../../util/shareSendMode';
import { ShareTarget } from '../../util/shareTargets';
import { SharedPayload, previewOf } from '../../util/sharedContent';
import { logE } from '../../util/log';

// 系统分享面板里嵌的那一小块界面。
//
// ⚠️ **独立进程**：没有登录态、没有 TDLib、AppStorage 是空的。这里只做
// "挑一个目标"，挑完把结果写进交接文件并拉起主应用去发（说明见
// shareextension/ShareTargetAbility 的文件头）。
//
// 【为什么不在这里直接发】TDLib 的会话数据库是独占的，第二个进程打开同一个
// 目录会锁冲突。就算能开，登录态、代理、密钥全都要重来一遍——那是把半个
// 应用搬进分享面板。
//
// 【为什么样式全是手写的基础组件】这个进程里不能碰 HDS / 材质那一套：
// 它们在模块级解引用 ArkUI 符号，扩展进程加载不了就直接崩，用户看到的是
// "分享面板里点了没反应"。和 FaultLogExtensionAbility 是同一条约束。

const AVATAR_SIZE: number = 52;
// 一行几个。系统给的这个扩展窗口是整块的、尺寸不归我们调（
// UIExtensionContentSession 没有改窗口大小的接口），横排一行只占顶上一条，
// 底下一大片是空的。改成网格把这片空间用起来，顺带一次能看见 12 个而不是 5 个。
const GRID_COLUMNS: number = 4;

// 首字母底色。扩展进程里不能 import 应用那套配色（会把 ArkUI 之外的依赖拖进
// 这个进程，见 ShareTargetAbility 文件头），所以自带一份小调色板，按 chatId
// 取——同一个会话每次打开颜色一致。
const TINTS: string[] = ['#5C9CE5', '#E5735C', '#5CB85C', '#B85CE5', '#E5A85C', '#5CD3E5'];

function avatarTint(chatId: number): string {
  const index: number = Math.abs(chatId) % TINTS.length;
  return TINTS[index];
}

const storage: LocalStorage = LocalStorage.getShared();

@Entry(storage)
@Component
struct SharePanel {
  @LocalStorageProp('shareTargets') targets: ShareTarget[] = [];
  // 初值必须和 ability 里塞进 LocalStorage 的那个**同类型且非 null**，
  // 理由见 ShareTargetAbility 里那段说明。
  @LocalStorageProp('sharePayload') payload: SharedPayload = { caption: '', media: [] };
  @LocalStorageProp('shareReady') ready: boolean = false;
  @LocalStorageProp('shareFailed') failed: boolean = false;
  // 由 ability 塞进来。普通字段：整个界面生命周期内不变。
  private session: UIExtensionContentSession | null = null;
  private ctx: common.UIExtensionContext | null = null;
  @State private sending: boolean = false;
  // 点头像之后干什么。用户选过就记住（落文件，见 util/shareSendMode）。
  @State private mode: ShareSendMode = 'send';

  aboutToAppear(): void {
    this.session = storage.get<UIExtensionContentSession>('shareSession') ?? null;
    this.ctx = storage.get<common.UIExtensionContext>('shareContext') ?? null;
    const filesDir: string = this.ctx?.getApplicationContext().filesDir ?? '';
    initShareHandoff(filesDir);
    initShareSendMode(filesDir);
    this.mode = readShareSendMode();
  }

  private preview(): string {
    return previewOf(this.payload);
  }

  // 有东西可交接。载荷解析完且确实带了内容才算。
  private usable(): boolean {
    return this.ready && !this.failed &&
      (this.payload.caption !== '' || this.payload.media.length > 0);
  }

  // 右上角那行状态。三态：解析中 / 失败 / 内容摘要。
  private statusText(): ResourceStr {
    if (!this.ready) {
      return $r('app.string.share_preparing');
    }
    if (this.failed) {
      return $r('app.string.share_failed');
    }
    return this.preview();
  }

  // 选中一个目标（chatId 为 0 = 用户点了"在应用中选择"）。
  // 写交接文件 → 拉起主应用 → 关掉面板。
  private handOff(chatId: number): void {
    if (this.sending || !this.usable()) {
      return;
    }
    this.sending = true;
    // chatId 为 0 是"在应用中选择…"，那条路本来就要进应用挑会话，不自动发。
    const ok: boolean = writeShareHandoff({
      chatId: chatId,
      autoSend: chatId !== 0 && isAutoSend(this.mode),
      payload: this.payload
    });
    if (!ok) {
      this.sending = false;
      return;
    }
    const want: Want = {
      bundleName: this.ctx?.extensionAbilityInfo?.bundleName ?? '',
      abilityName: 'EntryAbility',
      parameters: { 'shareHandoff': true }
    };
    this.ctx?.startAbility(want).then((): void => {
      this.session?.terminateSelf();
    }).catch((e: Object): void => {
      this.sending = false;
      logE(`SharePanel.startAbility failed: ${e}`);
    });
  }

  private pickMode(next: ShareSendMode): void {
    if (this.mode === next) {
      return;
    }
    this.mode = next;
    writeShareSendMode(next);
  }

  @Builder
  modeChip(label: ResourceStr, value: ShareSendMode) {
    Text(label)
      .fontSize(12)
      .fontColor(this.mode === value ? Color.White : '#5A5A5F')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.mode === value ? '#3478F6' : '#E3E3E8')
      .onClick((): void => this.pickMode(value));
  }

  @Builder
  targetCell(target: ShareTarget) {
    Column({ space: 6 }) {
      // 首字母垫在底下、头像盖在上面——和应用里的 AvatarView 同一做法：
      // 文件还没解码完、或者已经被缓存清理清掉时，露出来的是一颗有颜色的圆，
      // 而不是一个洞。快照里的路径是写快照那一刻的，之后 TDLib 完全可能把
      // 那张图清掉，所以这一层不是可选的。
      Stack() {
        Text(target.initials)
          .fontColor(Color.White)
          .fontSize(AVATAR_SIZE * 0.4)
          .fontWeight(FontWeight.Medium)
          .width(AVATAR_SIZE).height(AVATAR_SIZE)
          .align(Alignment.Center).textAlign(TextAlign.Center)
          .borderRadius(AVATAR_SIZE / 2)
          .backgroundColor(avatarTint(target.chatId));
        if (target.avatarPath !== '') {
          // **objectFit 必须显式给 Cover。** 头像图未必是方的，按默认那档
          // 会上下留边——真机上看到的就是"灰黄分层的圆"，不是加载失败。
          Image(`file://${target.avatarPath}`)
            .objectFit(ImageFit.Cover)
            .width(AVATAR_SIZE).height(AVATAR_SIZE)
            .borderRadius(AVATAR_SIZE / 2)
            .draggable(false);
        }
      }
      .width(AVATAR_SIZE).height(AVATAR_SIZE);
      // 「我的收藏」要换名字：TDLib 给的标题是自己的昵称，直接显示用户
      // 根本认不出这是收藏（真机反馈）。判据在 ChatEntry.isSavedMessages。
      Text(target.isSavedMessages ? $r('app.string.cl_saved_messages') : target.title)
        .fontSize(11)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .onClick((): void => this.handOff(target.chatId));
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.share_to'))
          .fontSize(16).fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.statusText())
          .fontSize(12).fontColor('#8A8A8E')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '55%' })
      }
      .width('100%')

      if (this.targets.length === 0) {
        Column() {
          Text($r('app.string.share_no_targets'))
            .fontSize(13).fontColor('#8A8A8E')
            .width('100%').textAlign(TextAlign.Center)
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.targets, (target: ShareTarget): void => {
            GridItem() {
              this.targetCell(target)
            }
          }, (target: ShareTarget): string => `${target.chatId}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(14)
        .columnsGap(8)
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        // 载荷还没解析完（文件还在复制）时不给点：点了也没东西可交接。
        .enabled(this.usable())
        .opacity(this.usable() ? 1 : 0.4)
      }

      // 点头像之后的两档。放在按钮上方：用户先决定"怎么发"，再决定"发给谁"。
      Row({ space: 8 }) {
        this.modeChip($r('app.string.share_mode_send'), 'send');
        this.modeChip($r('app.string.share_mode_edit'), 'edit');
      }
      .width('100%')

      Button($r('app.string.share_open_app'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .width('100%')
        .enabled(this.usable() && !this.sending)
        .onClick((): void => this.handOff(0))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.page_bg'))
  }
}

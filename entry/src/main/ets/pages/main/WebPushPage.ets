import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getTdClient } from '../../tdkit/Globals';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_MEOW_NICKNAME, KEY_MEOW_SECRET, KEY_WEBPUSH_ACCEPTED, KEY_WEBPUSH_AUTH, KEY_WEBPUSH_ENABLED,
  KEY_WEBPUSH_ENDPOINT, KEY_WEBPUSH_MODE, KEY_WEBPUSH_P256DH, WEBPUSH_MODE_CUSTOM, WEBPUSH_MODE_MEOW,
  setBoolean, setString
} from '../../store/AppSettings';
import {
  ParsedSubscription, SUBSCRIPTION_JSON_HINT, WebPushConfig, WebPushValidation,
  deregisterWebPush, parseSubscriptionJson, registerWebPush, validateWebPushConfig
} from '../../services/WebPushRegistration';
import {
  MeowDeregisterOutcome, MeowRegisterOutcome, confirmMeowRegistration, deregisterMeowPush,
  getMeowSubKey, meowRelayEnabled, resolveWebPushMode, startMeowRegistration
} from '../../services/MeowPushRegistration';
import { HuaweiPushResult, registerHuaweiPush } from '../../services/HuaweiPushRegistration';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { contentSideGutter } from '../../util/contentWidth';

const CARD_RADIUS: number = 14;

// 华为 Push Kit 探针的可见性开关。结论已定：真机验证 pushService.getToken()
// 能拿到 token，但 TDLib registerDevice(deviceTokenHuaweiPush) 被 Telegram 服务器
// 拒绝（400 APP_PUSH_APIKEY_MISSING，见 DeviceTokenManager.cpp:447），这条通道走不通。
// 代码保留作参考实现，改为 true 即可恢复调试 UI。
const SHOW_HUAWEI_PROBE: boolean = false;

// 自定义 Web Push 中转通道的配置页。
//
// 这个功能默认关闭，且必须先读完风险说明才能启用 —— 它会把消息预览的明文交给
// 用户自建的服务器，属于「知情后自愿」的取舍，不能默默生效。
@Entry
@Component
struct WebPushPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp(KEY_WEBPUSH_ENABLED) pushEnabled: boolean = false;
  @StorageProp(KEY_WEBPUSH_ACCEPTED) accepted: boolean = false;
  @StorageProp(KEY_WEBPUSH_ENDPOINT) storedEndpoint: string = '';
  @StorageProp(KEY_WEBPUSH_P256DH) storedP256dh: string = '';
  @StorageProp(KEY_WEBPUSH_AUTH) storedAuth: string = '';
  @StorageProp(KEY_WEBPUSH_MODE) storedMode: string = '';
  @StorageProp(KEY_MEOW_NICKNAME) storedMeowNickname: string = '';
  @StorageProp(KEY_MEOW_SECRET) storedMeowSecret: string = '';
  // 草稿态：编辑中的值不立刻落盘，点「保存并注册」才写入并生效。
  @State endpoint: string = '';
  @State p256dh: string = '';
  @State auth: string = '';
  @State busy: boolean = false;
  @State statusText: string = '';
  @State statusOk: boolean = false;
  @State consentShown: boolean = false;
  @State jsonInput: string = '';
  @State jsonExpanded: boolean = false;
  // 顶部二选一：'custom'（手工三字段）或 'meow'（只填用户名，由中转服务器代填）。
  // MeoW 入口本身只在这台构建配置了中转地址（meowRelayEnabled()）时才显示，
  // clone 仓库拿到空地址的人只会看到手工模式，界面上不出现任何相关文案。
  @State mode: string = WEBPUSH_MODE_CUSTOM;
  @State meowNickname: string = '';
  // 两步注册：先拿 pendingId（验证码已发出），再用用户填回来的验证码确认。
  // pendingId 非空即代表"验证码已发出，等待用户填码"这一步骤状态，5 分钟
  // 过期不做本地倒计时 —— 过期由 confirm 请求的 400/403 直接反馈。
  @State meowPendingId: string = '';
  @State meowCode: string = '';
  @State meowBusy: boolean = false;
  @State meowStatusText: string = '';
  @State meowStatusOk: boolean = false;
  // 华为 Push Kit 探针：验证 Telegram 服务器能否直接投递到 Push Kit 通道
  // （而不经过自建 Web Push 中转）。三行分别对应 token / registerDevice 结果 /
  // 失败时的错误码与文案，见 HuaweiPushRegistration.ets 顶部注释。
  @State hwBusy: boolean = false;
  @State hwTokenLine: string = '';
  @State hwResultLine: string = '';
  @State hwErrorLine: string = '';

  aboutToAppear(): void {
    this.endpoint = this.storedEndpoint;
    this.p256dh = this.storedP256dh;
    this.auth = this.storedAuth;
    if (this.pushEnabled && this.storedEndpoint !== '') {
      this.statusOk = true;
      this.statusText = str('wp_enabled');
    }
    // 停留在用户上次用的模式；从没选过时默认落到 MeoW，但 MeoW 未配置中转
    // 地址时永远回落到手工模式（见 resolveWebPushMode 注释）。
    this.mode = resolveWebPushMode(meowRelayEnabled(), this.storedMode);
    this.meowNickname = this.storedMeowNickname;
    if (this.pushEnabled && this.mode === WEBPUSH_MODE_MEOW && this.storedMeowNickname !== '') {
      this.meowStatusOk = true;
      this.meowStatusText = str('wp_enabled');
    }
  }

  private setMode(next: string): void {
    if (this.mode === next) {
      return;
    }
    this.mode = next;
    setString(KEY_WEBPUSH_MODE, next);
  }

  private currentConfig(): WebPushConfig {
    return { endpoint: this.endpoint, p256dh: this.p256dh, auth: this.auth };
  }

  private onToggle(next: boolean): void {
    if (!next) {
      this.disable();
      return;
    }
    if (!this.accepted) {
      // 未读过说明：先弹说明，开关保持关闭，接受后由 acceptConsent 打开。
      this.consentShown = true;
      return;
    }
    this.saveAndRegister();
  }

  private acceptConsent(): void {
    this.consentShown = false;
    setBoolean(KEY_WEBPUSH_ACCEPTED, true);
    this.saveAndRegister();
  }

  private disable(): void {
    setBoolean(KEY_WEBPUSH_ENABLED, false);
    this.statusOk = false;
    this.statusText = str('wp_disabled');
    deregisterWebPush(getTdClient());
  }

  private saveAndRegister(): void {
    if (this.busy) {
      return;
    }
    const config: WebPushConfig = this.currentConfig();
    const check: WebPushValidation = validateWebPushConfig(config);
    if (!check.valid) {
      this.statusOk = false;
      this.statusText = check.error;
      promptAction.showToast({ message: check.error, duration: 2000 });
      return;
    }
    this.busy = true;
    this.statusText = str('wp_registering');
    registerWebPush(getTdClient(), config).then((receiverId: string): void => {
      setString(KEY_WEBPUSH_ENDPOINT, config.endpoint.trim());
      setString(KEY_WEBPUSH_P256DH, config.p256dh.trim());
      setString(KEY_WEBPUSH_AUTH, config.auth.trim());
      setBoolean(KEY_WEBPUSH_ENABLED, true);
      this.statusOk = true;
      this.statusText = receiverId !== ''
        ? str('wp_registered_with_id', receiverId)
        : str('wp_registered_no_id');
      this.busy = false;
    }).catch((e: TdError): void => {
      // 注册失败不打开开关 —— 否则用户会以为通知已经生效。
      setBoolean(KEY_WEBPUSH_ENABLED, false);
      this.statusOk = false;
      this.statusText = str('wp_register_failed', e.message);
      this.busy = false;
    });
  }

  // 多行输入：endpoint 和两个 base64url 密钥都很长，单行框只能看到开头一小截，
  // 核对和排错都很难受。
  //
  // 三个字段各写一个无参 @Builder，且用 $$ 双向绑定。不能把值当参数传进
  // @Builder —— 值参数只在首次渲染时求值，之后任何一次重渲染（比如点「保存」
  // 时 busy 变化）都会把 TextArea 的 text 重置回捕获时的旧值，表现就是
  // "输入完保存后地址弹回上一个"。
  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 5 });
  }

  @Builder
  endpointField() {
    this.fieldLabel($r('app.string.wp_endpoint_label'));
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.endpoint, placeholder: $r('app.string.wp_endpoint_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  @Builder
  p256dhField() {
    this.fieldLabel($r('app.string.wp_p256dh_label'));
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.p256dh, placeholder: $r('app.string.wp_p256dh_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  @Builder
  authField() {
    this.fieldLabel('auth（base64url）');
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.auth, placeholder: $r('app.string.wp_auth_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  private fillFromJson(): void {
    const parsed: ParsedSubscription = parseSubscriptionJson(this.jsonInput);
    // 即使有缺字段也把已解析出来的回填，用户只需补齐缺的那项。
    if (parsed.config.endpoint !== '') { this.endpoint = parsed.config.endpoint; }
    if (parsed.config.p256dh !== '') { this.p256dh = parsed.config.p256dh; }
    if (parsed.config.auth !== '') { this.auth = parsed.config.auth; }
    if (parsed.error !== '') {
      this.statusOk = false;
      this.statusText = parsed.error;
      promptAction.showToast({ message: parsed.error, duration: 2000 });
      return;
    }
    this.jsonExpanded = false;
    this.statusOk = true;
    this.statusText = str('wp_filled');
  }

  private truncateToken(token: string): string {
    const EDGE_LEN: number = 12;
    if (token.length <= EDGE_LEN * 2) {
      return token;
    }
    return `${token.substring(0, EDGE_LEN)}...${token.substring(token.length - EDGE_LEN)}`;
  }

  private runHuaweiPushProbe(): void {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    this.hwTokenLine = str('wp_registering');
    this.hwResultLine = '';
    this.hwErrorLine = '';
    registerHuaweiPush(getTdClient()).then((result: HuaweiPushResult): void => {
      this.hwTokenLine = result.token !== ''
        ? this.truncateToken(result.token)
        : str('wp_register_failed', `${result.errorCode}`);
      this.hwResultLine = result.success
        ? (result.pushReceiverId !== '' ? str('wp_registered_with_id', result.pushReceiverId) : str('wp_registered_no_id'))
        : (result.token !== '' ? str('wp_register_failed', `${result.errorCode}`) : '');
      this.hwErrorLine = result.success ? '' : result.errorMessage;
      this.hwBusy = false;
    });
  }

  private deregister(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    setBoolean(KEY_WEBPUSH_ENABLED, false);
    deregisterWebPush(getTdClient()).then((): void => {
      this.statusOk = false;
      // 只注销订阅，保留已填的三项 —— 用户多半是想换个地址再注册，
      // 清空会逼他重新粘一遍。
      this.statusText = str('wp_deregistered');
      this.busy = false;
    });
  }

  // MeoW 模式：两步注册，带验证码。MeoW 是纯昵称寻址、无鉴权的，不验证的话
  // 谁都能拿别人的昵称注册、把自己的消息转推过去；验证码证明用户确实拥有
  // 这个昵称。第一步只拿 pendingId，第二步验证码确认后才拿到三个 Web Push
  // 字段，复用 registerWebPush 那条已验证过的路径。
  //
  // 错误按来源（网络 / HTTP 状态 / 响应缺字段 / 验证码错误或过期）分别落到
  // 不同的文案上，不做笼统的"失败"提示。
  private meowRequestCode(): void {
    if (this.meowBusy) {
      return;
    }
    this.meowBusy = true;
    this.meowStatusText = str('wp_registering');
    startMeowRegistration(this.meowNickname).then((pendingId: string): void => {
      this.meowPendingId = pendingId;
      this.meowCode = '';
      this.meowStatusOk = true;
      this.meowStatusText = str('meow_code_sent');
      this.meowBusy = false;
    }).catch((e: Error): void => {
      this.meowStatusOk = false;
      this.meowStatusText = str('wp_register_failed', e.message);
      this.meowBusy = false;
    });
  }

  private meowConfirmCode(): void {
    if (this.meowBusy) {
      return;
    }
    this.meowBusy = true;
    this.meowStatusText = str('wp_registering');
    confirmMeowRegistration(getTdClient(), this.meowPendingId, this.meowCode, this.meowNickname,
      this.storedMeowSecret)
      .then((outcome: MeowRegisterOutcome): void => {
        setBoolean(KEY_WEBPUSH_ENABLED, true);
        this.meowPendingId = '';
        this.meowCode = '';
        this.meowStatusOk = true;
        this.meowStatusText = outcome.receiverId !== ''
          ? str('wp_registered_with_id', outcome.receiverId)
          : str('wp_registered_no_id');
        this.meowBusy = false;
      }).catch((e: Error): void => {
        // 确认失败不打开开关，避免用户误以为通知已生效。验证码错误/过期时
        // pendingId 保留，用户可以直接重填验证码重试而不用回退到第一步。
        this.meowStatusOk = false;
        this.meowStatusText = str('wp_register_failed', e.message);
        this.meowBusy = false;
      });
  }

  private meowCancelCode(): void {
    this.meowPendingId = '';
    this.meowCode = '';
    this.meowStatusText = '';
  }

  private meowDeregister(): void {
    if (this.meowBusy) {
      return;
    }
    this.meowBusy = true;
    const subKey = getMeowSubKey();
    const secret = this.storedMeowSecret;
    setBoolean(KEY_WEBPUSH_ENABLED, false);
    deregisterMeowPush(getTdClient(), subKey, secret).then((outcome: MeowDeregisterOutcome): void => {
      // 中转端取消订阅失败不影响本地已经停止投递这一事实，但要让用户知道
      // 服务端那份订阅记录可能还留着。
      this.meowPendingId = '';
      this.meowCode = '';
      this.meowStatusOk = outcome.relayWarning === '';
      this.meowStatusText = outcome.relayWarning !== '' ? outcome.relayWarning : str('wp_deregistered');
      this.meowBusy = false;
    }).catch((e: Error): void => {
      this.meowStatusOk = false;
      this.meowStatusText = str('wp_register_failed', e.message);
      this.meowBusy = false;
    });
  }

  @Builder
  modeTab(target: string, label: ResourceStr) {
    Text(label).fontSize(14)
      .fontWeight(this.mode === target ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.mode === target ? Color.White : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.mode === target ? COLOR_PRIMARY : Color.Transparent)
      .layoutWeight(1).height(36).textAlign(TextAlign.Center).borderRadius(9)
      .onClick((): void => this.setMode(target));
  }

  @Builder
  modeSwitcher() {
    Row({ space: 4 }) {
      this.modeTab(WEBPUSH_MODE_MEOW, $r('app.string.meow_mode_meow'));
      this.modeTab(WEBPUSH_MODE_CUSTOM, $r('app.string.meow_mode_custom'));
    }
    .width('100%').padding(4)
    .backgroundColor(COLOR_PAGE_BG).borderRadius(12);
  }

  @Builder
  consentSheet() {
    Column({ space: 12 }) {
      Text($r('app.string.wp_before_you_enable'))
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.wp_intro'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19);
      Text($r('app.string.wp_warn_1'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_2'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_3'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_4'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_5'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Row({ space: 10 }) {
        Button($r('app.string.cancel')).fontSize(15).layoutWeight(1)
          .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_TEXT_PRIMARY)
          .onClick((): void => { this.consentShown = false; });
        Button($r('app.string.wp_accept')).fontSize(15).layoutWeight(1)
          .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
          .onClick((): void => this.acceptConsent());
      }.width('100%').margin({ top: 4 });
    }
    .width('100%').padding(20).alignItems(HorizontalAlign.Start);
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY])
          .onClick((): void => { router.back(); });
        Text($r('app.string.ns_custom_push')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').height(52).padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center);

      Scroll() {
        Column({ space: 12 }) {
          // MeoW 入口只在这台构建配置了中转地址时出现；未配置的构建（比如 clone
          // 仓库、用模板生成 ApiCredentials.ets 的人）永远只看到手工模式，
          // 不出现任何切换控件。
          if (meowRelayEnabled()) {
            this.modeSwitcher();
          }

          if (this.mode === WEBPUSH_MODE_MEOW) {
            Column({ space: 10 }) {
              Text($r('app.string.meow_nickname_label')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 16, right: 16, top: 14 });
              Row() {
                TextInput({ text: $$this.meowNickname, placeholder: $r('app.string.meow_nickname_hint') })
                  .fontSize(15).layoutWeight(1).enabled(!this.meowBusy && this.meowPendingId === '')
                  .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
              }.width('100%').padding({ left: 16, right: 16 });
              Text($r('app.string.meow_privacy_note'))
                .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
                .width('100%').padding({ left: 16, right: 16, top: 4 });

              // 第二步：拿到 pendingId 后才出现验证码输入框，填完点「完成注册」。
              if (this.meowPendingId !== '') {
                Text($r('app.string.meow_code_label')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                  .width('100%').padding({ left: 16, right: 16, top: 4 });
                Row() {
                  TextInput({ text: $$this.meowCode, placeholder: $r('app.string.meow_code_hint') })
                    .fontSize(15).layoutWeight(1).enabled(!this.meowBusy).type(InputType.Number)
                    .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
                }.width('100%').padding({ left: 16, right: 16 });
              }

              Column({ space: 8 }) {
                if (this.meowPendingId === '') {
                  Button(this.meowBusy ? $r('app.string.processing') : $r('app.string.meow_request_code'))
                    .fontSize(15).width('100%').height(44)
                    .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
                    .enabled(!this.meowBusy)
                    .onClick((): void => this.meowRequestCode());
                } else {
                  Button(this.meowBusy ? $r('app.string.processing') : $r('app.string.meow_confirm'))
                    .fontSize(15).width('100%').height(44)
                    .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
                    .enabled(!this.meowBusy)
                    .onClick((): void => this.meowConfirmCode());
                  Button($r('app.string.cancel'))
                    .fontSize(15).width('100%').height(44)
                    .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_TEXT_PRIMARY)
                    .enabled(!this.meowBusy)
                    .onClick((): void => this.meowCancelCode());
                }
                Button($r('app.string.wp_deregister'))
                  .fontSize(15).width('100%').height(44)
                  .backgroundColor(COLOR_PAGE_BG).fontColor('#FF3B30')
                  .enabled(!this.meowBusy)
                  .onClick((): void => this.meowDeregister());
                if (this.meowStatusText !== '') {
                  Text(this.meowStatusText)
                    .fontSize(12).lineHeight(17)
                    .fontColor(this.meowStatusOk ? COLOR_PRIMARY : '#FF3B30')
                    .width('100%');
                }
              }
              .width('100%').padding({ left: 16, right: 16, top: 4 });
            }
            .width('100%').padding({ bottom: 16 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          }

          if (this.mode === WEBPUSH_MODE_CUSTOM) {
          Column() {
            Row() {
              Text($r('app.string.wp_enable')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
                .selectedColor(COLOR_PRIMARY)
                .enabled(!this.busy)
                .onChange((next: boolean): void => this.onToggle(next));
            }.width('100%').height(48).padding({ left: 14, right: 12 });
            Text($r('app.string.wp_enable_sub'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
              .width('100%').padding({ left: 14, right: 14, bottom: 10 });
          }
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          Column() {
            Row() {
              Text($r('app.string.wp_subscription')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text(this.jsonExpanded ? $r('app.string.collapse') : $r('app.string.wp_paste_json'))
                .fontSize(13).fontColor(COLOR_PRIMARY)
                .onClick((): void => { this.jsonExpanded = !this.jsonExpanded; });
            }.width('100%').padding({ left: 16, right: 16, top: 14 });
            Text($r('app.string.wp_keygen_note'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
              .width('100%').padding({ left: 16, right: 16, top: 6 });

            // 一键填充：多数服务端库直接输出这个结构，逐项复制既慢又容易串行。
            if (this.jsonExpanded) {
              Column({ space: 8 }) {
                Row() {
                  TextArea({ text: $$this.jsonInput, placeholder: SUBSCRIPTION_JSON_HINT })
                    .fontSize(12).layoutWeight(1).maxLines(8)
                    .enabled(!this.busy)
                    .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
                }.width('100%');
                Button($r('app.string.wp_fill_three'))
                  .fontSize(14).width('100%').height(40)
                  .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_PRIMARY)
                  .enabled(!this.busy)
                  .onClick((): void => this.fillFromJson());
              }
              .width('100%').padding({ left: 16, right: 16, top: 10 });
            }

            this.endpointField();
            this.p256dhField();
            this.authField();

            Column({ space: 8 }) {
              Button(this.busy ? $r('app.string.processing') : $r('app.string.wp_save_register'))
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
                .enabled(!this.busy)
                .onClick((): void => this.saveAndRegister());
              // 注销入口独立出来：关开关也会注销，但换地址时用户想的是
              // "先退掉旧的"，没有这个按钮就只能去拨开关，很不直观。
              Button($r('app.string.wp_deregister'))
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PAGE_BG).fontColor('#FF3B30')
                .enabled(!this.busy)
                .onClick((): void => this.deregister());
              if (this.statusText !== '') {
                Text(this.statusText)
                  .fontSize(12).lineHeight(17)
                  .fontColor(this.statusOk ? COLOR_PRIMARY : '#FF3B30')
                  .width('100%');
              }
            }
            .width('100%').padding({ left: 16, right: 16, top: 12 });
          }
          .width('100%').padding({ bottom: 16 })
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          Column({ space: 6 }) {
            Text($r('app.string.wp_server_todo')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
            // One key for the whole list rather than five joined fragments: the
            // numbering and line breaks belong to the copy, and a translator
            // needs to see the sentences whole.
            Text($r('app.string.wp_server_steps'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17).width('100%');
          }
          .width('100%').padding(14)
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          }

          // 探针区块：与上面的自建 Web Push 并存，验证华为 Push Kit 通道是否
          // 可被 Telegram 服务器直接使用。验证通过前不接入 PushExtensionAbility。
          // 结论已定（见 SHOW_HUAWEI_PROBE 注释），默认不渲染。
          if (SHOW_HUAWEI_PROBE) {
            Column({ space: 8 }) {
              Button(this.hwBusy ? $r('app.string.processing') : $r('app.string.px_test'))
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_PRIMARY)
                .enabled(!this.hwBusy)
                .onClick((): void => this.runHuaweiPushProbe());
              if (this.hwTokenLine !== '') {
                Text(this.hwTokenLine).fontSize(12).lineHeight(17).fontColor(COLOR_TEXT_PRIMARY).width('100%');
              }
              if (this.hwResultLine !== '') {
                Text(this.hwResultLine).fontSize(12).lineHeight(17).fontColor(COLOR_TEXT_SECONDARY).width('100%');
              }
              if (this.hwErrorLine !== '') {
                Text(this.hwErrorLine).fontSize(12).lineHeight(17).fontColor('#FF3B30').width('100%');
              }
            }
            .width('100%').padding(14)
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          }
        }
        .width('100%')
        // 限宽做在内容列的内边距上而不是 Scroll 的宽度上：Scroll 仍铺满窗口，
        // 两侧让出来的留白因此还在它的命中区里，手指按在留白上照样能滚页面。
        // 这一页的说明文字最长，收窄后一行才不用横扫整屏。
        // 手机上 contentSideGutter 恒为 0，两个值逐像素等于改动前的 12。
        .padding({
          left: 12 + contentSideGutter(this.screenW),
          right: 12 + contentSideGutter(this.screenW),
          bottom: this.bottomSafe + 16
        });
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top);
    }
    .width('100%').height('100%')
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .backgroundColor(COLOR_PAGE_BG)
    .bindSheet($$this.consentShown, this.consentSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: COLOR_SURFACE,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}

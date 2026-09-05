// 麦克风录音状态机：start/stopTimer/finish/cancel/secondsLabel 五个方法 +
// isRecording/recordingStarting/recordSeconds 三个显示态。从 ChatPage 整体
// 搬出（B15 批）。原方法名 startRecording/stopRecordTimer/finishRecording/
// cancelRecording/formatRecSeconds 按方案改名为 start/stopTimer/finish/
// cancel/secondsLabel，方法体逐字保留。
//
// 【为什么只有三个 @Trace】
// isRecording/recordingStarting/recordSeconds 是 ChatComposerInput.build()
// 的三处直读点（原来是三个标量 @Param，逐个转手，页面因此订阅了这三个
// @Trace——与 composer/commandSuggestion 同一形状的第三次重复，见侦察报告
// 3）。recordTimer/voiceRec/recordingSeq 三个是纯内部机件，从不被任何
// build() 读取，不加 @Trace。
//
// 【composerController 是 TextAreaController，不是 ComposerSession——与
// AttachActions 文件头同一份说明】
// start() 里的 `composerController.stopEditing()` 操作的是 ArkUI 内建
// TextAreaController（页面另有同名相近字段 `this.composer: ComposerSession`，
// 两者是完全不同的两个对象）。这一步与 beforeStart 打包的另外四步一起经
// `host.beforeStart()` 转发，不接到 ComposerSession 上。
//
// 【start() 开头六件事：五件真连续，composerFocused 那一件不进 beforeStart】
// 侦察报告 (B) 逐行核对过原 HEAD：
//   setEmojiPanel(false) → applyBottomSlot(closeSlot(bottomSlot,
//   SLOT_REPLY_KB)) → mention.clear() → command.closePanel() →
//   composerController.stopEditing()
// 这五行（原 6218-6222）彼此紧邻、确实连续，打包成宿主的一个 `beforeStart`
// 回调；`command.closePanel()`（B14 产物）方案原文成文时还没点名，但既然夹在
// 中间就必须一并纳入，否则开始录音时命令菜单不再被关闭，是行为变更。
// 紧接着的 `this.composerFocused = false;`（原 6223）是页面自留字段（方案
// 6.9 节裁决，不进任何控制器），单独经 `host.setComposerFocused(false)`
// 转发，不并进 beforeStart——与 AttachActions.openVideoNoteRecorder 对
// stopEditing()/setComposerFocused(false) 的处理是同一个理由：页面另外几处
// `composerController.stopEditing()` + `composerFocused=false` 组合彼此独立，
// 合并成一个回调会让它们意外被牵连。两次宿主调用逐字保持原来的先后顺序
// （beforeStart 在前，setComposerFocused(false) 在后，再是本簇自己的
// recordingStarting=true）。
//
// 【recordingSeq："比较后不执行"的令牌，不是 clearTimeout】
// start() 领一枚新令牌 `seq = ++this.recordingSeq`，闭包捕获它与这一次的
// VoiceRecorder 实例 `rec`（**局部变量**，不是重新读 `this.voiceRec`）。
// cancel() 只做 `this.recordingSeq++`（连同 finish() 也是），不做
// clearTimeout——原代码里这一簇本来就没有用 setTimeout 做取消，`recordTimer`
// 是 setInterval 句柄，由 stopTimer() 用 clearInterval 收，与令牌比较是两套
// 独立机制。
// 竞态例子（快速"开始-取消-开始"）：第一次 start() 捕获 seq=N；在其
// `rec.start(...)` 落地前调用 cancel()，recordingSeq 变为 N+1（或以上，
// 经 resetComposerSession 间接调用时还会先在那边 ++ 一次）；第二次 start()
// 通过 recordingStarting/isRecording 已被 cancel() 复位为 false 的守卫，
// 再次 ++recordingSeq 捕获新的 seq'>N。第一段迟到的 `.then`/`.catch` 比较
// `seq !== this.recordingSeq` 恒真，直接 `rec.cancel()`/`return`，从不写
// `isRecording=true`、不写 `recordSeconds`/`recordTimer`，也不会误伤第二段
// 已经写入 `this.voiceRec` 的新实例（`rec` 是各自调用的局部闭包变量）。
// **因此 cancel() 必须 `++recordingSeq`**——去掉这一步，第一段迟到的
// Promise 会被当作有效录音接受。
//
// 【dispose() = cancel()】
// 侦察报告 (C) 核实过：全仓对本簇字段唯一一处页面销毁时的清理是
// `aboutToDisappear` → `disposeTimersAndSeqGuards`（原 3664 行）里裸调的
// `this.cancelRecording();`，不做任何额外动作。dispose() 如实等价为
// `this.cancel()`，不新增、不少做。
//
// 【context() 一次性求值——与 AttachActions 同一个例外】
// `rec.start(...)` 原来传 `getContext(this) as common.UIAbilityContext`。
// `UIAbilityContext` 在同一个 Ability 生命周期内是稳定值，页面在
// `aboutToAppear` 调 `bind()` 时把它求值一次、闭包成 `context: () => ctx`
// 传进来，不是像其余取值器那样每次现读一个活字段——与 AttachActions.ets
// 文件头「getContext(this) 一共 6 处」那段是同一份道理。
//
// 【与其余控制器同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数
// 取值器/动作回调，现取不缓存（`context` 见上方说明）；类中不声明
// @Monitor；未 bind 时的空宿主字段类型非空，占位值在页面 bind() 完成前不会
// 被真正用到。

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { MessageStore } from '../../store/MessageStore';
import { logE } from '../../util/log';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把跨簇副作用交回页面执行。仿 AttachActions 的
// AttachActionsHost / JumpFlashState 的 JumpFlashStateHost。
export interface VoiceRecordingStateHost {
  // 当前 MessageStore；路由切换途中可能为 null。start() 的入口守卫、
  // finish() 发送语音都要用。
  store: () => MessageStore | null;
  // UIAbilityContext。**唯一例外**：页面在 `aboutToAppear` 调 `bind()` 时把
  // `getContext(this) as common.UIAbilityContext` 求值一次、闭包成常量传进
  // 来，不是像其余取值器那样每次现读一个活字段——理由见文件头「context()
  // 一次性求值」一节。
  context: () => common.UIAbilityContext;
  // start() 开头五件真连续的跨簇动作（setEmojiPanel(false)/
  // applyBottomSlot(closeSlot(...))/mention.clear()/command.closePanel()/
  // composerController.stopEditing()），原样打包，page 侧实现成这五行按原
  // 顺序各调各的。
  beforeStart: () => void;
  // 写页面 `@Local composerFocused`（原 `this.composerFocused = false;`，
  // 页面自留字段）。**不要**并进 `beforeStart()`——理由见文件头专项说明。
  setComposerFocused: (value: boolean) => void;
  // finish() 发送成功后的 `this.atBottom = true;`（页面自留字段，跨簇写）。
  afterSent: () => void;
  // 造一个录音器。搬之前 start() 里写的是 `new VoiceRecorder()` 硬编码。
  //
  // 【为什么给它开缝】本批方案点名要钉的那枚钉子是「start→cancel→start，
  // 第一段迟到的 Promise 不改状态」——也就是 cancel() 必须 ++recordingSeq、
  // 且两处 `seq !== this.recordingSeq` 比较都在。这条语义全部活在
  // rec.start(...) 的 .then()/.catch() 里；录音器是 new 出来的，测试没有
  // 任何手段让那个 Promise 按自己的节奏兑现，钉子就钉不住。
  //
  // 本类其余每一处跨簇依赖（store/context/beforeStart/setComposerFocused/
  // afterSent）都走了宿主，唯独这里没走——不是有意的设计，是漏了。方案 §3
  // 末行本来就写着「异步用注入的 fake」。B14 也是靠同一条缝（client 取值器）
  // 才把那批的钉子钉住的。
  //
  // 页面侧实现恒为 `() => new VoiceRecorder()`，与搬之前逐字等价。
  newRecorder: () => VoiceRecorder;
}

@ObservedV2
export class VoiceRecordingState {
  // ——— 显示态：ChatComposerInput 直接读这三个 @Trace ———
  // 对应原 ChatPage.@Local isRecording/recordingStarting/recordSeconds
  // （原 1848-1850 行）。下面这一行是原注释，原样照抄，未改一字。
  //
  // Voice recording state.
  @Trace isRecording: boolean = false;
  @Trace recordingStarting: boolean = false;
  @Trace recordSeconds: number = 0;

  // ——— 内部机件：一律**不加 @Trace** ———
  private recordTimer: number = -1;
  private voiceRec: VoiceRecorder | null = null;
  private recordingSeq: number = 0;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的
  // 值；`context` 用一个空对象强转占位——真实调用发生在用户点开麦克风之后，
  // 严格晚于页面 bind() 完成，这个占位值永远不会被真正用到。
  private host: VoiceRecordingStateHost = {
    store: (): MessageStore | null => null,
    context: (): common.UIAbilityContext => ({} as common.UIAbilityContext),
    beforeStart: (): void => {},
    setComposerFocused: (_value: boolean): void => {},
    afterSent: (): void => {},
    newRecorder: (): VoiceRecorder => new VoiceRecorder()
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: VoiceRecordingStateHost): void {
    this.host = host;
  }

  // --- voice recording (mic button) ---
  start(): void {
    if (this.recordingStarting || this.isRecording || this.host.store() === null) {
      return;
    }
    this.host.beforeStart();
    this.host.setComposerFocused(false);
    this.recordingStarting = true;
    const seq: number = ++this.recordingSeq;
    const rec = this.host.newRecorder();
    this.voiceRec = rec;
    rec.start(this.host.context()).then((ok: boolean) => {
      if (seq !== this.recordingSeq) {
        rec.cancel();
        return;
      }
      this.recordingStarting = false;
      if (!ok) {
        this.voiceRec = null;
        promptAction.showToast({ message: $r('app.string.cp_record_failed_permission'), duration: 2500 });
        return;
      }
      this.isRecording = true;
      this.recordSeconds = 0;
      this.recordTimer = setInterval(() => { this.recordSeconds += 1; }, 1000);
    }).catch((e: Object): void => {
      if (seq !== this.recordingSeq) {
        return;
      }
      this.recordingStarting = false;
      this.voiceRec = null;
      logE(`VoiceRecordingState.start failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.cp_record_failed'), duration: 1800 });
    });
  }

  private stopTimer(): void {
    if (this.recordTimer !== -1) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  finish(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopTimer();
    this.isRecording = false;
    if (rec === null) {
      return;
    }
    rec.stop().then((duration: number) => {
      const store = this.host.store();
      if (rec.path !== '' && store !== null) {
        this.host.afterSent();
        store.sendVoiceNote(rec.path, duration);
      }
    });
  }

  cancel(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopTimer();
    this.isRecording = false;
    if (rec !== null) {
      rec.cancel();
    }
  }

  secondsLabel(): string {
    const m = Math.floor(this.recordSeconds / 60);
    const s = this.recordSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  // ChatPage.aboutToDisappear 全链路对本簇唯一的清理就是裸调
  // `this.cancelRecording()`（原 disposeTimersAndSeqGuards@3664）——见文件头
  // 「dispose() = cancel()」一节，逐字等价，不新增、不少做。
  dispose(): void {
    this.cancel();
  }
}

// 会话翻译（总开关/排除名单/加入名单三态判定 + 可见范围批量翻译 + 单条重译/
// 隐藏 + 会话级开关切换）的状态机。从 ChatPage 整体搬出（B10 批）。
//
// 【为什么要搬】
// 这一簇原本只有两个真正驱动 UI 的字段（translateChatOptOut/
// translateChatOptIn），字段数不大，搬迁收益主要不是"收窄重渲染"（不像
// B5/B6/B8 那样有一整条订阅链每隔几百毫秒翻转），而是把散在 ChatPage 里的
// 三态判定、批量翻译请求节流、会话级开关切换这几件强内聚但与消息行渲染、
// 头部身份、搜索、选择等其它簇都无关的逻辑收进一个独立文件，跟 B9
// ComposerSession/B10 TypingIndicatorState 一起，把 ChatPage 降到"控制器持有者
// + 各控制器之间的协调器"这一层。
//
// 【为什么 isTranslatable 不进本类】
// B8 已经把 isGroup/isChannel/isBotChat/isTranslatable/membershipState/
// unreadBadge 六个字段的所有权裁决钉在页面：它们被 cacheKey、成员资格状态机、
// 翻译总开关、ScrollFab 未读徽标等多个与身份簇无关的域共同读写。isTranslatable
// 除了本类的三态判定，还被 HeaderIdentitySession（B8）经 host.isTranslatable()
// 读取、经 host.onChatKindResolved 回传新值，以及页面自己的
// updateChatIsTranslatable TDLib 订阅直接写入——三条独立的读写通道，任何一条
// 搬进本类都会变成"两个控制器互相持有对方"，违反"控制器只对宿主说话，不直接
// 认识兄弟控制器"这条通用约定。本类经 host.isTranslatable() 现取、经
// host.setIsTranslatable() 写回，**不存一份影子拷贝**——这正是 B8 在
// HeaderIdentitySession 里对同一个字段采用的处理方式。
//
// 【翻译三态语义耦合，不可拆】
// 总开关（页面的 @Param translateChatsEnabled）、会话级排除名单
// （translateChatOptOut）、会话级加入名单（translateChatOptIn）三者不是三个
// 独立布尔量：
//   总开关开着 —— 默认所有会话都翻，会话级那一项是"排除名单"（关掉这个会话）；
//   总开关关着 —— 默认都不翻，会话级那一项是"加入名单"（只翻这个会话，落地为
//                 服务端 is_translatable，跟官方客户端同一个字段，多端同步）。
// util/translationMode.ets 的 translationActive()/toggleTranslation() 把这套
// 判定收成了两个纯函数（两处都在文件头注释里强调"两份名单的极性是反的，最容易
// 写错的就是在总开关模式下忘了取反"）。本类的 active()/toggleTranslatable()
// 只是这两个纯函数的薄包装，不得在包装层再引入第二套独立判定——历史上这类
// "看起来等价"的重复判定正是这套机制反复出 bug 的根源。
//
// 【@Monitor('translateChatsEnabled') 留在页面】
// 官方规则：@ObservedV2 类里的 @Monitor 解注册依赖 GC，销毁时机不可靠
// （HeaderIdentitySession/SearchSession/SelectionSession/LiveTopCardController
// 四个先例都不在类里声明 @Monitor）。更关键的是，@Monitor 只能监听同一个
// @ComponentV2/@ObservedV2 实例上的 @Param/@Local/@Trace，而
// translateChatsEnabled 是页面的 @Param，本来就不可能被本类监听到。装饰器连同
// 它的空壳方法体一并留在 ChatPage，方法体只转发一行到 onSettingChanged(...)，
// 显式带上 this.translateChatsEnabled 当参数——本类永远不缓存这个 @Param，每次
// 由调用方现取现传。
//
// 【active() 在消息行渲染热路径上，零分配、无日志】
// prepareMessageBubble 的 cacheKey 每次都读 this.translation.active(...)，装进
// 每一行的复用键里（不变量 1）。方法体因此只能是三个字段读取 + 一次纯函数调用，
// 不能有 new/日志/额外的函数调用层——与 util/translationMode.ets 里
// translationActive() 本身"抽出来是因为同一份判断在页面里出现过三次"的初衷
// 一致，本类只是把"页面里的那一份"搬了个位置，判定逻辑本身仍在纯函数里。
//
// 【driveVisibleWork 留在页面】
// driveVisibleWork() 是翻译/媒体窗口/播放位三件事的汇合点：它在同一次调用里
// 分别驱动 drive()（本类）、syncMediaWindow()（媒体窗口簇）、
// armPlaySlotSettle()（播放位簇）。这三件事分属互不相干的域，合并进本类会让
// 控制器反过来持有媒体窗口和播放位的知识。driveVisibleWork() 本身继续留在
// 页面当协调器，只把翻译那一路的方法体（原 driveTranslations）搬进本类的
// drive(enabled, startIdx, endIdx)；本类需要"翻译总开关切换后要不要把可见范围
// 补翻一遍"这个联动时，经 host.driveVisibleWork() 回调触发页面那份完整协调，
// 而不是自己只调半份。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，每个都有自己的会话级翻译开关。
// 做成单例会让一个会话切的开关冒到另一个会话里。页面用字段初始化器 new 一个：
// 首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【为什么 dispose() 里没有 seq/定时器】
// 本簇不像 LiveTopCardController/SearchSession/HeaderIdentitySession 那样有
// 会因换会话/页面销毁而需要作废的异步在途请求——批量翻译（drive）与单条重译
// （translateInline）各自的回调都用调用时刻捕获的 `this.store === store` 做
// 陈旧响应判定（响应回来时页面已经切换了 MessageStore 就直接丢弃，判据在
// 原 ChatPage 代码里就是这样，不是本次新增的收紧），toggleTranslatable 的
// TDLib 回滚也只在极短的请求窗口内生效、不依赖跨会话的序号守卫。原
// ChatPage.aboutToDisappear 里也确实没有任何 translate* 字段的清理语句。
// dispose() 仍然保留、仍然被 ChatPage.aboutToDisappear 调用——这是所有
// @ObservedV2 控制器统一的生命周期约定（bind/dispose 成对出现），不因为这一批
// 恰好没有要清的定时器就省掉这个方法。
//
// 【不在本类里声明 @Monitor】
// 同上：官方规则，类中 @Monitor 的解注册依赖 GC，本簇的联动全部用显式方法
// 调用表达。

import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdRequest } from '../../tdkit/TdTypes';
import { MessageStore } from '../../store/MessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import {
  setTranslateOptedIn, setTranslateOptedOut, translateOptedIn, translateOptedOut
} from '../../store/AppSettings';
import { AlbumGroup } from '../../util/collapseAlbums';
import {
  TranslateToggle,
  toggleTranslation, translationActive as isTranslationActive
} from '../../util/translationMode';
import {
  TranslationService, getTranslationService, looksLikeTargetLanguage, resolveTranslateTarget
} from '../../services/TranslationService';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读页面
// 当下的真值，动作回调把副作用交回页面执行。仿 HeaderIdentitySession 的
// HeaderIdentityHost / SearchSession 的 SearchSessionHost。
//
// 两条纪律：
// 1. 这里只放**取值器**，不放页面的 @Local/@Param 引用。控制器不缓存页面的
//    值，每次要用就现取——否则页面改了字段、控制器手里还是旧的；
//    translateChatsEnabled（页面的 @Param）因此不在这份接口里，改由每个需要
//    它的方法（active/drive/toggleTranslatable）显式接收调用方传入的参数。
// 2. isTranslatable 字段本身留在页面（所有权裁决见文件头），本类只经
//    isTranslatable() 现取、经 setIsTranslatable() 写回，不在本类里存一份
//    影子拷贝。
export interface TranslationDriverHost {
  // 当前会话 id。
  chatId: () => number;
  // 当前 MessageStore；路由切换途中可能为 null。
  store: () => MessageStore | null;
  // 当前折叠后的消息行分组——drive() 按可见区间索引它，取"当下这一份"而不是
  // 控制器自己持有一份引用（不变量 9：禁止把任何 @Local 按引用传给控制器）。
  groups: () => AlbumGroup[];
  // 服务端 is_translatable 位。字段本身留在页面（所有权裁决见文件头），本类
  // 只在三态判定和切换开关时现取。
  isTranslatable: () => boolean;
  // toggleTranslatable() 算出新的服务端位（以及请求失败时的回滚值）之后，把
  // 写入交回页面执行——isTranslatable 的唯一写入口仍是页面自己的字段。
  setIsTranslatable: (value: boolean) => void;
  // 总开关切换（onSettingChanged）或会话级开关切换（toggleTranslatable）之后，
  // 翻译从"关"变"开"要把当前可见范围补翻一遍——这同时也要连带刷新媒体窗口
  // 和播放位判定（driveVisibleWork 是三者的汇合点，留页面作协调器，见文件头
  // 说明），本类不越权只调用自己那一路。
  driveVisibleWork: () => void;
}

@ObservedV2
export class TranslationDriver {
  // ——— 显示态：目前没有直接被某个宿主组件 build() 读的 @Trace 消费者（本簇
  // 不像 B5/B6/B8 那样有专属的展示宿主组件），但两个字段仍然驱动
  // this.active()/toggleTranslatable() 的判定结果，而 active() 又被
  // prepareMessageBubble 的 cacheKey 读取，翻转必须能触发消息行重渲染——这正是
  // @Trace 的用途，而不是普通私有字段。———

  // 总开关开着时的会话级"排除名单"：true = 这个会话不翻。
  @Trace optOut: boolean = false;
  // 总开关关着时的会话级"加入名单"：true = 只翻这个会话。
  @Trace optIn: boolean = false;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的
  // 值，与页面同名字段的初值一致。
  private host: TranslationDriverHost = {
    chatId: (): number => 0,
    store: (): MessageStore | null => null,
    groups: (): AlbumGroup[] => [],
    isTranslatable: (): boolean => false,
    setIsTranslatable: (_value: boolean): void => {},
    driveVisibleWork: (): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: TranslationDriverHost): void {
    this.host = host;
  }

  // ——— 会话重置：路由参数就绪后的初值 ———

  // 搬之前是 resolveRouteAndResetSession() 里紧跟 this.chatId 赋值之后的两行
  // 直接字段赋值：排除名单/加入名单都是本地存储，chatId 一确定就能读，不用等
  // getChat 回来。chatId 由调用方显式传入（页面此刻刚把 this.chatId 设成新值，
  // 传参比再经 host.chatId() 绕一圈更直接，也避免本类对"页面字段已经写完"这件
  // 事做隐含假设）。
  load(chatId: number): void {
    this.optOut = translateOptedOut(chatId);
    this.optIn = translateOptedIn(chatId);
  }

  // ——— 三态判定：这个会话此刻到底翻不翻 ———

  // 总开关是"默认值"，会话级那一项是对默认值的反转：开着就是排除名单，关着
  // 就是白名单。判定本身在 util/translationMode.ets（有单测），这里只是把
  // 页面里散落的三处调用点收成一个方法。
  //
  // 【热路径纪律】prepareMessageBubble 的 cacheKey 每行都读一次
  // （不变量 1），方法体必须零分配、无日志——三个字段读取 + 一次纯函数调用，
  // 不能有 new/日志/额外的间接层。enabled 由调用方显式传入
  // （this.translation.active(this.translateChatsEnabled)），本类不缓存这个
  // @Param。
  active(enabled: boolean): boolean {
    return isTranslationActive(enabled, this.optOut, this.host.isTranslatable(), this.optIn);
  }

  // 总开关在设置页被改动后，当前页要立刻跟上：开了就把可见范围补翻，关了就把
  // 已经渲染出来的译文收走（服务的缓存留着，再开秒回）。
  // 搬之前是 ChatPage.onTranslateSettingChanged() 的方法体；@Monitor 装饰器
  // 本身留在页面（见文件头说明），页面方法一行转发到这里，显式传
  // this.translateChatsEnabled。
  onSettingChanged(enabled: boolean): void {
    if (this.active(enabled)) {
      this.host.driveVisibleWork();
    } else {
      this.host.store()?.clearTranslations();
    }
  }

  // 可见范围（外扩几行缓冲）内还没有当前目标语言译文的消息，交给
  // TranslationService 排队。结果回来经 store.applyTranslation 写入条目，
  // 内容签名变化触发 CHANGE，气泡里长出译文块。
  // 搬之前是 ChatPage.driveTranslations()；enabled 由调用方（页面的
  // driveVisibleWork()/handleTimelineScrollIndex()）显式传入
  // this.translateChatsEnabled，本类不缓存这个 @Param。
  drive(enabled: boolean, startIdx: number, endIdx: number): void {
    const store: MessageStore | null = this.host.store();
    const groups: AlbumGroup[] = this.host.groups();
    if (!this.active(enabled) || store === null || groups.length === 0) {
      return;
    }
    const lang: string = resolveTranslateTarget();
    const from: number = Math.max(0, startIdx - 3);
    const to: number = Math.min(groups.length - 1, endIdx + 3);
    if (from > to) {
      return;
    }
    const fromId: number = groups[from].head.id;
    const toGroup: AlbumGroup = groups[to];
    const toId: number = toGroup.memberIds[toGroup.memberIds.length - 1];
    const service: TranslationService = getTranslationService(getTdClient());
    for (const m of store.translationCandidates(fromId, toId, lang)) {
      // 已经是目标语言（按文字系统判定）就不发请求。拉丁字母目标语言判不了，
      // 仍交给服务器（结果按内容版本缓存，只花一次往返）。
      if (looksLikeTargetLanguage(m.text, lang)) {
        continue;
      }
      const hit: string | null = service.cached(this.host.chatId(), m.id, m.editDate, lang);
      if (hit !== null) {
        // 译文与原文相同（同语言消息）就什么都不写，气泡不长翻译块。
        if (hit !== '' && hit !== m.text) {
          store.applyTranslation(m.id, lang, hit);
        }
        continue;
      }
      const requestedId: number = m.id;
      const originalText: string = m.text;
      service.request(this.host.chatId(), m.id, m.editDate, lang, (text: string | null): void => {
        if (text !== null && text !== '' && text !== originalText && this.host.store() === store) {
          store.applyTranslation(requestedId, lang, text);
        }
      });
    }
  }

  // 就地翻译一条消息：长按菜单的「翻译」和失败行上的「重试」共用。
  //
  // 先调 service.retry() 清掉失败冷却：TranslationService 失败后有 60 秒静默
  // 期，不清掉的话紧接着的 request() 会被直接挡下、界面上什么都不会发生。
  // 对从没失败过的消息，这一步是无副作用的空操作。
  // 搬之前是 ChatPage.translateInline()。不检查 active()——这是用户手动点的
  // 「翻译」/「重试」，与总开关/会话级开关状态无关，原 ChatPage 代码里也没有
  // 这道检查。
  translateInline(id: number): void {
    const store: MessageStore | null = this.host.store();
    if (store === null) {
      return;
    }
    const target: MessageEntry | undefined =
      store.getMessages().find((e: MessageEntry): boolean => e.id === id);
    if (target === undefined) {
      return;
    }
    const lang: string = resolveTranslateTarget();
    const service: TranslationService = getTranslationService(getTdClient());
    service.retry(this.host.chatId(), id, target.editDate, lang);
    const originalText: string = target.text;
    service.request(this.host.chatId(), id, target.editDate, lang,
      (text: string | null): void => {
        if (text !== null && text !== '' && text !== originalText && this.host.store() === store) {
          store.applyTranslation(id, lang, text);
        }
      });
  }

  // 搬之前是 ChatPage.toggleTranslationHidden()。长按菜单"隐藏译文"调用。
  toggleHidden(id: number, hidden: boolean): void {
    this.host.store()?.setTranslationHidden(id, hidden);
  }

  // 菜单里那一项永远是"把当前状态反过来"，但落到哪个开关上取决于总开关：
  // 总开关开着时写本地排除名单（纯本地，不会失败）；总开关关着时才走
  // 服务端的 toggleChatIsTranslatable，跟官方客户端保持同一份状态。
  // 搬之前是 ChatPage.toggleTranslatable()；enabled 由调用方显式传入
  // this.translateChatsEnabled，本类不缓存这个 @Param。isTranslatable 的读写
  // 全部经 host.isTranslatable()/host.setIsTranslatable()（所有权裁决见文件头）。
  toggleTranslatable(enabled: boolean): void {
    const decision: TranslateToggle = toggleTranslation(
      enabled, this.optOut, this.host.isTranslatable(), this.optIn);
    const next: boolean = decision.active;
    if (decision.writesOptOut) {
      this.optOut = decision.optOut;
      setTranslateOptedOut(this.host.chatId(), decision.optOut);
      this.afterToggled(next);
      return;
    }
    const previous: boolean = this.host.isTranslatable();
    this.host.setIsTranslatable(decision.translatable);
    // 本地也记一份：服务端那次写未必落盘（见 translationMode 的说明），
    // 只靠它的话用户下次进来又得手动开一遍。
    this.optIn = next;
    setTranslateOptedIn(this.host.chatId(), next);
    this.afterToggled(next);
    const req: TdRequest = { '@type': 'toggleChatIsTranslatable' };
    req['chat_id'] = this.host.chatId();
    req['is_translatable'] = next;
    getTdClient().send(req).catch((e: TdError): void => {
      this.host.setIsTranslatable(previous);
      logE(`TranslationDriver.toggleTranslatable failed: ${e.message}`);
      promptAction.showToast({ message: str('cp_setting_failed_msg', e.message), duration: 1800 });
    });
  }

  // 搬之前是 ChatPage.afterTranslationToggled()。toggleTranslatable() 唯一
  // 调用者，两个分支收尾都要经过它：开着补翻可见范围，关着收走已渲染译文，
  // 最后一律弹一次开关状态的 toast。
  private afterToggled(active: boolean): void {
    if (active) {
      this.host.driveVisibleWork();
    } else {
      // 关掉时立刻把已渲染的译文收走；服务的缓存保留，再开秒回。
      this.host.store()?.clearTranslations();
    }
    promptAction.showToast({
      message: active
        ? $r('app.string.cp_auto_translate_enabled') : $r('app.string.cp_auto_translate_disabled'),
      duration: 1500
    });
  }

  // ChatPage.aboutToDisappear 调用，放在原来（本来就不存在的）translate*
  // 清理语句的位置——见文件头「为什么 dispose() 里没有 seq/定时器」：本簇没有
  // 需要在换会话/页面销毁时作废的异步在途请求或定时器句柄，原 ChatPage 代码里
  // aboutToDisappear 也确实没有任何 translate* 字段的清理语句。这个方法仍然
  // 保留、仍然被调用，只是为了让本类的 bind/dispose 成对出现，与仓库里其余
  // @ObservedV2 控制器的生命周期约定保持一致。
  dispose(): void {}
}

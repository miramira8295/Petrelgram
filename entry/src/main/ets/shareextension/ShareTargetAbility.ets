import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { initShareHandoff } from '../services/ShareHandoff';
import { initShareSnapshot, readShareTargetSnapshot } from '../services/ShareTargetSnapshot';
import { parseShareWant } from '../services/ShareInbox';
import { SharedPayload } from '../util/sharedContent';
import { ShareTarget } from '../util/shareTargets';
import { logE, logI } from '../util/log';

// 系统分享面板里就地选人的那一小块界面。
//
// ⚠️ **这是独立进程**，和主应用不共享内存：AppStorage 是空的、TDLib 没有登录
// 态、ChatStore 不存在。它能看见主应用状态的唯一途径是磁盘上那份候选名单
// （services/ShareTargetSnapshot），能把结果送回去的唯一途径是交接文件
// （services/ShareHandoff）。**别在这里 import 任何依赖 store / TDLib 的东西**
// ——那和 FaultLogExtensionAbility 的约束是同一条（见 services/crashRecordStore
// 文件头），扩展进程加载不了就直接崩，用户看到的是"分享面板里点了没反应"。
//
// 生命周期只有一件事：把 want 解析成载荷、把名单读出来，塞进 LocalStorage
// 交给页面。真正的发送在主应用里做。

export default class ShareTargetAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const filesDir: string = this.context.getApplicationContext().filesDir;
    // **不调 initDiagLog**：日志文件是主进程在写的，两个进程共写同一个文件
    // 还带轮转（rename），有竞争；而这里只打两行、根本到不了落盘阈值。
    // logI/logW 本来就会走 console → hilog，`hdc hilog` 里照样看得到。
    initShareSnapshot(filesDir);
    initShareHandoff(filesDir);
    const targets: ShareTarget[] = readShareTargetSnapshot();
    logI(`[Share] panel opened, ${targets.length} cached targets`);

    // 解析要复制文件，是异步的。界面先用空载荷起来（显示"正在准备"），
    // 载荷到位再填——比让分享面板白屏等着强。
    //
    // ⚠️ **初值不能是 null。** LocalStorage 不接受 null/undefined：那样
    // `setOrCreate` 建不出这个 key，后面的 `set` 又只对已存在的 key 生效，
    // 于是**静默失败**，界面里永远是组件自己的默认值。真机现象是整块面板灰着、
    // 按钮点不动（第一版就栽在这里）。所以初值给一个空载荷对象。
    const storage: LocalStorage = new LocalStorage();
    const empty: SharedPayload = { caption: '', media: [] };
    storage.setOrCreate('shareTargets', targets);
    storage.setOrCreate('sharePayload', empty);
    storage.setOrCreate('shareReady', false);
    storage.setOrCreate('shareFailed', false);
    storage.setOrCreate('shareSession', session);
    storage.setOrCreate('shareContext', this.context);
    session.loadContent('pages/share/SharePanel', storage);

    parseShareWant(want, this.context.cacheDir).then(
      (payload: SharedPayload | null): void => {
        if (payload === null) {
          logE('[Share] panel got no usable content');
          storage.set('shareFailed', true);
          storage.set('shareReady', true);
          return;
        }
        storage.set('sharePayload', payload);
        storage.set('shareReady', true);
      }).catch((e: Object): void => {
        logE(`ShareTargetAbility parse failed: ${e}`);
        storage.set('shareFailed', true);
        storage.set('shareReady', true);
      });
  }

  onSessionDestroy(_session: UIExtensionContentSession): void {
    logI('[Share] panel closed');
  }
}

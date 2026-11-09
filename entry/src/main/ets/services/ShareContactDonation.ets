import { common } from '@kit.AbilityKit';
import { insightIntent } from '@kit.IntentsKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ShareTarget } from '../util/shareTargets';
import { logI, logW } from '../util/log';

// 把常聊的会话捐献给意图框架，让它们直接出现在**系统分享面板的头像那一排**
// （不是我们自己的界面——那一排由系统画）。用户点某个头像时，系统会把
// entityId 放进 want，我们在 ShareInbox.contactChatIdOf 里读回来。
//
// ⚠️ **这一块很可能在本应用上跑不通，是有意留着的**：
//
//   · 官方错误码 1000101101「The application has not been registered with the
//     InsightIntent」说明捐献的前提是应用已在**小艺开放平台**注册意图；
//   · 意图名必须是**预置垂域意图**，不允许自定义，而且上架时会校验。
//
// Petrelgram 不在应用市场上，多半拿不到这个注册。所以这里的设计是
// **失败即自动停用**：第一次拿到"未注册"就把开关关掉，本次进程不再尝试，
// 不消耗那每天 20 次的配额、也不在日志里刷屏。分享功能的其余部分
// （面板入口、面板内选人、应用内选择器）完全不依赖它。
//
// 要彻底关掉：把 DONATION_ENABLED 改成 false 即可，没有别的地方引用。

const DONATION_ENABLED: boolean = true;

// 官方限额：每个应用每天最多共享 20 次，每次最多 50KB。所以**一次把整份
// 名单捐完**，而不是每变一个会话捐一次。
const MIN_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
// 一次捐几个。头像那一排显示不了几个，多捐只是占数据量。
const MAX_DONATED: number = 8;

// 意图名与实体名。
//
// ⚠️ **这两个值没有验证过**：能查到的官方文档里，ContactInfo 只举了
// entityName 的例子（'Contact' / 'ChatGroup'），意图名要去「各垂域意图
// Schema」里找，而那份表在开放平台后台。在应用完成注册之前，调用会先被
// 1000101101 挡下来，根本走不到校验名字这一步——所以现在填什么都一样，
// 等真拿到注册再按后台给的名字改这里。
const INTENT_NAME: string = 'ShareContent';
const INTENT_VERSION: string = '1.0.1';
const ENTITY_CONTACT: string = 'Contact';
const ENTITY_GROUP: string = 'ChatGroup';

// 本进程内是否已经放弃。拿到"未注册"之后置位，不再尝试。
let disabled: boolean = !DONATION_ENABLED;
let lastDonatedAt: number = 0;

// Telegram 的 chat id：正数是私聊（联系人），负数是群/频道。
function entityNameOf(target: ShareTarget): string {
  return target.chatId > 0 ? ENTITY_CONTACT : ENTITY_GROUP;
}

// 执行时段。IntentActionInfo 是索引签名类型，里面的嵌套对象也得有声明。
interface DonationTimeSlot {
  executedStartTime: number;
  executedEndTime: number;
}

function intentOf(target: ShareTarget, now: number): insightIntent.InsightIntent {
  const entity: insightIntent.IntentEntityInfo = {
    entityName: entityNameOf(target),
    // entityId 就是 chatId：用户点头像时系统把它原样放进 want，
    // 我们据此直接进那个会话（见 ShareInbox.contactChatIdOf）。
    entityId: `${target.chatId}`
  };
  entity['displayName'] = target.title;
  // 名单已经是"我主动聊得最多"的顺序，名次直接映射成权重。
  entity['rankingHint'] = MAX_DONATED;
  entity['isPublicData'] = false;

  const slot: DonationTimeSlot = { executedStartTime: now, executedEndTime: now };
  const action: insightIntent.IntentActionInfo = {};
  action['actionMode'] = 'EXECUTED';
  action['executedTimeSlots'] = slot;

  return {
    intentName: INTENT_NAME,
    intentVersion: INTENT_VERSION,
    // 标识符按会话固定，这样重复捐献是**更新**同一条而不是堆出一堆重复项。
    identifier: `pg-chat-${target.chatId}`,
    intentActionInfo: action,
    intentEntityInfo: entity
  };
}

// 捐献一次。失败绝不向外抛——这是锦上添花的能力。
export function donateShareTargets(context: common.BaseContext, targets: ShareTarget[]): void {
  if (disabled || targets.length === 0) {
    return;
  }
  const now: number = Date.now();
  if (now - lastDonatedAt < MIN_INTERVAL_MS) {
    return;
  }
  lastDonatedAt = now;
  const intents: insightIntent.InsightIntent[] = [];
  const limit: number = Math.min(targets.length, MAX_DONATED);
  for (let i = 0; i < limit; i++) {
    intents.push(intentOf(targets[i], now));
  }
  try {
    insightIntent.shareIntent(context, intents).then((): void => {
      logI(`[Share] donated ${intents.length} contacts to Intents Kit`);
    }).catch((e: BusinessError): void => {
      handleFailure(e);
    });
  } catch (e) {
    // 设备上根本没有这个服务时 shareIntent 会同步抛。
    disabled = true;
    logW(`[Share] contact donation unavailable, disabled for this session: ${e}`);
  }
}

// 1000101101 = 应用没在意图框架注册。这不是偶发错误，重试多少次都一样，
// 直接停用本次进程的捐献，别把每天 20 次的配额烧在必败的调用上。
function handleFailure(e: BusinessError): void {
  if (e.code === 1000101101) {
    disabled = true;
    logW('[Share] contact donation needs InsightIntent registration; disabled');
    return;
  }
  logW(`[Share] contact donation failed (code ${e.code}): ${e.message}`);
}

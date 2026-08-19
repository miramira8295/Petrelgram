// 附件面板里有哪些格子、每格长什么样。
//
// 抽出来是因为原先 ChatPage.attachMenuItems() 把三件事揉在一起：有哪些项、
// 每项显示什么、点了做什么。改成面板之后前两件要给一个纯展示组件用，第三件
// 留在 ChatPage；顺带这份"私聊不能发投票"的规则也就能脱离 UI 单测了。

// 面板格子的标识。分发靠它，所以这份表是全集——列表里冒出表外的 key，
// 就是一个点了没反应的格子。
export const ATTACH_KEYS: string[] =
  ['media', 'file', 'audio', 'videoNote', 'location', 'contact', 'poll', 'dice'];

export interface AttachAction {
  key: string;
  // sys.symbol 的名字。**缺名不会报错，会静默画成空白**——music_note 和
  // chart_bar 就是这么空了一版才被截图抓到。新符号必须先在项目里找到已有的
  // 使用点，或者上机看过再用。
  icon: string;
  label: Resource;
  // 图标圆底的颜色。取 AVATAR_PALETTE 同族的实色，和头像占位色是一套观感。
  tint: string;
}

// 顺序是这份列表最要紧的东西——面板是肌肉记忆，用户记的是位置不是文字。
//
// 第一行：把一份现成的东西发出去。
// 第二行：现场构造一条结构化消息。
//
// 投票排在倒数第二不是随手放的：它是唯一会因会话类型消失的一项，放在这里，
// 私聊时只有骰子一个格子会挪位。
const ORDER: AttachAction[] = [
  { key: 'media', icon: 'sys.symbol.picture', label: $r('app.string.cp_photo_or_video'), tint: '#65AADD' },
  { key: 'file', icon: 'sys.symbol.doc', label: $r('app.string.storage_file'), tint: '#7BC862' },
  { key: 'audio', icon: 'sys.symbol.speaker_wave_2', label: $r('app.string.storage_audio'), tint: '#EFA92E' },
  { key: 'videoNote', icon: 'sys.symbol.video', label: $r('app.string.cp_video_message'), tint: '#6EC9CB' },
  { key: 'location', icon: 'sys.symbol.map', label: $r('app.string.loc_location'), tint: '#E17076' },
  { key: 'contact', icon: 'sys.symbol.person', label: $r('app.string.tab_contacts'), tint: '#A695E7' },
  { key: 'poll', icon: 'sys.symbol.data_proportion', label: $r('app.string.poll_word'), tint: '#EE7AAE' },
  { key: 'dice', icon: 'sys.symbol.gamecontroller', label: $r('app.string.cp_dice'), tint: '#FAA774' }
];

// 投票仅群/频道可发——这是 Telegram 的限制，不是本端的选择。
function allowed(action: AttachAction, isGroup: boolean, isChannel: boolean): boolean {
  if (action.key === 'poll') {
    return isGroup || isChannel;
  }
  return true;
}

// 这个会话能用的格子，按固定顺序。
export function attachActions(isGroup: boolean, isChannel: boolean): AttachAction[] {
  return ORDER.filter((a: AttachAction): boolean => allowed(a, isGroup, isChannel));
}

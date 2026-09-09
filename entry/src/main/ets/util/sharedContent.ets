// 系统分享送进来的数据 → 我们自己的发送模型。纯函数，无 IO，无 SDK 依赖。
//
// 【为什么要自己分类】systemShare 给的是 UTD（uniform type descriptor）字符串，
// 是一棵树：general.jpeg → general.image → general.media → general.object。
// 分享方填的是最具体那一层，而我们只关心"当图发、当视频发、还是当文件发"。
// 穷举叶子类型是不可能的（SDK 里两百多个），所以：
//   1. 先按已知的常见叶子/中间类型直接判；
//   2. 判不出来就看 URI 的扩展名；
//   3. 再判不出来就当**文件**发——这一档永远成立，不会丢数据。
// 调用方还可以在第 1 步之前用 UTD 的 belongsTo() 把未知类型归化到中间类型
// （见 kindFromAncestor），那是增量优化，缺了也不影响正确性。

export type SharedKind = 'text' | 'link' | 'image' | 'video' | 'audio' | 'file';

// systemShare.SharedRecord 的结构子集。单独声明一份，这样纯逻辑不依赖 HMS SDK，
// 单测可以直接构造。
export interface SharedRecordLike {
  utd: string;
  uri?: string;
  content?: string;
  title?: string;
}

export interface SharedItem {
  kind: SharedKind;
  // 文件类的本地路径/URI；纯文本与链接为空串。
  uri: string;
  // 文本类的正文；文件类为空串。
  text: string;
  // 分享方给的标题，可能为空。只用于界面预览，不进消息体。
  title: string;
  // 分享方原始的 URI（复制进沙箱**之前**那个）。
  //
  // 【为什么要留着】实况照片的动态部分不在文件里，要拿这个 URI 去媒体库查
  // （photoAccessHelper 按 PhotoKeys.URI 查 subtype，见 util/movingPhotoPick）。
  // 只留复制后的路径就永远只能当普通图发——用户报的「实况照片分享变成图片了」。
  // 媒体库查不到（不是相册来的、授权已过期）时退回按 uri 那份文件发，不影响主链路。
  sourceUri: string;
}

// 中间类型 → 我们的分类。调用方用 UTD 的 belongsTo() 把未知叶子归化到这里的
// 某个 key，就能命中。
const ANCESTOR_KIND: Record<string, SharedKind> = {
  'general.image': 'image',
  'general.video': 'video',
  'general.audio': 'audio',
  'general.hyperlink': 'link',
  'general.plain-text': 'text',
  'general.text': 'text'
};

// 常见叶子类型的直判表。命中率高的放这里，省一次 SDK 调用。
const UTD_KIND: Record<string, SharedKind> = {
  'general.plain-text': 'text',
  'general.text': 'text',
  'general.html': 'text',
  'general.markdown': 'text',
  'general.hyperlink': 'link',
  'general.image': 'image',
  'general.jpeg': 'image',
  'general.png': 'image',
  'general.heif': 'image',
  'general.heic': 'image',
  'general.bmp': 'image',
  'general.tiff': 'image',
  'general.webp': 'image',
  'general.svg': 'image',
  'general.gif': 'image',
  'general.raw-image': 'image',
  'general.video': 'video',
  'general.mpeg': 'video',
  'general.mpeg-4': 'video',
  'general.mpeg-2': 'video',
  'general.avi': 'video',
  'general.ms-wmv': 'video',
  'general.matroska-video': 'video',
  'general.audio': 'audio',
  'general.mp3': 'audio',
  'general.mpeg-4-audio': 'audio',
  'general.wav': 'audio',
  'general.flac': 'audio',
  'general.ogg': 'audio',
  'general.aac': 'audio',
  'general.file': 'file',
  'general.folder': 'file',
  'general.pdf': 'file'
};

const EXT_KIND: Record<string, SharedKind> = {
  'jpg': 'image', 'jpeg': 'image', 'png': 'image', 'webp': 'image', 'gif': 'image',
  'bmp': 'image', 'heic': 'image', 'heif': 'image', 'tiff': 'image', 'svg': 'image',
  'mp4': 'video', 'mov': 'video', 'mkv': 'video', 'avi': 'video', 'webm': 'video',
  '3gp': 'video', 'm4v': 'video',
  'mp3': 'audio', 'm4a': 'audio', 'wav': 'audio', 'flac': 'audio', 'ogg': 'audio',
  'aac': 'audio', 'opus': 'audio'
};

// URI 末尾的扩展名，小写、不含点。取不到返回空串。
export function extensionOf(uri: string): string {
  if (uri === '') {
    return '';
  }
  // 查询串和锚点先切掉：内容 URI 常带 ?xxx
  let path: string = uri;
  const q: number = path.indexOf('?');
  if (q >= 0) {
    path = path.substring(0, q);
  }
  const slash: number = path.lastIndexOf('/');
  const name: string = slash >= 0 ? path.substring(slash + 1) : path;
  const dot: number = name.lastIndexOf('.');
  if (dot <= 0 || dot === name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 已知的中间类型 → 分类。调用方拿 belongsTo() 的结果喂进来。
export function kindFromAncestor(ancestor: string): SharedKind | undefined {
  return ANCESTOR_KIND[ancestor];
}

// UTD 直判表里的祖先候选，按从具体到宽泛排列。调用方按这个顺序问 belongsTo()。
export function ancestorCandidates(): string[] {
  return ['general.image', 'general.video', 'general.audio',
    'general.hyperlink', 'general.plain-text'];
}

// 单条记录的分类。`ancestor` 是可选的归化结果（见文件头第 3 段）。
export function classifyRecord(rec: SharedRecordLike, ancestor: string = ''): SharedKind {
  const direct: SharedKind | undefined = UTD_KIND[rec.utd];
  if (direct !== undefined) {
    // 图/视频/音频类必须有 uri 才成立；只给了 content 的当文本发。
    if ((rec.uri ?? '') === '' && direct !== 'text' && direct !== 'link') {
      return (rec.content ?? '') !== '' ? 'text' : 'file';
    }
    return direct;
  }
  if (ancestor !== '') {
    const byAncestor: SharedKind | undefined = ANCESTOR_KIND[ancestor];
    if (byAncestor !== undefined) {
      return byAncestor;
    }
  }
  const byExt: SharedKind | undefined = EXT_KIND[extensionOf(rec.uri ?? '')];
  if (byExt !== undefined) {
    return byExt;
  }
  if ((rec.uri ?? '') === '') {
    return (rec.content ?? '') !== '' ? 'text' : 'file';
  }
  return 'file';
}

// 一条记录 → 一个待发项。无效记录（既没 uri 也没 content）返回 null，
// 由调用方丢弃——这是系统边界，不信任任何字段。
export function itemOf(rec: SharedRecordLike, ancestor: string = ''): SharedItem | null {
  const uri: string = rec.uri ?? '';
  const content: string = rec.content ?? '';
  if (uri === '' && content === '') {
    return null;
  }
  const kind: SharedKind = classifyRecord(rec, ancestor);
  const isTextual: boolean = kind === 'text' || kind === 'link';
  return {
    kind: kind,
    uri: isTextual ? '' : uri,
    text: isTextual ? (content !== '' ? content : uri) : '',
    title: rec.title ?? '',
    sourceUri: isTextual ? '' : uri
  };
}

// 一次分享可能带多条记录（选了 5 张图 = 5 条）。文本和媒体混在一起时，
// Telegram 的惯例是**文本当作媒体的说明文字**，而不是先发一条文本再发媒体。
// 这个函数把待发项拆成"说明文字 + 媒体列表"。
export interface SharedPayload {
  // 说明文字。没有文本记录时为空串。
  caption: string;
  media: SharedItem[];
}

export function splitPayload(items: SharedItem[]): SharedPayload {
  const texts: string[] = [];
  const media: SharedItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: SharedItem = items[i];
    if (item.kind === 'text' || item.kind === 'link') {
      if (item.text !== '') {
        texts.push(item.text);
      }
    } else {
      media.push(item);
    }
  }
  return { caption: texts.join('\n'), media: media };
}

// 分享面板/选择页上给用户看的一行摘要。
export function previewOf(payload: SharedPayload): string {
  if (payload.media.length === 0) {
    return payload.caption;
  }
  const first: SharedItem = payload.media[0];
  const name: string = first.title !== '' ? first.title : extensionOf(first.uri).toUpperCase();
  return payload.media.length > 1 ? `${name} +${payload.media.length - 1}` : name;
}

// --- 跨进程交接 -----------------------------------------------------------
//
// 分享面板里那块界面跑在独立进程，它只负责"选人"，真正发送在主应用进程里。
// 两边靠一个交接文件通信（见 services/ShareHandoff），这里是它的编解码。
// 和快照一样：**解析失败一律当作"没有交接"**，宁可丢一次分享也不能崩。

export const HANDOFF_VERSION: number = 1;

export interface ShareHandoff {
  // 用户在面板里选中的会话。0 表示没选（让主应用自己弹选择页）。
  chatId: number;
  // 面板上「直接发送 / 进会话编辑」那个档（见 util/shareSendMode）。
  // true = 主应用打开后立刻发出并退回后台，不经过输入框。
  autoSend: boolean;
  payload: SharedPayload;
}

export function serializeHandoff(handoff: ShareHandoff): string {
  const payload: Record<string, Object> = {
    'version': HANDOFF_VERSION,
    'chatId': handoff.chatId,
    'autoSend': handoff.autoSend,
    'caption': handoff.payload.caption,
    'media': handoff.payload.media
  };
  return JSON.stringify(payload);
}

export function parseHandoff(text: string): ShareHandoff | null {
  if (text === '') {
    return null;
  }
  let raw: Record<string, Object> | null = null;
  try {
    raw = JSON.parse(text) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  if (raw === null || (raw['version'] as number | undefined) !== HANDOFF_VERSION) {
    return null;
  }
  const list = raw['media'] as Object[] | undefined;
  const media: SharedItem[] = [];
  if (list !== undefined && Array.isArray(list)) {
    for (let i = 0; i < list.length; i++) {
      const row = list[i] as Record<string, Object> | null;
      if (row === null) {
        continue;
      }
      const uri = row['uri'] as string | undefined;
      const kind = row['kind'] as string | undefined;
      // 媒体项没有路径就是废的：交接的前提是文件已经复制进沙箱。
      if (uri === undefined || uri === '' || kind === undefined) {
        continue;
      }
      media.push({
        kind: kind as SharedKind,
        uri: uri,
        text: '',
        title: (row['title'] as string | undefined) ?? '',
        sourceUri: (row['sourceUri'] as string | undefined) ?? ''
      });
    }
  }
  const caption: string = (raw['caption'] as string | undefined) ?? '';
  if (caption === '' && media.length === 0) {
    return null;
  }
  return {
    chatId: (raw['chatId'] as number | undefined) ?? 0,
    // 缺字段按 false：老格式的交接文件（升级前留下的）宁可多一步确认，
    // 也不要莫名其妙把东西发出去。
    autoSend: (raw['autoSend'] as boolean | undefined) ?? false,
    payload: { caption: caption, media: media }
  };
}

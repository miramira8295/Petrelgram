// 输入框此刻在做什么：普通输入、回复某条、编辑某条。
//
// 这三种状态共用输入框上方那一条，而它们此前是**两组互相独立的字段**
// （replyToId/Name/Text 与 editingId/Kind/Preview），谁都能单独改。结果就是
// 真实发生过的那个 bug：进入编辑态时没人清掉待回复，编辑条把回复条盖住，
// 回复却仍然生效——用户看不见也取消不掉，发出去时 replyToId 还在。
//
// 做成一个状态机之后，"进编辑就没有待回复"不再是某个函数里的一行，而是
// 转换函数的后置条件，能被单测钉住。
//
// 只管状态，不碰输入法、焦点、滚动——那些只有页面做得了。

export const COMPOSER_IDLE: string = 'idle';
export const COMPOSER_REPLY: string = 'reply';
export const COMPOSER_EDIT: string = 'edit';

export interface ComposerMode {
  kind: string;
  // 回复：目标消息、显示的名字与摘要。
  replyToId: number;
  replyName: string;
  replyText: string;
  // 回复条左侧那张缩略图（贴纸/图片/视频封面，见 util/replyThumb）。空串 = 无图。
  replyThumb: string;
  replyThumbSticker: boolean;
  // 编辑：目标消息、'text' 还是 'caption'、条上显示的原文。
  editingId: number;
  editingKind: string;
  editingPreview: string;
  // 进入编辑前的草稿，取消时要还回去。
  draftBeforeEdit: string;
}

export function idleComposer(): ComposerMode {
  return {
    kind: COMPOSER_IDLE,
    replyToId: 0, replyName: '', replyText: '',
    replyThumb: '', replyThumbSticker: false,
    editingId: 0, editingKind: '', editingPreview: '',
    draftBeforeEdit: ''
  };
}

// 回复某条。若正在编辑，编辑先作废——两者共用同一条，同时存在必然有一个
// 是隐形的。
export function enterReply(
  state: ComposerMode, messageId: number, name: string, snippet: string,
  thumb: string = '', thumbSticker: boolean = false
): ComposerMode {
  if (messageId <= 0) {
    return state;
  }
  return {
    kind: COMPOSER_REPLY,
    replyToId: messageId, replyName: name, replyText: snippet,
    replyThumb: thumb, replyThumbSticker: thumbSticker,
    editingId: 0, editingKind: '', editingPreview: '',
    draftBeforeEdit: ''
  };
}

export function clearReply(state: ComposerMode): ComposerMode {
  if (state.kind !== COMPOSER_REPLY) {
    return state;
  }
  return idleComposer();
}

// 编辑某条。**必定清掉待回复**——这就是那个 bug 的不变量化。
// draftBeforeEdit 只在首次进入时记录：编辑期间再切换目标不该把原草稿冲掉。
export function enterEdit(
  state: ComposerMode, messageId: number, editKind: string,
  preview: string, currentDraft: string
): ComposerMode {
  if (messageId <= 0) {
    return state;
  }
  const keepDraft: string = state.kind === COMPOSER_EDIT ? state.draftBeforeEdit : currentDraft;
  return {
    kind: COMPOSER_EDIT,
    replyToId: 0, replyName: '', replyText: '',
    replyThumb: '', replyThumbSticker: false,
    editingId: messageId, editingKind: editKind, editingPreview: preview,
    draftBeforeEdit: keepDraft
  };
}

export function cancelEdit(state: ComposerMode): ComposerMode {
  if (state.kind !== COMPOSER_EDIT) {
    return state;
  }
  return idleComposer();
}

// 取消编辑时要还回去的草稿。不在编辑态就没有可还的，返回空串由调用方忽略。
export function draftToRestore(state: ComposerMode): string {
  return state.kind === COMPOSER_EDIT ? state.draftBeforeEdit : '';
}

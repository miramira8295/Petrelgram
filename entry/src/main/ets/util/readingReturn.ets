// 右下角「↓」的去向。
//
// 它不是"回到底部"，而是"把我带回刚才该继续看的地方"。三级优先级：
//
//   引用跳转返回  >  阅读进度  >  最新消息
//
// 之所以抽成纯函数：这套优先级要覆盖"未读阅读 + 引用链"的组合，规则本身
// 值得单独钉住（见 ReadingReturn.test），而页面那边只负责把状态喂进来、
// 把结果执行掉。

export const RETURN_NONE: string = 'none';     // 已在该在的位置，按钮隐藏
export const RETURN_JUMP: string = 'jump';     // 原路退回上一跳
export const RETURN_READ: string = 'read';     // 回到阅读进度
export const RETURN_LATEST: string = 'latest'; // 回到最新消息

export interface ReturnState {
  // 引用跳转的返回栈，后进先出。存的是"跳走之前所在的那条消息"。
  jumpStack: number[];
  // 正常阅读推进到的位置；0 表示没有需要恢复的阅读进度。
  readAnchor: number;
}

export interface ReturnTarget {
  kind: string;
  // RETURN_JUMP / RETURN_READ 时是目标消息 id；RETURN_LATEST 时为 0。
  messageId: number;
}

export function emptyReturnState(): ReturnState {
  return { jumpStack: [], readAnchor: 0 };
}

// 当前视口是否已经落在阅读进度上或更靠后。id 随时间递增，所以"更靠后"
// 就是"id 更大"。currentId 为 0（还不知道看的是哪条）时按"未偏离"处理，
// 免得刚进页面就冒出一个指向自己的箭头。
function atOrPastAnchor(state: ReturnState, currentId: number): boolean {
  return state.readAnchor === 0 || currentId === 0 || currentId >= state.readAnchor;
}

// 「↓」这一下该去哪。atLatest = 视口已经贴着最新消息。
export function nextReturnTarget(state: ReturnState, currentId: number,
  atLatest: boolean): ReturnTarget {
  // 1. 引用链没退完：先原路退，退栈顶那一跳。
  if (state.jumpStack.length > 0) {
    return { kind: RETURN_JUMP, messageId: state.jumpStack[state.jumpStack.length - 1] };
  }
  // 2. 偏离了阅读进度：回到读到的地方，而不是一路扔到底。
  if (!atOrPastAnchor(state, currentId)) {
    return { kind: RETURN_READ, messageId: state.readAnchor };
  }
  // 3. 没有要恢复的阅读位置，但也不在最新：回最新。
  if (!atLatest) {
    return { kind: RETURN_LATEST, messageId: 0 };
  }
  // 4. 已经在该在的位置。
  return { kind: RETURN_NONE, messageId: 0 };
}

// 点了引用/跳转链接，从 fromId 跳走。记下"跳走之前在哪"。
// 连续跳同一条不重复入栈——引用块被连点两下不该要按两次才退得回来。
export function pushJump(state: ReturnState, fromId: number): ReturnState {
  if (fromId <= 0) {
    return state;
  }
  const top: number = state.jumpStack.length > 0
    ? state.jumpStack[state.jumpStack.length - 1] : 0;
  if (top === fromId) {
    return state;
  }
  return { jumpStack: [...state.jumpStack, fromId], readAnchor: state.readAnchor };
}

// 退回一跳。
export function popJump(state: ReturnState): ReturnState {
  if (state.jumpStack.length === 0) {
    return state;
  }
  return {
    jumpStack: state.jumpStack.slice(0, state.jumpStack.length - 1),
    readAnchor: state.readAnchor
  };
}

// 阅读进度只前进不后退：往回翻不该把进度带回去，否则「↓」就没有可回的地方了。
export function advanceRead(state: ReturnState, messageId: number): ReturnState {
  if (messageId <= 0 || messageId <= state.readAnchor) {
    return state;
  }
  return { jumpStack: state.jumpStack, readAnchor: messageId };
}

// 用户自己滑到了某个返回点：那一层的返回已经由他自己完成，出栈。
//
// 栈里存的是"跳走之前所在的那条消息"，通常比跳转目标新（id 更大）。视口
// 底部一旦到达或越过它，再让「↓」把人送回那里就是多余的一步。
//
// 从栈顶往下逐层判：连续滑过好几层返回点时，一次全部出清，而不是留着让用户
// 按三下什么都不发生。
export function dropReachedJumps(state: ReturnState, currentId: number): ReturnState {
  if (currentId <= 0 || state.jumpStack.length === 0) {
    return state;
  }
  let end: number = state.jumpStack.length;
  while (end > 0 && state.jumpStack[end - 1] <= currentId) {
    end--;
  }
  if (end === state.jumpStack.length) {
    return state;
  }
  return { jumpStack: state.jumpStack.slice(0, end), readAnchor: state.readAnchor };
}

// 用户自己滚回了最新消息：这趟"返回"已经由他自己完成，整套关系作废。
export function reachedLatest(): ReturnState {
  return emptyReturnState();
}

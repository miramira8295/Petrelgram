export interface ChatRouteParams {
  chatId: number;
  threadRootId: number;
  topicName: string;
  forumTopicId: number;
  directMessagesTopicId: number;
  showJoinedNotice: boolean;
  joinedNoticeIsChannel: boolean;
  jumpTo: number | undefined;
  draftText: string;
  searchQuery: string;
  startSearch: boolean;
}

function numberParam(params: Record<string, Object> | undefined, key: string,
  fallback: number = 0): number {
  if (params === undefined) {
    return fallback;
  }
  return (params[key] as number | undefined) ?? fallback;
}

function stringParam(params: Record<string, Object> | undefined, key: string,
  fallback: string = ''): string {
  if (params === undefined) {
    return fallback;
  }
  return (params[key] as string | undefined) ?? fallback;
}

function boolParam(params: Record<string, Object> | undefined, key: string,
  fallback: boolean = false): boolean {
  if (params === undefined) {
    return fallback;
  }
  return (params[key] as boolean | undefined) ?? fallback;
}

export function parseChatRouteParams(params: Record<string, Object> | undefined): ChatRouteParams {
  return {
    chatId: numberParam(params, 'chatId'),
    threadRootId: numberParam(params, 'threadRootId'),
    topicName: stringParam(params, 'topicName'),
    forumTopicId: numberParam(params, 'forumTopicId'),
    directMessagesTopicId: numberParam(params, 'directMessagesTopicId'),
    showJoinedNotice: boolParam(params, 'showJoinedNotice'),
    joinedNoticeIsChannel: boolParam(params, 'joinedNoticeIsChannel'),
    jumpTo: params !== undefined ? (params['jumpTo'] as number | undefined) : undefined,
    draftText: stringParam(params, 'draftText'),
    searchQuery: stringParam(params, 'searchQuery'),
    startSearch: boolParam(params, 'startSearch')
  };
}

// Navigation state is deliberately kept outside the rendering component. It
// owns only NavDestination plumbing; chat/session state remains in ChatPage.
export class ChatPageNavigationCoordinator {
  private navStack: NavPathStack | undefined = undefined;
  private paramsApplied: boolean = false;

  setStack(stack: NavPathStack): void {
    this.navStack = stack;
  }

  beginRouteApply(): boolean {
    if (this.paramsApplied) {
      return false;
    }
    this.paramsApplied = true;
    return true;
  }

  pop(): boolean {
    if (this.navStack === undefined) {
      return false;
    }
    this.navStack.pop();
    return true;
  }
}

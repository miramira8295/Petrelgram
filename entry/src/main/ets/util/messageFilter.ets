// 群组 / 频道本地消息拦截纯逻辑引擎。
//
// 零 ArkUI / TDLib 运行时依赖，全部规则在变更时一次性预编译为 CompiledChatFilter；
// 无规则会话返回 null，热路径 O(1) 短路，不影响聊天页滚动与渲染速度。

export type FilterMatchField = 'user' | 'nickname' | 'keyword';
export type FilterMatchMode = 'exact' | 'contains' | 'regex';

export interface MessageFilterRule {
  id: string;
  enabled: boolean;
  // 0 = 全局规则（仅作用于群组与频道）；非 0 = 仅作用于指定 chatId。
  chatId: number;
  field: FilterMatchField;
  mode: FilterMatchMode;
  pattern: string;
  // 快捷拦截发送者时同步记录 userId，防止对方改名或删用户名绕过。
  userId?: number;
  note?: string;
}

export interface MessageFilterConfig {
  enabled: boolean;
  // 停用全局规则的会话白名单。
  disabledGlobalChatIds: number[];
  rules: MessageFilterRule[];
}

export interface CompiledChatFilter {
  blockedUserIds: Set<number>;
  blockedUsernames: Set<string>;
  nicknameContains: string[];
  nicknameExact: Set<string>;
  nicknameRegex: RegExp[];
  keywordContains: string[];
  keywordExact: Set<string>;
  keywordRegex: RegExp[];
}

export interface FilterableMessage {
  isOutgoing: boolean;
  isService: boolean;
  senderUserId: number;
  senderName: string;
  senderUsernames: string[];
  text: string;
  caption: string;
  forwardFrom: string;
  linkPreviewTitle: string;
}

export const MAX_FILTER_AUTO_BACKFILL: number = 3;
export const MIN_VISIBLE_INITIAL_MESSAGES: number = 8;

export function emptyMessageFilterConfig(): MessageFilterConfig {
  return {
    enabled: true,
    disabledGlobalChatIds: [],
    rules: []
  };
}

export function normalizeUsernamePattern(raw: string): string {
  const trimmed: string = raw.trim();
  const stripped: string = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  return stripped.trim().toLowerCase();
}

export function validateFilterPattern(field: FilterMatchField, mode: FilterMatchMode, rawPattern: string): boolean {
  const trimmed: string = field === 'user' ? normalizeUsernamePattern(rawPattern) : rawPattern.trim();
  if (trimmed === '') {
    return false;
  }
  if (mode === 'regex' && field !== 'user') {
    try {
      new RegExp(trimmed, 'i');
      return true;
    } catch (_e) {
      return false;
    }
  }
  return true;
}

export function serializeMessageFilterConfig(config: MessageFilterConfig): string {
  return JSON.stringify(config);
}

export function parseMessageFilterConfig(raw: string): MessageFilterConfig {
  if (raw === '') {
    return emptyMessageFilterConfig();
  }
  try {
    const parsed: object = JSON.parse(raw) as object;
    if (parsed === null || Array.isArray(parsed)) {
      return emptyMessageFilterConfig();
    }
    const obj: Record<string, Object> = parsed as Record<string, Object>;
    const enabled: boolean = typeof obj['enabled'] === 'boolean' ? (obj['enabled'] as boolean) : true;
    const rawDisabled = obj['disabledGlobalChatIds'];
    const disabledGlobalChatIds: number[] = [];
    if (Array.isArray(rawDisabled)) {
      for (const item of rawDisabled as Object[]) {
        if (typeof item === 'number' && Number.isFinite(item) && item !== 0 &&
          disabledGlobalChatIds.indexOf(item) < 0) {
          disabledGlobalChatIds.push(item);
        }
      }
    }
    const rawRules = obj['rules'];
    const rules: MessageFilterRule[] = [];
    if (Array.isArray(rawRules)) {
      for (const item of rawRules as Object[]) {
        if (item === null || typeof item !== 'object' || Array.isArray(item)) {
          continue;
        }
        const r: Record<string, Object> = item as Record<string, Object>;
        const id: string = typeof r['id'] === 'string' ? (r['id'] as string) : '';
        const fieldRaw: string = typeof r['field'] === 'string' ? (r['field'] as string) : '';
        const modeRaw: string = typeof r['mode'] === 'string' ? (r['mode'] as string) : '';
        const pattern: string = typeof r['pattern'] === 'string' ? (r['pattern'] as string) : '';
        const chatId: number = typeof r['chatId'] === 'number' && Number.isFinite(r['chatId'] as number)
          ? (r['chatId'] as number) : 0;
        const userId: number = typeof r['userId'] === 'number' && Number.isFinite(r['userId'] as number)
          ? (r['userId'] as number) : 0;
        const note: string = typeof r['note'] === 'string' ? (r['note'] as string) : '';
        if (id === '' || (fieldRaw !== 'user' && fieldRaw !== 'nickname' && fieldRaw !== 'keyword')) {
          continue;
        }
        const field: FilterMatchField = fieldRaw as FilterMatchField;
        const mode: FilterMatchMode = (modeRaw === 'exact' || modeRaw === 'contains' || modeRaw === 'regex')
          ? (modeRaw as FilterMatchMode) : (field === 'user' ? 'exact' : 'contains');
        if (pattern.trim() === '' && !(field === 'user' && userId > 0)) {
          continue;
        }
        const rule: MessageFilterRule = {
          id,
          enabled: typeof r['enabled'] === 'boolean' ? (r['enabled'] as boolean) : true,
          chatId,
          field,
          mode,
          pattern
        };
        if (userId > 0) { rule.userId = userId; }
        if (note !== '') { rule.note = note; }
        rules.push(rule);
      }
    }
    return { enabled, disabledGlobalChatIds, rules };
  } catch (_e) {
    return emptyMessageFilterConfig();
  }
}

export function compileFilterForChat(config: MessageFilterConfig, chatId: number): CompiledChatFilter | null {
  if (!config.enabled || chatId === 0 || config.rules.length === 0) {
    return null;
  }
  const globalDisabled: boolean = config.disabledGlobalChatIds.indexOf(chatId) >= 0;
  const blockedUserIds: Set<number> = new Set<number>();
  const blockedUsernames: Set<string> = new Set<string>();
  const nicknameContains: string[] = [];
  const nicknameExact: Set<string> = new Set<string>();
  const nicknameRegex: RegExp[] = [];
  const keywordContains: string[] = [];
  const keywordExact: Set<string> = new Set<string>();
  const keywordRegex: RegExp[] = [];
  let activeCount: number = 0;

  for (const rule of config.rules) {
    if (!rule.enabled) {
      continue;
    }
    if (rule.chatId === 0) {
      if (globalDisabled) { continue; }
    } else if (rule.chatId !== chatId) {
      continue;
    }
    if (rule.field === 'user') {
      let added: boolean = false;
      if (rule.userId !== undefined && rule.userId > 0) {
        blockedUserIds.add(rule.userId);
        added = true;
      }
      const normUser: string = normalizeUsernamePattern(rule.pattern);
      if (normUser !== '') {
        blockedUsernames.add(normUser);
        added = true;
      }
      if (added) { activeCount++; }
      continue;
    }
    const trimmed: string = rule.pattern.trim();
    if (trimmed === '') {
      continue;
    }
    if (rule.mode === 'regex') {
      try {
        const re: RegExp = new RegExp(trimmed, 'i');
        if (rule.field === 'nickname') {
          nicknameRegex.push(re);
        } else {
          keywordRegex.push(re);
        }
        activeCount++;
      } catch (_e) {
        // 非法正则静默忽略，避免破坏整群消息流。
      }
      continue;
    }
    const lower: string = trimmed.toLowerCase();
    if (rule.field === 'nickname') {
      if (rule.mode === 'exact') {
        nicknameExact.add(lower);
      } else {
        nicknameContains.push(lower);
      }
    } else {
      if (rule.mode === 'exact') {
        keywordExact.add(lower);
      } else {
        keywordContains.push(lower);
      }
    }
    activeCount++;
  }

  if (activeCount === 0) {
    return null;
  }
  return {
    blockedUserIds,
    blockedUsernames,
    nicknameContains,
    nicknameExact,
    nicknameRegex,
    keywordContains,
    keywordExact,
    keywordRegex
  };
}

function matchTextList(
  value: string, exact: Set<string>, contains: string[], regexes: RegExp[]
): boolean {
  if (value === '') {
    return false;
  }
  const lower: string = value.toLowerCase();
  if (exact.size > 0 && exact.has(lower.trim())) {
    return true;
  }
  for (const sub of contains) {
    if (lower.indexOf(sub) >= 0) {
      return true;
    }
  }
  for (const re of regexes) {
    if (re.test(value)) {
      return true;
    }
  }
  return false;
}

export function messageMatchesFilter(
  msg: FilterableMessage, filter: CompiledChatFilter | null
): boolean {
  if (filter === null || msg.isOutgoing || msg.isService) {
    return false;
  }
  if (msg.senderUserId > 0 && filter.blockedUserIds.has(msg.senderUserId)) {
    return true;
  }
  if (filter.blockedUsernames.size > 0 && msg.senderUsernames.length > 0) {
    for (const uname of msg.senderUsernames) {
      if (filter.blockedUsernames.has(uname.toLowerCase())) {
        return true;
      }
    }
  }
  if ((filter.nicknameExact.size > 0 || filter.nicknameContains.length > 0 || filter.nicknameRegex.length > 0) &&
    matchTextList(msg.senderName, filter.nicknameExact, filter.nicknameContains, filter.nicknameRegex)) {
    return true;
  }
  if (filter.keywordExact.size > 0 || filter.keywordContains.length > 0 || filter.keywordRegex.length > 0) {
    if (matchTextList(msg.text, filter.keywordExact, filter.keywordContains, filter.keywordRegex)) {
      return true;
    }
    if (matchTextList(msg.caption, filter.keywordExact, filter.keywordContains, filter.keywordRegex)) {
      return true;
    }
    if (matchTextList(msg.forwardFrom, filter.keywordExact, filter.keywordContains, filter.keywordRegex)) {
      return true;
    }
    if (matchTextList(msg.linkPreviewTitle, filter.keywordExact, filter.keywordContains, filter.keywordRegex)) {
      return true;
    }
  }
  return false;
}

// 整页被拦截时的自动补页判据（带最大连拉上限，防止死循环与无限拉历史）。
export function shouldAutoBackfillFilteredPage(
  isInitial: boolean,
  rawPageCount: number,
  visibleTotal: number,
  visibleAdded: number,
  hasMoreOlder: boolean,
  autoFillCount: number
): boolean {
  if (!hasMoreOlder || rawPageCount <= 0 || autoFillCount >= MAX_FILTER_AUTO_BACKFILL) {
    return false;
  }
  if (isInitial) {
    return visibleTotal < MIN_VISIBLE_INITIAL_MESSAGES;
  }
  return visibleAdded === 0;
}

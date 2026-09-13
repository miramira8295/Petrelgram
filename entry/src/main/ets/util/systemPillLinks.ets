// 系统消息药丸里的「人名可点」（issue #201 第 3 条）。
//
// 药丸文案是 str() 拼出来的一整句（"A 邀请了 B、C"），要让名字各自可点，就得
// 知道每个名字落在句子的哪一段。这里不重新拼句子，而是在**已经拼好的文案里
// 按顺序找名字**：拼句时名字的出现顺序与传入顺序一致，顺序 indexOf 就能把重名
// 也分开（"Bob 邀请了 Bob" 两个 Bob 各得各的区间）。
//
// 规则（用户定的）：名字落在人身上；只有一个人时整颗药丸都是他；其余区域默认
// 文案里最先出现的那个人。

export interface NamedUser {
  userId: number;
  name: string;
}

export interface SystemPillLink {
  userId: number;
  start: number;   // 含
  end: number;     // 不含
}

export interface PillSegment {
  text: string;
  userId: number;    // 0 = 不可点
  isName: boolean;
}

export function linkNamesInLabel(label: string, people: NamedUser[]): SystemPillLink[] {
  const out: SystemPillLink[] = [];
  let cursor: number = 0;
  for (const p of people) {
    if (p.userId <= 0 || p.name === '') {
      continue;
    }
    let at: number = label.indexOf(p.name, cursor);
    if (at < 0) {
      // 传入顺序与文案顺序不一致时从头再找一次，但不能压在已认领的区间上。
      at = label.indexOf(p.name, 0);
      if (at < 0 || overlaps(out, at, at + p.name.length)) {
        continue;
      }
    }
    out.push({ userId: p.userId, start: at, end: at + p.name.length });
    cursor = Math.max(cursor, at + p.name.length);
  }
  return out;
}

function overlaps(links: SystemPillLink[], start: number, end: number): boolean {
  for (const l of links) {
    if (start < l.end && end > l.start) {
      return true;
    }
  }
  return false;
}

export function systemPillDefaultUserId(links: SystemPillLink[]): number {
  let first: SystemPillLink | null = null;
  for (const l of links) {
    if (first === null || l.start < first.start) {
      first = l;
    }
  }
  return first === null ? 0 : first.userId;
}

// 把文案按链接切成交替的段，供 Text 里逐段挂 Span.onClick。非名字段带默认人，
// 这样整颗药丸的文字区域都有落点，而不只是名字那几个字。
export function pillSegments(label: string, links: SystemPillLink[]): PillSegment[] {
  const fallback: number = systemPillDefaultUserId(links);
  const sorted: SystemPillLink[] = links.slice().sort(
    (a: SystemPillLink, b: SystemPillLink): number => a.start - b.start);
  const out: PillSegment[] = [];
  let cursor: number = 0;
  for (const l of sorted) {
    if (l.start > cursor) {
      out.push({ text: label.substring(cursor, l.start), userId: fallback, isName: false });
    }
    out.push({ text: label.substring(l.start, l.end), userId: l.userId, isName: true });
    cursor = l.end;
  }
  if (cursor < label.length) {
    out.push({ text: label.substring(cursor), userId: fallback, isName: false });
  }
  return out;
}

// 「谁回应了」名单的分组（点表情条末尾的「>」弹出，见 pages/chat/ReactorsMenu）。
//
// getMessageAddedReactions 不带 reaction_type 时返回**所有表情混在一起**的一串，
// 每行自带它回应的是哪个表情。弹出的名单要按表情分组：
//   ❤️
//     aaa / bbbb / ccc
//   👍
//     djdoq / jdasjod
// 组的先后按第一次出现的顺序，组内保持服务端给的顺序（最新在前）。纯函数，有单测。

export interface ReactorRow {
  reactionKey: string;  // util/reactions 的 key：emoji 本身，或 'ce:<id>'
  userId: number;       // 用户发的回应；频道/群身份发的为 0
  chatId: number;       // 以频道/群身份回应时的会话 id；用户为 0
  name: string;
}

export interface ReactorGroup {
  reactionKey: string;
  rows: ReactorRow[];
}

export function groupReactors(rows: ReactorRow[]): ReactorGroup[] {
  const groups: ReactorGroup[] = [];
  const index: Map<string, number> = new Map<string, number>();
  for (const r of rows) {
    const at: number | undefined = index.get(r.reactionKey);
    if (at === undefined) {
      index.set(r.reactionKey, groups.length);
      groups.push({ reactionKey: r.reactionKey, rows: [r] });
    } else {
      groups[at].rows.push(r);
    }
  }
  return groups;
}

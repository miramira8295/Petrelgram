// 多选态里"哪些消息被选中"的集合运算。
//
// 选中的单位是**行**不是消息：一条相册消息在列表里是一行，底下挂着若干
// member。所以一行要么整体选中、要么整体不选，不存在选一半——这条不变量
// 决定了下面每个函数的形状。
//
// 抽出来是因为这几处最容易出错，而且错了在 UI 上很隐蔽：
//   - 半选的相册行再点一次，是全选还是全不选（答案：全不选，行是一个整体）；
//   - 消息被撤回后，选中集合里会留下指向不存在消息的 id（幽灵计数）；
//   - 转发要求 id 不重复，而按行追加天然会带进重复。

// 系统消息和被隐藏的消息不参与多选——它们没有可转发/可复制的内容。
const UNSELECTABLE: string[] = ['system', 'hidden'];

export function rowSelectable(contentType: string): boolean {
  return UNSELECTABLE.indexOf(contentType) < 0;
}

// 这一行有没有被选中。任意一个 member 在集合里就算整行选中——半选状态在
// UI 上不存在，所以读取时也按"沾上就算"处理。
export function rowSelected(selectedIds: number[], memberIds: number[]): boolean {
  for (const id of memberIds) {
    if (selectedIds.indexOf(id) >= 0) {
      return true;
    }
  }
  return false;
}

// 点一行：选中的整行移除，未选中的整行加入。半选（比如相册在选中之后又收到
// 新 member）走的是"已选中"那一支，结果是整行清空——一次点击后状态干净，
// 好过让用户在半选里反复横跳。
export function toggleRow(selectedIds: number[], memberIds: number[]): number[] {
  if (rowSelected(selectedIds, memberIds)) {
    return selectedIds.filter((id: number): boolean => memberIds.indexOf(id) < 0);
  }
  // 走到这一支说明整行都没被选中（rowSelected 为假），所以和已选集合不可能
  // 撞号——去重挡的是 memberIds **自己**重复：相册重组时 member 列表由多次
  // 更新拼出来，出现过同一个 id 进来两次，直接展开会让计数虚高、转发带重复。
  const merged: number[] = [...selectedIds];
  for (const id of memberIds) {
    if (merged.indexOf(id) < 0) {
      merged.push(id);
    }
  }
  return merged;
}

// 消息列表变了之后，把选中集合里已经不存在的 id 摘掉。撤回、删除、切换窗口
// 都会让选中集合里留下幽灵 id——计数还在涨，操作却落空。
export function pruneSelection(selectedIds: number[], liveIds: number[]): number[] {
  return selectedIds.filter((id: number): boolean => liveIds.indexOf(id) >= 0);
}

// 转发前的过滤：去掉不能转发的类型，并去重。顺序保持输入顺序，排序由发起
// 转发的那一侧负责（TDLib 要求 message_ids 严格递增）。
export function forwardableIds(ids: number[], contentTypeOf: (id: number) => string): number[] {
  const result: number[] = [];
  for (const id of ids) {
    if (rowSelectable(contentTypeOf(id)) && result.indexOf(id) < 0) {
      result.push(id);
    }
  }
  return result;
}

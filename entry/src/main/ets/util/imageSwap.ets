// CachedImage 的解码/换图判定，抽成纯函数。
//
// 为什么值得单独一个文件：这几条判定决定了「屏幕上会不会出现一帧空白」，
// 而空白帧正是用户看到的闪烁。判定散在组件里就只能靠上机复现来验证；
// 抽出来之后每一条都能用单测钉死（见 test/ImageSwap.test.ets）。
//
// 约定：heldPath 为空串表示当前什么位图都没握着。

// 目标框还没有量出来（宽或高为 0）或者根本没有图时，不该发起解码。
export function isDecodableTarget(path: string, width: number, height: number): boolean {
  return path !== '' && width > 0 && height > 0;
}

// 手上这张位图是不是「正好就是要显示的那张」——路径与解码目标尺寸都一致。
// 尺寸按整像素比较：vp2px 的取整抖动不该算作一次换图。
export function sameDecodeTarget(
  heldPath: string, heldWidth: number, heldHeight: number,
  nextPath: string, nextWidth: number, nextHeight: number
): boolean {
  return heldPath !== '' && heldPath === nextPath
    && Math.round(heldWidth) === Math.round(nextWidth)
    && Math.round(heldHeight) === Math.round(nextHeight);
}

// 新的解码要不要发起。
export function shouldStartDecode(
  heldPath: string, heldWidth: number, heldHeight: number,
  nextPath: string, nextWidth: number, nextHeight: number
): boolean {
  return !sameDecodeTarget(heldPath, heldWidth, heldHeight, nextPath, nextWidth, nextHeight);
}

// **闪烁的核心判定**：在新位图到手之前，要不要先把节点清空。
//
// 只有一种情况必须清空——手上这张属于**另一个源文件**。复用出来的行如果继续
// 画上一条消息的图，那是内容错乱，比空白严重。
//
// 反过来，同一个源文件只是解码目标尺寸变了（例如 photoWidth/photoHeight 元数据
// 晚到，boxHeight 从错值修正到对值），清空就是纯亏：老位图和新位图画的是同一张
// 图，中间那段空窗完全没有必要，用户看到的就是「图闪一下」。
//
// 【issue #188 补充】"另一个源文件"原来是按**路径**判的，但同一条消息自己也会换路径：
// 视频海报换成真缩略图、贴纸换清晰档、元数据晚到重解——这些场景 A、B 画的是同一张图，
// 清空就是在制造闪烁（行复用已关掉，路径变化几乎全是这类升级）。所以判定改按
// **源身份**：调用方传了 key 就比 key（同源保留旧图当占位，直到新图解完——官方 alt
// 占位的语义），没传就退回路径规则，老调用点逐字不变。
export function shouldBlankBeforeDecode(heldPath: string, nextPath: string,
  heldKey: string = '', nextKey: string = ''): boolean {
  if (heldPath === '') {
    return false;
  }
  if (heldKey !== '' && nextKey !== '') {
    return heldKey !== nextKey;
  }
  return heldPath !== nextPath;
}

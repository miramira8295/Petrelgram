// GIF 发送的形状判定（issue #105 的回归）。
//
// 本仓库捆绑的 libtdjson 是「半新半旧」的 schema：photo/video/document 的
// inputMessageXxx 要包装对象，而 sticker 之类仍是裸 InputFile。animation 属于
// 前者——裸发一律回 "InputFile is not specified"。但别的构建未必，所以发送时
// 先试包装、被拒再裸发，这个函数判断「被拒」是不是形状问题。
export function animationShapeRejected(message: string): boolean {
  const m: string = message.toLowerCase();
  return m.indexOf('unknown class') >= 0
    || m.indexOf('unexpected field') >= 0
    || m.indexOf('expected an object') >= 0
    || m.indexOf('inputfile') >= 0;
}

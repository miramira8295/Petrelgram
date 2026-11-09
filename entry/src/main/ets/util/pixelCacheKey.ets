// 像素缓存的键。
//
// 【为什么单独成文件】pixelCache 本身要加载 ImageKit，宿主单测里起不来；而这条
// 键的规则出错的代价很隐蔽，值得钉住。做法与同目录的 imageSwap / decodeSize 一致。
//
// 【为什么像素格式必须进键 —— 2026-09-20】相册格改用 RGB_565 解码之后（每像素
// 2 字节而不是 RGBA_8888 的 4 字节，见 pixelCache.PixelRequest.opaque），同一个
// 文件、同一个目标尺寸会有**两份不同的位图**。键里不带格式，就会把 565 那份喂给
// 要 8888 的调用方——现象是单张大图或头像莫名其妙掉色阶，而且只在"先看过相册"
// 之后才出现，最难查的那一种。
//
// 【尺寸为什么要取整】键是字符串比对，而调用方给的是 vp2px 的结果，同一个 vp 在
// 不同调用点可能差出浮点尾数。差一点点就是两份解码——这正是 mediaBox 文件头里
// 那条"差一像素就是两份解码"的同一条规矩。
export function pixelCacheKey(
  path: string, width: number, height: number, opaque: boolean
): string {
  return `${path}@${Math.round(width)}x${Math.round(height)}${opaque ? '#565' : ''}`;
}

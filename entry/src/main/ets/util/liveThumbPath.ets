// Resolve the image path while a LiveThumbImage attachment is updated.
// Kept pure so the fileId=0 path-only case has a host-side regression test.
export function liveThumbPath(
  fileId: number,
  channelPath: string,
  currentPath: string,
  initialPath: string,
  sameAttachment: boolean
): string {
  // fileId=0 has no usable media channel; initialPath is the entire identity
  // and must replace (or clear) the previous row's path immediately.
  if (fileId === 0) {
    return initialPath;
  }
  if (channelPath !== '') {
    return channelPath;
  }
  // Reattaching the same downloadable file should preserve its decoded image
  // while the row crosses the reuse pool.
  if (sameAttachment && currentPath !== '') {
    return currentPath;
  }
  return initialPath;
}

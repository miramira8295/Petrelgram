export interface CommonMarkNode {
  type: string;
  literal: string | null;
  firstChild: CommonMarkNode | null;
  lastChild: CommonMarkNode | null;
  next: CommonMarkNode | null;
  prev: CommonMarkNode | null;
  parent: CommonMarkNode | null;
  level: number;
  listType: string;
  listStart: number;
  info: string | null;
  destination: string | null;
  title: string | null;
  markdownSource?: string;
}
export default class CommonMarkParser {
  constructor(options?: { smart?: boolean });
  parse(source: string): CommonMarkNode;
}
export function inlineMarkdown(parser: CommonMarkParser, source: string): CommonMarkNode;

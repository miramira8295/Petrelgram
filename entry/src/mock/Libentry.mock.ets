const NativeMock: Record<string, Object> = {
  'tdInit': (onReceive: (json: string) => void) => {
  },
  'tdSend': (json: string) => {
  },
  'tdExecute': (json: string) => {
    return '';
  },
  'tdDestroy': () => {
  },
};

export default NativeMock;

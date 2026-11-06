export type HudStatus = 'working' | 'needs_you' | 'waiting_on_others' | 'ready_to_close'

// The optional paid summary: what a small model wrote the last time this chat was summarized.
export type HudEntry = {
  status: HudStatus
  label: string
  purpose: string
  done: string
  next: string
  updatedAt: number
}

// One chat's status, as the band shows it and as Chat Board reads it from ~/.claude/chat-hud/rows/<sessionId>.json.
// Everything but `summary` costs nothing: it comes from what the chat already does.
export type HudRow = {
  sessionId: string
  // The app's own id and title for the chat, read from its record.
  localId: string | null
  title: string | null
  phase: 'working' | 'idle'
  // When the person last wrote, and when the chat last finished a turn.
  userAt: number
  repliedAt: number
  summary: HudEntry | null
  // The chat's end-of-turn box. A question in it means the chat needs the person.
  turnEnd?: { ask: string | null; recap: string | null; at: number } | null
  // The chat's own answer to "is this chat's purpose done?", given at the end of each turn.
  verdict?: { isDone: boolean; left: string; purpose: string; at: number } | null
  // A question written at the end of the chat's last reply, and when that reply ended.
  textQuestion?: { text: string; at: number } | null
  // A tool call still running. A card waiting on the person (permission, rename, a question) holds the call open,
  // so a call that is normally quick being pending for a while means the chat is waiting for the person's OK.
  // `asked` is set when the permission check put the call to a person.
  pending?: { tool: string; at: number; asked: boolean } | null
}

export type HudKind = 'working' | 'question' | 'your_move' | 'ready'

declare module 'claude-code' {
  interface PluginState {
    'chat-hud': {
      row: HudRow | null
      error: string | null
      isHidden: boolean
      isOff: boolean
      isSummarizing: boolean
    }
  }
}

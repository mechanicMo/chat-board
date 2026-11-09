import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { HudRow } from '../types'
import { ageLabel, buildPrompt, describe, freshSummary, parseReply, purposeOf, questionIn, STATUS_PROMPT, SYSTEM, toRow } from './parse'

const PREFIX = 'chat:'
const USAGE = 'usage:'
const USAGE_ROWS = 500
const STATUS_TOOL = 'chat_status'
const SESSIONS = '/Library/Application Support/Claude/claude-code-sessions'
// How long a Chat Board archive request and its one-time code stay valid.
const TOKEN_LIFE = 60000

const row = atom({ plugin: 'chat-hud', key: 'row' } as const, null)
const error = atom({ plugin: 'chat-hud', key: 'error' } as const, null)
const isHidden = atom({ plugin: 'chat-hud', key: 'isHidden' } as const, false)
const isOff = atom({ plugin: 'chat-hud', key: 'isOff' } as const, false)
const isSummarizing = atom({ plugin: 'chat-hud', key: 'isSummarizing' } as const, false)

// The same four colors as the Chat Board window, as theme keys so they follow light and dark mode.
const COLORS = {
  working: 'inactive',
  question: 'merged',
  your_move: 'warning',
  ready: 'success',
} as const

let latestRun = 0
let recordPath: string | null = null
let isRecordSearched = false
let privateFolders: string[] | null = null
let usageQueue: Promise<void> = Promise.resolve()
// The chat's permission mode as the classic hooks last reported it; null until one has.
let permissionMode: string | null = null

// Modes where an "ask" goes to a person. In auto mode the classifier settles it; dontAsk and bypass never ask.
export const asksPerson = (mode: string | null): boolean =>
  mode !== 'auto' && mode !== 'dontAsk' && mode !== 'bypassPermissions'

// The folder every chat and the Chat Board window share. Files, because the store is read once per process
// and can't carry changes between chats that are already open.
const sharedDir = async ($: EngineInterface): Promise<string | null> => {
  const home = await $.env.get('HOME')
  return home ? home + '/.claude/chat-hud' : null
}

const writeShared = async ($: EngineInterface, name: string, value: unknown) => {
  const dir = await sharedDir($)
  if (dir) await $.fs.write(dir + '/' + name, JSON.stringify(value))
}

const readShared = async ($: EngineInterface, name: string): Promise<unknown> => {
  const dir = await sharedDir($)
  if (!dir) return null
  try {
    return JSON.parse(await $.fs.read(dir + '/' + name))
  } catch {
    return null
  }
}

const BROKEN: string[] = []

// Missing config: no private folders. A config that is there but unreadable, or whose list isn't all strings,
// returns BROKEN, the same rule Chat Board uses.
const readPrivateFolders = async ($: EngineInterface, home: string): Promise<string[]> => {
  const dir = await sharedDir($)
  if (!dir) return []
  let text: string
  try {
    text = await $.fs.read(dir + '/config.json')
  } catch {
    return []
  }
  try {
    const listed = (JSON.parse(text) as { privateFolders?: unknown }).privateFolders ?? []
    if (!Array.isArray(listed) || listed.some(one => typeof one !== 'string')) return BROKEN
    return (listed as string[])
      .map(one => one.trim())
      .map(one => (one === '~' || one.startsWith('~/') ? home + one.slice(1) : one).replace(/\/+$/, ''))
      .filter(one => one !== '')
  } catch {
    return BROKEN
  }
}

// Folders whose chats are never summarized or listed, from ~/.claude/chat-hud/config.json:
// {"privateFolders": ["~/journal"]}. Read once per process, so an open chat sees a change after /reload-plugins.
const isPrivate = async ($: EngineInterface): Promise<boolean> => {
  const home = (await $.env.get('HOME')) ?? ''
  if (!privateFolders) privateFolders = await readPrivateFolders($, home)
  // A config that exists but can't be read fails closed: the chat is treated as private.
  if (privateFolders === BROKEN) return true
  const cwd = await $.session.cwd()
  return privateFolders.some(folder => cwd === folder || cwd.startsWith(folder + '/'))
}

// Every summary's real token count, so its cost is measured rather than guessed.
const recordUsage = ($: EngineInterface, trigger: string, input: number, output: number) => {
  usageQueue = usageQueue.then(async () => {
    const key = USAGE + (await $.session.id())
    const rows = ((await $.store.get(key)) ?? []) as unknown[]
    await $.store.set(key, [...rows, { at: await $.clock.now(), trigger, input, output }].slice(-USAGE_ROWS))
  }).catch(() => {})
  return usageQueue
}

const saveRow = async ($: EngineInterface, change: (current: HudRow) => HudRow) => {
  if ((await read($, isOff)) || (await isPrivate($))) return
  const sessionId = await $.session.id()
  const current: HudRow = (await read($, row)) ?? { sessionId, localId: null, title: null, phase: 'idle', userAt: 0, repliedAt: 0, summary: null }
  const next = change(current)
  if (next === current) return
  await update($, row, () => next)
  await $.store.set(PREFIX + sessionId, next)
  await writeShared($, 'rows/' + sessionId + '.json', next)
}

// The app keeps one record per chat holding its title and the id its links use.
const readChatRecord = async ($: EngineInterface): Promise<{ localId: string; title: string | null } | null> => {
  try {
    if (!recordPath) {
      if (isRecordSearched) return null
      isRecordSearched = true
      const home = await $.env.get('HOME')
      if (!home) return null
      const found = await $.process.run(['grep', '-rlF', '--include=local_*.json', await $.session.id(), home + SESSIONS])
      recordPath = found.stdout.split('\n').find(line => line.trim() !== '')?.trim() ?? null
      if (!recordPath) return null
    }
    const record = JSON.parse(await $.fs.read(recordPath)) as { sessionId?: unknown; title?: unknown }
    if (typeof record.sessionId !== 'string') return null
    return { localId: record.sessionId, title: typeof record.title === 'string' ? record.title : null }
  } catch {
    return null
  }
}

const turnOff = async ($: EngineInterface) => {
  await update($, isOff, () => true)
  await update($, row, () => null)
  const sessionId = await $.session.id()
  await $.store.delete(PREFIX + sessionId)
  // There's no file delete, so a switched-off chat leaves a marker that keeps it off the board.
  await writeShared($, 'rows/' + sessionId + '.json', { sessionId, isOff: true })
}

// The one paid feature, only when the person asks: a small model summarizes the chat.
const summarize = async ($: EngineInterface, trigger: string) => {
  if ((await read($, isOff)) || (await isPrivate($))) return
  const run = ++latestRun
  await update($, isSummarizing, () => true)
  let reply
  try {
    const previous = (await read($, row))?.summary ?? null
    const messages = await $.session.messages()
    reply = await $.model.complete({ model: 'haiku', system: SYSTEM, prompt: buildPrompt(messages, '', previous), maxTokens: 400, timeoutMs: 30000 })
  } finally {
    // Only the newest run clears the indicator, so an older one finishing can't hide a live one.
    if (run === latestRun) await update($, isSummarizing, () => false)
  }
  if (reply.isAnswered) void recordUsage($, trigger, reply.usage.input_tokens, reply.usage.output_tokens)
  if (run !== latestRun) return

  if (!reply.isAnswered) {
    await update($, error, () => `Couldn't summarize (${reply.reason})`)
    return
  }
  const summary = parseReply(reply.text, await $.clock.now())
  if (!summary) {
    await update($, error, () => "Couldn't summarize (unreadable reply)")
    return
  }
  await update($, error, () => null)
  await saveRow($, current => ({ ...current, summary }))
}

// An archive goes through only when it names a chat with a waiting Chat Board request and carries that request's
// one-time code, still fresh. Anything else, the model in any chat included, is refused.
const isChatBoardArchive = async ($: EngineInterface, localId: unknown, reason: unknown): Promise<boolean> => {
  if (typeof localId !== 'string' || typeof reason !== 'string' || !/^local_[A-Za-z0-9-]+$/.test(localId)) return false
  const request = (await readShared($, `requests/archive-${localId}.json`)) as { token?: unknown; at?: unknown } | null
  return (
    typeof request?.token === 'string' &&
    request.token.length >= 16 &&
    reason.includes(`(${request.token})`) &&
    typeof request.at === 'number' &&
    (await $.clock.now()) - request.at <= TOKEN_LIFE
  )
}

// Archives through the app's own tool. The app refuses pinned, working or on-screen chats, and says why.
const archive = async ($: EngineInterface, localId: string, name: string, token: string): Promise<string> => {
  try {
    const answer = await $.mcp.call('ccd_session_mgmt', 'archive_session', { session_id: localId, reason: `Archived from Chat Board (${token})` })
    const said = (answer.content ?? [])
      .map(block => (block && typeof block === 'object' && 'text' in block ? String((block as { text: unknown }).text) : ''))
      .join(' ')
      .trim()
    return answer.isError ? `Couldn't archive ${name}: ${said}` : said || `Archived ${name}.`
  } catch (failure) {
    return `Couldn't archive ${name}: ${String(failure).slice(0, 160)}`
  }
}

// The Chat Board window can't reach the app's archive tool, so it leaves a request file. The first open chat to
// claim one carries it out and writes the app's answer back for the window to show.
const handleRequests = async ($: EngineInterface) => {
  const dir = await sharedDir($)
  if (!dir) return
  let names: string[] = []
  try {
    names = (await $.fs.list(dir + '/requests')).map(entry => entry.name)
  } catch {
    return
  }
  const self = await $.session.id()
  const mine = (await read($, row))?.localId
  for (const name of names) {
    const match = /^archive-(local_[A-Za-z0-9-]+)\.json$/.exec(name)
    if (!match) continue
    const localId = match[1]!
    const base = dir + '/requests/archive-' + localId
    if (names.includes(`archive-${localId}.result.json`) || names.includes(`archive-${localId}.claimed`)) continue
    // A chat leaves its own archive to another chat, so it never ends its own turn mid-answer.
    if (localId === mine) continue
    try {
      const request = JSON.parse(await $.fs.read(base + '.json')) as { at?: unknown; title?: unknown; token?: unknown }
      if (typeof request.at !== 'number' || (await $.clock.now()) - request.at > TOKEN_LIFE) continue
      if (typeof request.token !== 'string' || request.token.length < 16) continue
      await $.fs.write(base + '.claimed', self)
      if ((await $.fs.read(base + '.claimed')) !== self) continue
      const text = await archive($, localId, typeof request.title === 'string' ? request.title : 'that chat', request.token)
      await $.fs.write(base + '.result.json', JSON.stringify({ text, at: await $.clock.now() }))
    } catch {
      // Unreadable or half-written request: leave it for the next pass.
    }
  }
}

// Mark the running main-loop call (the named tool's, when given) as waiting for the person's OK.
const markAsked = ($: EngineInterface, tool?: string) =>
  saveRow($, current =>
    current.pending && (!tool || current.pending.tool === tool) ? { ...current, pending: { ...current.pending, asked: true } } : current,
  ).catch(() => {})

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    await $.command.register({ name: 'hud', description: 'Show this chat\'s status band. "/hud now" summarizes, "/hud off" or "/hud on"' })
    if (await isPrivate($)) {
      await turnOff($)
      return ran
    }

    const sessionId = await $.session.id()
    // The shared file is the newest copy (another process may have written it); the store is the fallback.
    const saved = toRow(await readShared($, 'rows/' + sessionId + '.json')) ?? toRow(await $.store.get(PREFIX + sessionId))
    if (saved) await update($, row, () => saved)
    const chat = await readChatRecord($)
    if (chat) await saveRow($, current => ({ ...current, ...chat }))
    await $.tool.register({
      name: STATUS_TOOL,
      description: "Report whether this chat's purpose is done, so the user knows if they can close it. Call once at the end of every main-conversation turn.",
      inputSchema: {
        type: 'object',
        properties: {
          is_done: { type: 'boolean', description: "True only if this chat's purpose is complete and it could be closed now with nothing lost." },
          left: { type: 'string', description: 'If not done, what still has to happen and who does it. If done, what was finished. One short sentence.' },
          purpose: { type: 'string', description: 'Why this chat exists, in one short sentence.' },
        },
        required: ['is_done', 'left', 'purpose'],
      },
      isDeferred: false,
    })
    // Archive requests from the Chat Board window, checked on local disk only.
    $.clock.every(5000, () => handleRequests($))

    return ran
  })

  on('turn.start', async ($, e, next) => {
    const ran = await next(e)
    if (!e.agentId) {
      const now = await $.clock.now()
      await saveRow($, current => ({ ...current, phase: 'working', pending: null, userAt: e.text.trim() === '' ? current.userAt : now }))
    }
    return ran
  })

  on('turn.complete', async ($, e, next) => {
    const ran = await next(e)
    if (!e.agentId) {
      const now = await $.clock.now()
      const chat = await readChatRecord($)
      const text = e.isAborted ? null : questionIn(e.answer)
      await saveRow($, current => ({
        ...current,
        ...(chat ?? {}),
        phase: 'idle',
        pending: null,
        repliedAt: now,
        textQuestion: e.isAborted ? current.textQuestion : text ? { text, at: now } : null,
      }))
    }
    return ran
  })

  // Every main-loop tool call is marked pending until it returns. A card asking the person (permission, rename,
  // a question) holds the call open, so a normally quick call pending a while means the chat is waiting on them.
  // It only observes: the call itself is never changed or blocked.
  on('tool.call', async ($, e, next) => {
    let at = 0
    if (!(e as { agentId?: string }).agentId) {
      try {
        at = await $.clock.now()
        await saveRow($, current => ({ ...current, pending: { tool: e.tool, at, asked: false } }))
      } catch {
        at = 0
      }
    }
    try {
      return await next(e)
    } finally {
      if (at) await saveRow($, current => (current.pending?.at === at ? { ...current, pending: null } : current)).catch(() => {})
    }
  })

  // When the permission check hands a main-loop call to a person, mark it so the board shows it at once.
  // An "ask" here is settled afterwards by the mode: in auto mode the classifier answers it, almost always
  // without the person, so it marks nothing (the dialog's own notification below does, if one shows).
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (verdict.decision === 'ask' && e.approver === 'person' && !e.agentId && e.tool_use_id && asksPerson(permissionMode)) {
      await markAsked($, e.tool)
    }
    return verdict
  })

  // The permission mode, read from the classic hooks that carry it, so tool.check can tell who settles an ask.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    return next(e)
  })
  on('classic.UserPromptSubmit', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    return next(e)
  })
  // A permission dialog actually put in front of the person: the one sure sign, whatever the mode.
  on('classic.Notification', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    if (e.notification_type === 'permission_prompt' && !e.agent_id) await markAsked($)
    return next(e)
  })

  // The chat's instruction to report its own status. Private and switched-off chats never get it.
  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    if ((await read($, isOff)) || (await isPrivate($))) return composed
    return { ...composed, sections: [...composed.sections, { id: 'chat-hud:status', text: STATUS_PROMPT, scope: 'session' as const }] }
  })

  on('tool.call', { tool: 'mcp__chat-hud__chat_status' }, async ($, e) => {
    // A tool call's arguments sit on the event itself, beside `tool`.
    const input = e as unknown as { is_done?: unknown; left?: unknown; purpose?: unknown }
    const text = (value: unknown) => (typeof value === 'string' ? value.replace(/\s+/g, ' ').trim().slice(0, 240) : '')
    const verdict = { isDone: input.is_done === true, left: text(input.left), purpose: text(input.purpose), at: await $.clock.now() }
    await saveRow($, current => ({ ...current, verdict })).catch(() => {})
    return { result: 'Status recorded.' }
  })

  // The archive guard. Skipping the app's own safety check for this tool is only safe with this in place.
  on('tool.call', { tool: 'mcp__ccd_session_mgmt__archive_session' }, async ($, e, next) => {
    const call = e as unknown as { session_id?: unknown; reason?: unknown }
    if (!(await isChatBoardArchive($, call.session_id, call.reason))) return { deny: 'Archiving is only allowed from the Chat Board window.' }
    return next(e)
  }).catch(($, e, next) => (next.called ? next(e) : { deny: 'Archiving is only allowed from the Chat Board window.' }))

  // The chat's end-of-turn box: a question in it means the chat needs the person.
  on('tool.call', { tool: 'mcp__ccd_turn__wrap_up' }, async ($, e, next) => {
    const ran = await next(e)
    const input = e as unknown as { ask?: unknown; recap?: unknown }
    const clean = (value: unknown) => (typeof value === 'string' && value.trim() !== '' ? value.trim() : null)
    const turnEnd = { ask: clean(input.ask), recap: clean(input.recap), at: await $.clock.now() }
    await saveRow($, current => ({ ...current, turnEnd }))
    return ran
  })

  on('command.run', { command: 'hud' }, async ($, e) => {
    const arg = e.args.trim()
    if (arg === 'off') {
      await turnOff($)
      return { text: 'HUD off for this chat. Nothing from it is summarized or shown on the board. "/hud on" turns it back on.' }
    }
    if (arg === 'on') {
      if (await isPrivate($)) return { text: 'This is a private chat, so the HUD stays off.' }
      await update($, isOff, () => false)
      await saveRow($, current => ({ ...current }))
      return { text: 'HUD on for this chat.' }
    }
    if (await read($, isOff)) return { text: 'The HUD is off for this chat. "/hud on" turns it back on.' }
    await update($, isHidden, () => false)
    if (arg === 'now') {
      void summarize($, 'command')
      return { text: 'Summarizing this chat.' }
    }
    $.ui.invalidate('ui.render')
    return { text: 'HUD shown.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const card = await read($, row)
    const problem = await read($, error)
    if (e.props.hasSurvey || (await read($, isHidden)) || (await read($, isOff)) || (!card && !problem)) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const busy = await read($, isSummarizing)
    const live = card && e.props.isWorking && card.phase !== 'working' ? { ...card, phase: 'working' as const } : card
    const summary = live ? freshSummary(live) : null
    const shown = live ? describe(live, now) : null
    const purpose = live ? purposeOf(live) : null
    const tint = shown ? COLORS[shown.kind] : 'inactive'

    return (
      <Box flexDirection="column" borderStyle="round" borderColor={tint} paddingX={1}>
        <Box flexDirection="row" alignItems="center" justifyContent="space-between" gap={1}>
          <Box flexDirection="row" alignItems="center" gap={1} flexShrink={1}>
            {shown && <Text backgroundColor={tint} color="inverseText" weight="semibold"> {shown.label} </Text>}
            {live?.title && <Text weight="medium" wrap="truncate-end">{live.title}</Text>}
          </Box>
          <Box flexDirection="row" gap={1}>
            {busy ? (
              <Text color="suggestion" italic>Summarizing...</Text>
            ) : (
              !summary && !e.props.isWorking && <Button key="now" label="Summarize now" onPress={() => summarize($, 'button')} />
            )}
            <Button key="hide" label="Hide" role="dismiss" onPress={async () => {
              await update($, isHidden, () => true)
              $.ui.toast('HUD hidden. Type /hud to bring it back.')
            }} />
          </Box>
        </Box>
        {problem && <Text color="error" size="footnote">{problem}</Text>}
        {shown && (
          <Text size="footnote">
            <Text color={tint} weight="semibold">{shown.kind === 'ready' ? 'Done  ' : 'Now  '}</Text>
            {busy ? 'Writing a fresh summary of this chat.' : shown.line}
          </Text>
        )}
        {purpose && <Text size="footnote" color="subtle">Purpose  {purpose}</Text>}
        {summary && (
          <Box flexDirection="column" marginTop={1}>
            <Text size="footnote"><Text color="subtle">Done so far  </Text>{summary.done}</Text>
            <Text size="footnote"><Text color="subtle">Next  </Text>{summary.next}</Text>
            <Text size="caption" color="subtle">Summary from {ageLabel(now - summary.updatedAt)}</Text>
          </Box>
        )}
      </Box>
    )
  })
}

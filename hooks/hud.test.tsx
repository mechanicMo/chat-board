import { expect, mock, test } from 'claude-code/testing'

import cases from '../fixtures/describe-cases'
import { ageLabel, buildPrompt, describe, parseReply, questionIn, toRow, waitingOn } from './parse'

const GOOD = JSON.stringify({
  status: 'needs_you',
  label: 'Reply to Sam',
  purpose: 'Answer Sam about the invoice.',
  done: 'Drafted the reply.',
  next: 'You approve the draft.',
})

const BAND = {
  plugin: 'chat-hud',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 12,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 12 },
    view: {},
  },
  surface: 'desktop',
} as const

const COMPOSE = { model: 'claude-opus-5-5', promptModel: 'claude-opus-5-5', surfaces: ['desktop'], tools: [], outputStyle: null, traits: [] }

const RECORD = '/Users/alex/Library/Application Support/Claude/claude-code-sessions/a/b/local_abc.json'

// Stand-ins for the engine: a store we can read back, the model, the app's chat record and `open`.
const engine = (on: any, reply: unknown, cwd = '/Users/alex/projects') => {
  const saved = new Map<string, unknown>()
  const calls: string[] = []
  const opened: string[][] = []
  on('store.get', (_: unknown, e: any) => ({ value: saved.get(e.key) }))
  on('store.set', (_: unknown, e: any) => {
    saved.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.delete', (_: unknown, e: any) => {
    saved.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...saved.keys()] }))
  on('model.complete', async (_: unknown, e: { prompt: string }) => {
    calls.push(e.prompt)
    return { value: typeof reply === 'function' ? await reply() : reply }
  })
  on('session.messages', () => ({ value: [{ role: 'user', text: 'Help me reply to Sam', toolUses: [] }] }))
  on('session.id', () => ({ value: 'session-a' }))
  on('session.cwd', () => ({ value: cwd }))
  on('env.get', (_: unknown, e: any) => ({ value: e.name === 'HOME' ? '/Users/alex' : undefined }))
  on('process.run', (_: unknown, e: any) => {
    opened.push([...e.argv])
    return { value: { exitCode: 0, stdout: e.argv[0] === 'grep' ? RECORD + '\n' : '', stderr: '' } }
  })
  // The shared board files other chats write, kept in memory.
  const files = new Map<string, { text: string; mtimeMs: number }>()
  let tick = 0
  const writes: { path: string; text: string }[] = []
  on('fs.write', (_: unknown, e: any) => {
    writes.push({ path: String(e.path), text: e.text })
    files.set(String(e.path), { text: e.text, mtimeMs: ++tick })
    return { value: undefined }
  })
  on('fs.read', (_: unknown, e: any) => {
    const path = String(e.path)
    if (path.includes('/.claude/chat-hud/')) {
      const file = files.get(path)
      return file ? { value: file.text } : { deny: 'missing' }
    }
    return {
      value: path.endsWith('local_old.json')
        ? JSON.stringify({ sessionId: 'local_old', title: 'Old chat', isArchived: true })
        : JSON.stringify({ sessionId: 'local_abc', title: '[work] sam - invoice reply', lastActivityAt: 1793898800000 }),
    }
  })
  on('fs.list', (_: unknown, e: any) => {
    const path = String(e.path)
    if (path.includes('/.claude/chat-hud/'))
      return {
        value: [...files.entries()]
          .filter(([name]) => name.startsWith(path + '/') && !name.slice(path.length + 1).includes('/'))
          .map(([name, file]) => ({ name: name.slice(path.length + 1), kind: 'file', size: 1, mtimeMs: file.mtimeMs, isLink: false })),
      }
    return {
      value: [
        { name: 'local_abc.json', kind: 'file', size: 1, mtimeMs: 1, isLink: false },
        { name: 'local_old.json', kind: 'file', size: 1, mtimeMs: 1, isLink: false },
      ],
    }
  })
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { isRegistered: true } }))
  const tools: string[] = []
  on('tool.register', (_: unknown, e: any) => {
    tools.push(e.name)
    return { value: { tool: 'mcp__chat-hud__' + e.name } }
  })
  on('tool.call', { tool: 'mcp__ccd_turn__wrap_up' }, () => ({ result: 'shown' }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'base', scope: 'shared' }] }))
  on('turn.start', () => ({ turnId: 't' }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  return { saved, calls, opened, tools, files, writes }
}

const usage = { input_tokens: 4200, output_tokens: 90 }
const answered = { isAnswered: true, text: GOOD, usage }
const finish = { answer: 'Draft is ready', durationMs: 1, isAborted: false, turnId: 't', reason: 'end_turn' }
const message = { text: 'Help me reply to Sam', turnId: 't' }

test('parseReply accepts a good reply and rejects anything else', () => {
  expect(parseReply(GOOD, 5)?.status).toBe('needs_you')
  expect(parseReply('```json\n' + GOOD + '\n```', 5)?.updatedAt).toBe(5)
  expect(parseReply('no json here', 5)).toBe(null)
  expect(parseReply('{broken', 5)).toBe(null)
  expect(parseReply(JSON.stringify({ ...JSON.parse(GOOD), status: 'done-ish' }), 5)).toBe(null)
  expect(parseReply(JSON.stringify({ ...JSON.parse(GOOD), next: '  ' }), 5)).toBe(null)
})

test('buildPrompt drops system reminders and keeps the first message', () => {
  const prompt = buildPrompt(
    [
      { role: 'user', text: 'The real goal<system-reminder>SECRET</system-reminder>' },
      ...Array.from({ length: 20 }, (_, i) => ({ role: 'assistant', text: `row ${i}` })),
    ],
    'final',
    null,
  )
  expect(prompt.includes('The real goal')).toBe(true)
  expect(prompt.includes('SECRET')).toBe(false)
  expect(prompt.includes('row 19')).toBe(true)
  expect(prompt.includes('row 2\n')).toBe(false)
})

test('old or broken saved rows are ignored, and ages read naturally', () => {
  expect(toRow({ status: 'needs_you', updatedAt: 7 })).toBe(null)
  expect(toRow('junk')).toBe(null)
  expect(toRow({ sessionId: 's', phase: 'idle', userAt: 1, repliedAt: 2, summary: null })?.repliedAt).toBe(2)
  expect(ageLabel(30000)).toBe('just now')
  expect(ageLabel(3 * 3600000)).toBe('3h ago')
})

// The same cases Chat Board's own tests read, so the band and the board can never disagree.
test('every shared status case gives the same color and line as Chat Board', () => {
  for (const one of cases.cases) {
    const row = { sessionId: 's', localId: null, title: null, repliedAt: 0, summary: null, ...one.row } as any
    const shown = describe(row, cases.now)
    expect([one.name, shown.kind, shown.line]).toEqual([one.name, one.kind, one.line])
  }
})

test('waiting for your OK: only card tools, asked calls, or quick tools stuck a long time', () => {
  const at = 1000000
  expect(waitingOn({ tool: 'AskUserQuestion', at, asked: false }, at + 3500)).toBe('answer a question')
  expect(waitingOn({ tool: 'AskUserQuestion', at, asked: false }, at + 1000)).toBe(null)
  expect(waitingOn({ tool: 'Bash', at, asked: false }, at + 600000)).toBe(null)
  expect(waitingOn({ tool: 'Read', at, asked: false }, at + 25000)).toBe('Read')
  expect(waitingOn(null, at)).toBe(null)
})

test('a finished turn never calls the model by itself', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { calls } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  await clock.advance(60 * 60000)
  await clock.settle()
  expect(calls.length).toBe(0)
})

test('a question in the chat\'s end-of-turn box shows Question for you, for free', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { calls } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.tool.call({ tool: 'mcp__ccd_turn__wrap_up', recap: 'Draft written.', ask: 'Send the draft to Sam?' } as any)
  await $.turn.complete(finish as any)
  await clock.settle()

  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /Question for you/ }))?.text.trim()).toBe('Question for you')
  expect(await ui.find({ type: 'Text', text: /Send the draft to Sam/ })).toBeDefined()
  expect(calls.length).toBe(0)
  await ui.unmount()
})

test('the chat says itself when it is ready to close, until the person writes again', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { tools } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  expect(tools).toEqual(['chat_status'])
  const composed = (await $.prompt.compose(COMPOSE as any)) as any
  expect(composed.sections.some((one: any) => one.id === 'chat-hud:status')).toBe(true)

  await $.turn.start(message as any)
  await clock.advance(1000)
  await $.tool.call({ tool: 'mcp__chat-hud__chat_status', is_done: false, left: 'You still have to send it.', purpose: 'Reply to Sam.' } as any)
  await $.turn.complete(finish as any)
  const notDone = await $.ui.mount(BAND)
  expect(await notDone.find({ type: 'Text', text: /Left: You still have to send it/ })).toBeDefined()
  await notDone.unmount()

  await $.turn.start(message as any)
  await clock.advance(1000)
  await $.tool.call({ tool: 'mcp__chat-hud__chat_status', is_done: true, left: 'Reply sent.', purpose: 'Reply to Sam.' } as any)
  await $.turn.complete(finish as any)
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /Ready to close/ }))?.text.trim()).toBe('Ready to close')
  expect(await ui.find({ type: 'Text', text: /Reply to Sam\./ })).toBeDefined()
  await ui.unmount()

  await clock.advance(1000)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  const after = await $.ui.mount(BAND)
  expect(await after.find({ type: 'Text', text: /Ready to close/ })).toBeUndefined()
  await after.unmount()
})

test('Summarize now skips the wait and records the cost', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { saved, calls } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  const ui = await $.ui.mount(BAND)
  await ui.press({ key: 'now' })
  await clock.settle()

  expect(calls.length).toBe(1)
  expect(await ui.find({ type: 'Text', text: /You approve the draft/ })).toBeDefined()
  expect((saved.get('usage:session-a') as { trigger: string }[])[0]?.trigger).toBe('button')
  await clock.advance(10 * 60000)
  expect(calls.length).toBe(1)
  await ui.unmount()
})

test('a failed call keeps the last summary and says so', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  engine(on, { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded' })

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  const ui = await $.ui.mount(BAND)
  await ui.press({ key: 'now' })
  await clock.settle()

  expect((await ui.find({ type: 'Text', text: /Couldn't summarize/ }))?.text).toBe("Couldn't summarize (api-error)")
  await ui.unmount()
})

test('a subagent turn changes nothing', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { saved, calls } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start({ ...message, agentId: 'sub' } as any)
  await $.turn.complete({ ...finish, agentId: 'sub' } as any)
  await clock.advance(10 * 60000)
  await clock.settle()

  expect(calls.length).toBe(0)
  expect((saved.get('chat:session-a') as { phase: string }).phase).toBe('idle')
})

test('/hud off keeps a chat off the board and off the model', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { saved, calls } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.complete(finish as any)
  expect(saved.has('chat:session-a')).toBe(true)

  await $.command.run({ command: 'hud', args: 'off' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  await clock.advance(10 * 60000)
  await clock.settle()

  expect(calls.length).toBe(0)
  expect(saved.has('chat:session-a')).toBe(false)
})

const CONFIG = '/Users/alex/.claude/chat-hud/config.json'

test('a chat in a private folder from the config is never summarized or listed', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { saved, calls, tools, files } = engine(on, answered, '/Users/alex/journal/notes')
  files.set(CONFIG, { text: JSON.stringify({ privateFolders: ['~/journal'] }), mtimeMs: 1 })

  await $.session.start({ cwd: '/Users/alex/journal/notes' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  await $.command.run({ command: 'hud', args: 'now' } as any)
  await $.command.run({ command: 'hud', args: 'on' } as any)
  expect(tools).toEqual([])
  await clock.advance(10 * 60000)
  await clock.settle()

  expect(calls.length).toBe(0)
  expect([...saved.keys()].some(key => key.startsWith('chat:'))).toBe(false)
  expect(JSON.parse(files.get('/Users/alex/.claude/chat-hud/rows/session-a.json')!.text).isOff).toBe(true)
  const composed = (await $.prompt.compose(COMPOSE as any)) as any
  expect(composed.sections.some((one: any) => one.id === 'chat-hud:status')).toBe(false)
})

test('a folder that only starts with a private folder\'s name is not private', async ($, on) => {
  mock.clock(on, { now: 1000 })
  const { saved, files } = engine(on, answered, '/Users/alex/journal-old')
  files.set(CONFIG, { text: JSON.stringify({ privateFolders: ['~/journal'] }), mtimeMs: 1 })
  await $.session.start({ cwd: '/Users/alex/journal-old' } as any)
  await $.turn.complete(finish as any)
  expect(saved.has('chat:session-a')).toBe(true)
})

test('a config file that is there but broken treats every chat as private', async ($, on) => {
  mock.clock(on, { now: 1000 })
  const { saved, files } = engine(on, answered, '/Users/alex/projects')
  files.set(CONFIG, { text: '{ not json', mtimeMs: 1 })
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.complete(finish as any)
  expect(saved.has('chat:session-a')).toBe(false)
})

test('a tool call is marked pending while it runs and cleared when it returns, so the board can see a waiting card', async ($, on) => {
  mock.clock(on, { now: 1000 })
  const { writes } = engine(on, answered)
  on('tool.call', { tool: 'Read' }, () => ({ result: 'contents' }))
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  const before = writes.length
  await $.tool.call({ tool: 'Read', file_path: '/tmp/x' } as any)
  const pending = writes
    .slice(before)
    .filter(one => one.path.endsWith('/rows/session-a.json'))
    .map(one => JSON.parse(one.text).pending?.tool ?? null)
  expect(pending).toEqual(['Read', null])
})

// Runs a Bash call whose permission check answers "ask", and reports whether the board row was marked asked
// while it ran. `during` runs inside the call, after the check (a dialog's notification, say).
const askedDuringBash = async ($: any, on: any, mode: string, during?: () => Promise<unknown>) => {
  mock.clock(on, { now: 1000 })
  const { files } = engine(on, answered)
  let asked: boolean | null = null
  // Only the check the stand-in runs asks; the harness's own check before the call lets it through.
  on('tool.check', (_: unknown, e: any) => ({ decision: e.tool_use_id === 't1' ? 'ask' : 'allow' }))
  on('classic.UserPromptSubmit', () => ({ value: {} }))
  on('classic.Notification', () => ({ value: {} }))
  on('tool.call', { tool: 'Bash' }, async () => {
    await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 't1', approver: 'person' })
    if (during) await during()
    asked = JSON.parse(files.get('/Users/alex/.claude/chat-hud/rows/session-a.json')!.text).pending?.asked ?? null
    return { result: 'ok' }
  })
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.classic.UserPromptSubmit({ prompt: 'go', permission_mode: mode } as any)
  await $.turn.start(message as any)
  await $.tool.call({ tool: 'Bash', command: 'ls' } as any)
  return asked
}

test('an ask in default mode goes to the person, so the row is marked asked', async ($, on) => {
  expect(await askedDuringBash($, on, 'default')).toBe(true)
})

test('an ask in auto mode is settled by the classifier, so a running command stays working', async ($, on) => {
  expect(await askedDuringBash($, on, 'auto')).toBe(false)
})

test('a permission dialog that actually shows marks the row asked, even in auto mode', async ($, on) => {
  const notify = () => $.classic.Notification({ message: 'Claude needs your permission to use Bash', notification_type: 'permission_prompt', permission_mode: 'auto' } as any)
  expect(await askedDuringBash($, on, 'auto', notify)).toBe(true)
})

test('an idle notification is not a permission dialog', async ($, on) => {
  const notify = () => $.classic.Notification({ message: 'Claude is waiting for your input', notification_type: 'idle_prompt', permission_mode: 'auto' } as any)
  expect(await askedDuringBash($, on, 'auto', notify)).toBe(false)
})

test('a subagent\'s tool calls never mark the chat pending', async ($, on) => {
  mock.clock(on, { now: 1000 })
  const { writes } = engine(on, answered)
  on('tool.call', { tool: 'Read' }, () => ({ result: 'contents' }))
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  const before = writes.length
  await $.tool.call({ tool: 'Read', file_path: '/tmp/x', agentId: 'sub' } as any)
  expect(writes.slice(before).some(one => one.text.includes('"pending":{'))).toBe(false)
})

test('a new turn clears a pending call left behind', async ($, on) => {
  mock.clock(on, { now: 1000 })
  const { saved } = engine(on, answered)
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  saved.set('chat:session-a', null)
  await $.turn.start(message as any)
  await $.tool.call({ tool: 'mcp__ccd_turn__wrap_up', recap: 'x' } as any)
  await $.turn.start(message as any)
  expect((saved.get('chat:session-a') as any).pending).toBe(null)
})

test('Summarize now shows that it is working until the summary lands', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  let release = () => {}
  const gate = new Promise<void>(resolve => (release = resolve))
  engine(on, async () => {
    await gate
    return answered
  })

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.turn.complete(finish as any)
  const ui = await $.ui.mount(BAND)
  const pressing = ui.press({ key: 'now' })
  for (let i = 0; i < 50; i++) await Promise.resolve()
  expect((await ui.find({ type: 'Text', text: /Summarizing/ }))?.text).toBe('Summarizing...')
  expect(await ui.find({ type: 'Button', key: 'now' })).toBeUndefined()

  release()
  await pressing
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /Summarizing/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /You approve the draft/ })).toBeDefined()
  await ui.unmount()
})

test('an archive request from the Chat Board window is carried out once and answered', async ($, on) => {
  const clock = mock.clock(on, { now: 1793900000000 })
  const { files } = engine(on, answered)
  const archived: string[] = []
  on('mcp.call', (_: unknown, e: any) => {
    archived.push(JSON.stringify(e))
    return { value: { content: [{ type: 'text', text: 'Archived.' }] } }
  })
  files.set('/Users/alex/.claude/chat-hud/requests/archive-local_old.json', {
    text: JSON.stringify({ type: 'archive', localId: 'local_old', title: 'Old chat', token: 'tok-1234567890abcdef', at: 1793900000000 }),
    mtimeMs: 1,
  })

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await clock.advance(6000)
  await clock.settle()
  await clock.advance(6000)
  await clock.settle()

  expect(archived.length).toBe(1)
  expect(archived[0]).toContain('local_old')
  expect(archived[0]).toContain('(tok-1234567890abcdef)')
  expect(JSON.parse(files.get('/Users/alex/.claude/chat-hud/requests/archive-local_old.result.json')!.text).text).toBe('Archived.')
})

test('each chat writes its status to the shared file the Chat Board window reads', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const { files } = engine(on, answered)

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.tool.call({ tool: 'mcp__chat-hud__chat_status', is_done: true, left: 'Reply sent.', purpose: 'Reply to Sam.' } as any)
  await $.turn.complete(finish as any)
  await clock.settle()

  const shared = JSON.parse(files.get('/Users/alex/.claude/chat-hud/rows/session-a.json')!.text)
  expect(shared.verdict.isDone).toBe(true)
  expect(shared.localId).toBe('local_abc')
})

test('a chat that starts up keeps the status already in its shared file', async ($, on) => {
  const clock = mock.clock(on, { now: 5000 })
  const { files, saved } = engine(on, answered)
  saved.set('chat:session-a', { sessionId: 'session-a', localId: 'local_abc', title: 'x', phase: 'idle', userAt: 10, repliedAt: 15, summary: null })
  files.set('/Users/alex/.claude/chat-hud/rows/session-a.json', {
    text: JSON.stringify({ sessionId: 'session-a', localId: 'local_abc', title: 'x', phase: 'idle', userAt: 10, repliedAt: 20, summary: null, turnEnd: { ask: 'Send it?', recap: null, at: 20 } }),
    mtimeMs: 1,
  })

  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await clock.settle()
  const ui = await $.ui.mount(BAND)
  expect(await ui.find({ type: 'Text', text: /Send it\?/ })).toBeDefined()
  await ui.unmount()
})

test('the archive guard refuses any archive without a waiting Chat Board code, and lets the real one through', async ($, on) => {
  const clock = mock.clock(on, { now: 1793900000000 })
  const { files } = engine(on, answered)
  const done: string[] = []
  on('tool.call', { tool: 'mcp__ccd_session_mgmt__archive_session' }, (_: unknown, e: any) => {
    done.push(e.session_id)
    return { result: 'Archived.' }
  })
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  const archive = (session_id: string, reason?: string) =>
    $.tool.call({ tool: 'mcp__ccd_session_mgmt__archive_session', session_id, ...(reason ? { reason } : {}) } as any)

  // No request waiting: the model asking on its own is refused.
  expect((await archive('local_old', 'the user asked'))?.deny).toContain('Chat Board')

  files.set('/Users/alex/.claude/chat-hud/requests/archive-local_old.json', {
    text: JSON.stringify({ type: 'archive', localId: 'local_old', token: 'tok-1234567890abcdef', at: 1793900000000 }),
    mtimeMs: 1,
  })
  // A waiting request, but the wrong code, or the code aimed at another chat: refused.
  expect((await archive('local_old', 'Archived (tok-guess)'))?.deny).toContain('Chat Board')
  expect((await archive('local_abc', 'Archived from Chat Board (tok-1234567890abcdef)'))?.deny).toContain('Chat Board')
  // The real one goes through.
  expect((await archive('local_old', 'Archived from Chat Board (tok-1234567890abcdef)'))?.deny).toBeUndefined()
  // An old code has expired.
  await clock.advance(61000)
  expect((await archive('local_old', 'Archived from Chat Board (tok-1234567890abcdef)'))?.deny).toContain('Chat Board')
  expect(done).toEqual(['local_old'])
})

test('a question written at the end of a reply counts as a question, and a plain reply does not', async ($, on) => {
  expect(questionIn('Here is the plan.\n\nWant me to send it to Sam today?')).toBe('Want me to send it to Sam today?')
  expect(questionIn('Why did it fail? Because of X.\n\nIt is fixed now.')).toBe(null)
  expect(questionIn('Done. **Should I push it?**')).toBe('Should I push it?')

  const clock = mock.clock(on, { now: 1000 })
  engine(on, answered)
  await $.session.start({ cwd: '/Users/alex/projects' } as any)
  await $.turn.start(message as any)
  await $.turn.complete({ ...finish, answer: 'Draft is ready.\n\nShould I send it now?' } as any)
  await clock.settle()
  const ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /Question for you/ }))?.text.trim()).toBe('Question for you')
  expect(await ui.find({ type: 'Text', text: /Should I send it now\?/ })).toBeDefined()
  await ui.unmount()

  await clock.advance(1000)
  await $.turn.start(message as any)
  await $.turn.complete({ ...finish, answer: 'Sent.' } as any)
  const after = await $.ui.mount(BAND)
  expect(await after.find({ type: 'Text', text: /Question for you/ })).toBeUndefined()
  await after.unmount()
})

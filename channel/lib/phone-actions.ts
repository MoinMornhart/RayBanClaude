/**
 * Aktionen, die Claude auf dem iPhone auslösen kann (Tool `phone_action`):
 * Timer, Wecker, Timer löschen, Anruf, Nachricht, Navigation, Erinnerung,
 * Foto in der Mediathek sichern, Standort (auch „merk dir, wo ich geparkt habe“).
 *
 * Jede Aktion wird hier per Whitelist geprüft. Anrufe, Nachrichten und Navigation
 * bestätigt der Nutzer immer auf dem iPhone – Claude kann nichts heimlich auslösen.
 */

import { CLOCK_TIME, ISO_DATE, PHONE } from './patterns.ts'
import { cleanText } from './validate.ts'

export const PHONE_ACTIONS = [
  'timer', 'alarm', 'cancel_timer', 'call', 'message', 'navigate', 'reminder', 'save_photo', 'location',
] as const
export type PhoneActionName = (typeof PHONE_ACTIONS)[number]

const MAX_TIMER_SECONDS = 86_400 // 24 Stunden
const MAX_LABEL_CHARS = 60
const MAX_CONTACT_CHARS = 80
const MAX_MESSAGE_CHARS = 1000
const MAX_DESTINATION_CHARS = 200
const MAX_REMINDER_CHARS = 200

/** Bereinigte Nutzdaten, die an die App gehen (nur bekannte Felder). */
export interface PhoneActionPayload {
  readonly action: PhoneActionName
  readonly duration_seconds?: number
  readonly time?: string
  readonly date?: string
  readonly label?: string
  readonly contact?: string
  readonly number?: string
  readonly text?: string
  readonly destination?: string
}

/** Fehler mit einer Meldung, die Claude direkt verstehen und dem Nutzer weitergeben kann. */
export class PhoneActionError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'PhoneActionError'
  }
}

type Args = Readonly<Record<string, unknown>>

function optionalText(raw: unknown, max: number): string | undefined {
  return cleanText(raw, max) || undefined
}

function requireContactOrNumber(args: Args): Pick<PhoneActionPayload, 'contact' | 'number'> {
  const contact = optionalText(args.contact, MAX_CONTACT_CHARS)
  const rawNumber = typeof args.number === 'string' ? args.number.trim() : ''
  if (rawNumber && !PHONE.test(rawNumber)) throw new PhoneActionError('number ist keine gültige Telefonnummer')
  const number = rawNumber || undefined
  if (!contact && !number) throw new PhoneActionError('contact (Name wie vom Nutzer gesagt) oder number ist erforderlich')
  return { contact, number }
}

const BUILDERS: Readonly<Record<PhoneActionName, (args: Args) => PhoneActionPayload>> = {
  timer: args => {
    const seconds = Number(args.duration_seconds)
    if (!Number.isInteger(seconds) || seconds < 1 || seconds > MAX_TIMER_SECONDS) {
      throw new PhoneActionError(`duration_seconds muss eine ganze Zahl zwischen 1 und ${MAX_TIMER_SECONDS} sein`)
    }
    return { action: 'timer', duration_seconds: seconds, label: optionalText(args.label, MAX_LABEL_CHARS) }
  },
  alarm: args => {
    const time = typeof args.time === 'string' ? args.time.trim() : ''
    if (!CLOCK_TIME.test(time)) throw new PhoneActionError('time muss im Format HH:MM (24 h) angegeben werden')
    return { action: 'alarm', time, label: optionalText(args.label, MAX_LABEL_CHARS) }
  },
  cancel_timer: args => ({ action: 'cancel_timer', label: optionalText(args.label, MAX_LABEL_CHARS) }),
  call: args => ({ action: 'call', ...requireContactOrNumber(args) }),
  message: args => {
    const text = optionalText(args.text, MAX_MESSAGE_CHARS)
    if (!text) throw new PhoneActionError('text ist erforderlich')
    return { action: 'message', ...requireContactOrNumber(args), text }
  },
  navigate: args => {
    const destination = optionalText(args.destination, MAX_DESTINATION_CHARS)
    if (!destination) throw new PhoneActionError('destination ist erforderlich')
    return { action: 'navigate', destination }
  },
  reminder: args => {
    const text = optionalText(args.text, MAX_REMINDER_CHARS)
    if (!text) throw new PhoneActionError('text (woran erinnert werden soll) ist erforderlich')
    const time = typeof args.time === 'string' ? args.time.trim() : ''
    const date = typeof args.date === 'string' ? args.date.trim() : ''
    if (time && !CLOCK_TIME.test(time)) throw new PhoneActionError('time muss im Format HH:MM (24 h) angegeben werden')
    if (date && !ISO_DATE.test(date)) throw new PhoneActionError('date muss im Format JJJJ-MM-TT angegeben werden')
    return { action: 'reminder', text, time: time || undefined, date: date || undefined }
  },
  save_photo: () => ({ action: 'save_photo' }),
  location: args => ({ action: 'location', label: optionalText(args.label, MAX_LABEL_CHARS) }),
}

function isPhoneAction(raw: unknown): raw is PhoneActionName {
  return PHONE_ACTIONS.some(a => a === raw)
}

/** Prüft die Tool-Argumente und liefert die bereinigten Nutzdaten für die App. */
export function buildPhoneAction(args: Args): PhoneActionPayload {
  if (!isPhoneAction(args.action)) throw new PhoneActionError(`action muss eine von ${PHONE_ACTIONS.join(', ')} sein`)
  return BUILDERS[args.action](args)
}

export const PHONE_ACTION_TOOL = {
  name: 'phone_action',
  description: [
    "Do something on the user's iPhone: set a timer or alarm, cancel timers, start a phone call,",
    'prepare a text message, start navigation, add a reminder (iOS Reminders app), save the last photo',
    'to the photo library (save_photo – when the user says "mach ein Foto" / "speicher das Foto"),',
    'or get the current location (location – "wo bin ich?"; with label it is also remembered, e.g.',
    'label "Auto geparkt" for "merk dir, wo ich geparkt habe"; navigate back later with the stored address).',
    'For call/message pass the contact name exactly as the user said it (e.g. "Mama") – the phone looks',
    'it up locally, contacts never leave the phone. Calls, messages and navigation are always confirmed',
    'by the user on the phone. The result tells you whether it worked.',
  ].join(' '),
  inputSchema: {
    type: 'object',
    properties: {
      action: { type: 'string', enum: [...PHONE_ACTIONS] },
      duration_seconds: { type: 'integer', description: 'timer: duration in seconds (1–86400)' },
      time: { type: 'string', description: 'alarm/reminder: local time HH:MM (24 h); alarm = next occurrence' },
      date: { type: 'string', description: 'reminder: day as YYYY-MM-DD (omit for today/next occurrence of time)' },
      label: { type: 'string', description: 'timer/alarm: short name, e.g. "Nudeln"; cancel_timer: which one (empty = all); location: name to remember the place by' },
      contact: { type: 'string', description: 'call/message: contact name as spoken by the user' },
      number: { type: 'string', description: 'call/message: phone number, only if the user said one' },
      text: { type: 'string', description: 'message: the message text; reminder: what to remind of' },
      destination: { type: 'string', description: 'navigate: address or place' },
    },
    required: ['action'],
  },
} as const

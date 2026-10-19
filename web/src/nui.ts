import { mockNui } from './mocks'

export const inGame = typeof window.GetParentResourceName === 'function'
const resource = inGame ? window.GetParentResourceName!() : 'dwkambience'

/** Llama a un RegisterNUICallback del cliente; fuera del juego responde el mock. */
export async function fetchNui<T = unknown>(event: string, data: unknown = {}): Promise<T> {
  if (!inGame) return mockNui<T>(event, data)

  const response = await fetch(`https://${resource}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  })
  return (await response.json()) as T
}

export interface NuiMessage<T = unknown> {
  action: string
  data: T
}

export function onNuiMessage(handler: (msg: NuiMessage) => void) {
  const listener = (event: MessageEvent) => {
    if (event.data && typeof event.data.action === 'string') handler(event.data as NuiMessage)
  }
  window.addEventListener('message', listener)
  return () => window.removeEventListener('message', listener)
}

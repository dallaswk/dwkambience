import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface ConfirmRequest {
  title: string
  body: string
  confirm: string
  danger?: boolean
  /** Si existe, el diálogo pide un texto (askText) */
  placeholder?: string
}

/** Diálogo de confirmación con promesa: `if (await confirm.ask({...})) ...` */
export const useConfirm = defineStore('confirm', () => {
  const request = ref<ConfirmRequest | null>(null)
  const text = ref('')
  let resolver: ((ok: boolean) => void) | null = null

  function ask(req: ConfirmRequest) {
    resolver?.(false)
    request.value = req
    return new Promise<boolean>((resolve) => (resolver = resolve))
  }

  /** Pide un texto; devuelve null si se cancela o queda vacío */
  async function askText(req: ConfirmRequest & { placeholder: string }) {
    text.value = ''
    const ok = await ask(req)
    const value = text.value.trim()
    return ok && value ? value : null
  }

  function answer(ok: boolean) {
    resolver?.(ok)
    resolver = null
    request.value = null
  }

  return { request, text, ask, askText, answer }
})

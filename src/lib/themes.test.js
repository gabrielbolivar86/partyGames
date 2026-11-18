import { describe, it, expect, beforeEach } from 'vitest'
import { THEMES, THEME_IDS, getTheme, applyTheme, readSavedTheme, contrast } from './themes'

describe('temas', () => {
  it('tiene los 8 ids del spec en orden', () => {
    expect(THEME_IDS).toEqual(['fiesta', 'halloween', 'navidad', 'baby-nino', 'baby-nina', 'revelacion', 'verde', 'azul'])
  })

  it('texto de botón legible (texto grande ≥ 3:1)', () => {
    for (const t of THEMES) {
      expect(contrast(t.colors.onPrimary, t.colors.primary), t.id).toBeGreaterThanOrEqual(2.95)
      expect(contrast(t.colors.onSecondary, t.colors.secondary), t.id).toBeGreaterThanOrEqual(2.95)
    }
  })

  it('texto sobre el fondo y texto suave legibles (≥ 4.5:1)', () => {
    for (const t of THEMES) {
      expect(contrast(t.colors.textOnPage, t.colors.page), t.id).toBeGreaterThanOrEqual(4.5)
      expect(contrast(t.colors.muted, t.colors.page), t.id).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('tinta legible sobre la tarjeta de pregunta y la superficie', () => {
    for (const t of THEMES) {
      expect(contrast('#18181B', t.colors.question), t.id).toBeGreaterThanOrEqual(4.5)
      expect(contrast('#18181B', t.colors.surface), t.id).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('ids desconocidos caen en fiesta', () => {
    expect(getTheme('xyz').id).toBe('fiesta')
    expect(getTheme().id).toBe('fiesta')
  })

  describe('applyTheme', () => {
    beforeEach(() => {
      localStorage.clear()
      document.head.innerHTML = '<meta name="theme-color" content="#000">'
    })

    it('pone data-theme, theme-color y lo recuerda', () => {
      applyTheme('navidad')
      expect(document.documentElement.dataset.theme).toBe('navidad')
      expect(document.querySelector('meta[name=theme-color]').content).toBe('#FFF4E4')
      expect(readSavedTheme()).toBe('navidad')
    })

    it('sin tema o con tema desconocido usa fiesta', () => {
      applyTheme(undefined)
      expect(document.documentElement.dataset.theme).toBe('fiesta')
      applyTheme('xyz')
      expect(document.documentElement.dataset.theme).toBe('fiesta')
    })

    it('no se rompe si localStorage lanza', () => {
      const orig = Storage.prototype.setItem
      Storage.prototype.setItem = () => { throw new Error('bloqueado') }
      try {
        expect(() => applyTheme('azul')).not.toThrow()
      } finally {
        Storage.prototype.setItem = orig
      }
    })
  })
})

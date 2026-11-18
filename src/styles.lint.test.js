import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

// Guardianes del rediseño: todo color sale de los temas, nada de degradados ni blur.
const SRC = path.resolve(__dirname)
const css = fs.readFileSync(path.join(SRC, 'styles.css'), 'utf8')

function jsxFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) return jsxFiles(p)
    return e.name.endsWith('.jsx') ? [p] : []
  })
}

describe('estilos', () => {
  it('styles.css: hex solo dentro de :root o [data-theme]', () => {
    const outside = css
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(:root|\[data-theme="[a-z-]+"\])\s*\{[^}]*\}/g, '')
    expect(outside.match(/#[0-9a-fA-F]{3,8}\b/g) || []).toEqual([])
  })

  it('styles.css: sin degradados ni blur', () => {
    expect(css.match(/gradient\(|blur\(/g) || []).toEqual([])
  })

  it('jsx: todo ícono usado está en el registro de Icon.jsx', () => {
    const iconFile = fs.readFileSync(path.join(SRC, 'components', 'Icon.jsx'), 'utf8')
    const registry = new Set(iconFile.match(/const ICONS = \{([\s\S]*?)\}/)[1].match(/Icon\w+/g))
    const used = [...jsxFiles(SRC), path.join(SRC, 'lib', 'themes.js')].flatMap((f) =>
      [...fs.readFileSync(f, 'utf8').matchAll(/['"](Icon[A-Z]\w+)['"]/g)].map((m) => `${path.relative(SRC, f)} ${m[1]}`))
    expect(used.filter((u) => !registry.has(u.split(' ')[1]))).toEqual([])
  })

  it('jsx: sin colores hex salvo los del QR', () => {
    const bad = jsxFiles(SRC).flatMap((f) =>
      (fs.readFileSync(f, 'utf8').match(/#[0-9a-fA-F]{6}\b/g) || [])
        .filter((h) => !['#ffffff', '#18181b'].includes(h.toLowerCase()))
        .map((h) => `${path.relative(SRC, f)} ${h}`))
    expect(bad).toEqual([])
  })
})

// Hallazgos de la revisión final (legibilidad)
import { THEMES, contrast } from './lib/themes'

function mix(a, b, pa) { // a al pa% + b, como color-mix(in srgb, a pa%, b)
  const h = (x) => [1, 3, 5].map((i) => parseInt(x.slice(i, i + 2), 16))
  const [A, B] = [h(a), h(b)]
  return '#' + A.map((v, i) => Math.round(v * pa + B[i] * (1 - pa)).toString(16).padStart(2, '0')).join('')
}

describe('legibilidad', () => {
  it('surface-2 es clara en todos los temas: el texto suave se lee encima', () => {
    const m = css.match(/--surface-2:\s*color-mix\(in srgb, var\(--surface\) (\d+)%, var\(--page\)\)/)
    expect(m, 'surface-2 debe mezclar sobre todo la superficie').not.toBeNull()
    for (const t of THEMES) {
      const s2 = mix(t.colors.surface, t.colors.page, Number(m[1]) / 100)
      expect(contrast('#52525B', s2), t.id).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('carta secreta cerrada sobre superficie clara y texto suave en tinta al abrirla', () => {
    expect(css).toMatch(/\.secret-card \{[^}]*background: var\(--surface\)/)
    expect(css).toMatch(/\.secret-card\.open \.muted \{[^}]*color: var\(--ink\)/)
  })

  it('hay respaldo para navegadores sin color-mix (TVs viejas)', () => {
    const block = css.match(/@supports not \(color: color-mix\(in srgb, red, blue\)\) \{([\s\S]*?)\n\}/)
    expect(block, 'falta el bloque @supports').not.toBeNull()
    for (const v of ['--line', '--surface-2', '--tint-ok', '--tint-danger', '--tint-warn', '--tint-primary', '--tint-secondary']) {
      expect(block[1], v).toContain(v + ':')
    }
  })
})

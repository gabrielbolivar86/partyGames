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

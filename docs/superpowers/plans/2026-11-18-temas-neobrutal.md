# Temas por fiesta + rediseño "cartas y stickers": plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cada fiesta elige uno de 8 temas, y toda la app (celular, TV y panel) pasa al estilo neo-brutalista suave del diseño aprobado.

**Architecture:**
- El tema vive en `events.theme`. Llega al cliente por `party_json()`, que ya va dentro de `get_dashboard()`.
- `ThemeSync`, dentro de `PartyScope`, aplica `data-theme` en `<html>`.
- Todo el color sale de variables CSS definidas por tema en `src/styles.css`. Unas pruebas impiden que vuelvan a aparecer colores fijos.
- Las pantallas se reestilizan por etapas sobre componentes CSS base. No se cambia la lógica de ningún juego.

**Tech Stack:** React 18 + Vite, Supabase (Postgres RPC + realtime), `@tabler/icons-react` (nuevo), Vitest + jsdom (nuevo, solo para pruebas).

**Spec:** `docs/superpowers/specs/2026-11-18-temas-neobrutal-design.md`

## Global Constraints

- Tinta `#18181B`. Bordes `2px solid var(--ink)`. Sombra dura `4px 4px 0 var(--ink)` (3px en elementos chicos). Esquinas de 12 a 16px.
- Prohibido: degradados, neón, glassmorphism, `blur()`, sombras con difuminado.
- Letras: títulos, cronómetros y puntos en Bricolage Grotesque 800; texto en Nunito 600/800. Creepster solo en `[data-theme="halloween"]` y en los números gigantes de la TV.
- Íconos: `@tabler/icons-react` con `stroke={2.25}`. Los emojis de decoración de interfaz se reemplazan; los que son contenido del juego (roles del lobo, emoji de cada juego en el catálogo, regalos) se quedan.
- Celular: acciones principales de al menos 56px de alto, nada tocable de menos de 44px, 12px de separación, sin scroll horizontal a 375px.
- TV: pregunta ≥ 34px, respuestas ≥ 20px, ningún texto < 18px.
- Texto sobre `--primary` / `--secondary`: negrita ≥ 18px, con el color `--on-primary` / `--on-secondary` de la tabla del spec. Texto más chico va en tinta.
- Ningún color hex en `src/**/*.jsx` salvo `#ffffff` y `#18181B` (QR). Ningún hex en `src/styles.css` fuera de los bloques `:root` / `[data-theme=…]`.
- Textos de interfaz en español y con el tono actual de la app.
- Commit por tarea. Al terminar cada etapa se le pregunta a Gabriel antes de hacer `git push origin main`: el push publica en vivo (Vercel).
- Los commits terminan con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Halloween, el único tema oscuro:** texto directo sobre el fondo, inputs, placeholders, pestañas inactivas y textos `muted` deben leerse. Prueba: `themes.test.js` verifica el contraste de `textOnPage`/`muted` contra `page` (≥ 4.5).
2. **Una fiesta antigua o sin tema** (`theme` nulo o un id desconocido que llega del servidor) debe verse con `fiesta` y no romperse. Prueba: `applyTheme(undefined)` y `applyTheme('xyz')` dejan `data-theme="fiesta"`.
3. **Cambio de tema con la TV y celulares abiertos:** cambian sin recargar. Verificación manual en la Tarea 4.
4. **Parpadeo al abrir:** antes de que llegue `get_dashboard`, se usa el último tema guardado, y si el storage está bloqueado no se rompe. Prueba: `applyTheme` con `localStorage` que lanza error no lanza.
5. **Llamada vieja de `owner_create_party` con 3 argumentos:** debe seguir funcionando y no quedar ambigua. Verificación SQL en la Tarea 2.

---

## Archivos

| Archivo | Responsabilidad |
|---|---|
| `src/lib/themes.js` (nuevo) | Lista de temas, `getTheme`, `applyTheme`, `readSavedTheme`, `contrast` |
| `src/lib/themes.test.js` (nuevo) | Ids, contraste y comportamiento de `applyTheme` |
| `src/styles.lint.test.js` (nuevo) | Prohíbe hex fuera de los bloques de tema y en JSX; prohíbe degradados y blur |
| `src/components/ThemeSync.jsx` (nuevo) | Usa `useDashboard()` y aplica el tema de la fiesta |
| `src/components/ThemePicker.jsx` (nuevo) | Grilla de mini-cartas para elegir tema |
| `src/components/Icon.jsx` (nuevo) | Exporta los íconos Tabler usados, con `stroke={2.25}` por defecto, y `ThemeIcon` (ícono del tema actual) |
| `src/components/Spinner.jsx` (nuevo) | Spinner con el ícono del tema |
| `supabase/13_fase11_temas.sql` (nuevo) | Columna, grants, `party_json`, `admin_set_theme`, `owner_create_party` con tema, `owner_list_parties` con tema |
| `src/styles.css` | Se reescribe: tokens por tema + componentes base + estilos por pantalla |
| `index.html`, `package.json`, `vite.config.js` | Fuentes, título y favicon; dependencias; config de Vitest |
| Pantallas en `src/pages/**` y `src/components/**` | Reestilizado por etapas (Tareas 5 a 9) |

---

## Etapa 1: base y temas

### Task 1: Catálogo de temas y pruebas

**Files:**
- Create: `src/lib/themes.js`, `src/lib/themes.test.js`, `src/styles.lint.test.js`
- Modify: `package.json` (devDependencies `vitest`, `jsdom`; script `"test": "vitest run"`), `vite.config.js` (`test: { environment: 'jsdom' }`)

**Interfaces:**
- Produces:
  - `THEMES: Array<{ id, name, icon, colors: { page, surface, primary, secondary, question, onPrimary, onSecondary, textOnPage, muted, ink } }>`. Orden: `fiesta, halloween, navidad, baby-nino, baby-nina, revelacion, verde, azul`.
  - `THEME_IDS: string[]`, `DEFAULT_THEME = 'fiesta'`.
  - `getTheme(id?: string) => Theme`: si el id no existe, devuelve `fiesta`.
  - `applyTheme(id?: string) => void`:
    - pone `document.documentElement.dataset.theme` (con fallback a `fiesta`);
    - actualiza `meta[name=theme-color]` con `colors.page`;
    - guarda en localStorage `pg-theme` dentro de try/catch.
  - `readSavedTheme() => string`: lo guardado, o `fiesta`.
  - `contrast(hexA, hexB) => number`: razón WCAG.
- `icon` es el **nombre de exportación** de Tabler: `IconConfetti`, `IconPumpkinScary`, `IconChristmasTree`, `IconBabyCarriage`, `IconHelpHexagon`, `IconLeaf`, `IconDroplet`.
- Colores: los de la tabla del spec.
  - `ink` es `#18181B`, salvo Halloween: `#0D0A14`.
  - `textOnPage` es `#18181B`, salvo Halloween: `#F4F1FF`.
  - `muted` es `#52525B` en los temas claros y `#C9C0E0` en Halloween.
  - `onPrimary` y `onSecondary` siguen la tabla de contraste del spec, con blanco = `#FFFFFF`.

- [ ] **Step 1: Escribir las pruebas que fallan (`src/lib/themes.test.js`)**

```js
import { describe, it, expect, beforeEach } from 'vitest'
import { THEMES, THEME_IDS, getTheme, applyTheme, readSavedTheme, contrast } from './themes'

describe('temas', () => {
  it('tiene los 8 ids del spec en orden', () => {
    expect(THEME_IDS).toEqual(['fiesta','halloween','navidad','baby-nino','baby-nina','revelacion','verde','azul'])
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
    beforeEach(() => { localStorage.clear(); document.head.innerHTML = '<meta name="theme-color" content="#000">' })
    it('pone data-theme, theme-color y lo recuerda', () => {
      applyTheme('navidad')
      expect(document.documentElement.dataset.theme).toBe('navidad')
      expect(document.querySelector('meta[name=theme-color]').content).toBe('#FFF4E4')
      expect(readSavedTheme()).toBe('navidad')
    })
    it('sin tema o con tema desconocido usa fiesta', () => {
      applyTheme(undefined); expect(document.documentElement.dataset.theme).toBe('fiesta')
      applyTheme('xyz'); expect(document.documentElement.dataset.theme).toBe('fiesta')
    })
    it('no se rompe si localStorage lanza', () => {
      const orig = Storage.prototype.setItem
      Storage.prototype.setItem = () => { throw new Error('bloqueado') }
      expect(() => applyTheme('azul')).not.toThrow()
      Storage.prototype.setItem = orig
    })
  })
})
```

- [ ] **Step 2: Escribir la prueba de estilo (`src/styles.lint.test.js`)**

Usa `fs` + `path` (Node) para leer:
- `src/styles.css`;
- todos los `src/**/*.jsx` (recorrido recursivo con `fs.readdirSync`).

Aserciones:
- `'styles.css: hex solo dentro de :root o [data-theme]'`:
  - quitar los bloques que coinciden con `/(:root|\[data-theme="[a-z-]+"\])\s*\{[^}]*\}/g`;
  - en lo que queda, `/#[0-9a-fA-F]{3,8}\b/` no aparece.
- `'styles.css: sin degradados ni blur'`: no aparecen `/gradient\(|blur\(/`.
- `'jsx: sin colores hex salvo los del QR'`: cada match de `/#[0-9a-fA-F]{6}\b/g` en JSX, en minúsculas, debe estar en `['#ffffff', '#18181b']`.

- [ ] **Step 3: Instalar y correr; verificar que fallan**

Run: `npm i -D vitest jsdom && npm test`
Expected:
- `themes.test.js` falla con "Failed to resolve import './themes'".
- `styles.lint.test.js` falla en las tres pruebas, porque hoy hay hex sueltos, `radial-gradient` y `#0d0a14` en el QR.

- [ ] **Step 4: Implementar `src/lib/themes.js` con las interfaces de arriba**

`contrast` usa la luminancia relativa WCAG:
- canal lineal = `c<=0.03928 ? c/12.92 : ((c+0.055)/1.055)^2.4`;
- `L = 0.2126R + 0.7152G + 0.0722B`;
- razón = `(Lmax+0.05)/(Lmin+0.05)`.

Si algún `muted` o `textOnPage` no llega a 4.5, oscurece `muted` (o aclara en Halloween) hasta pasar. Anota el valor final en el spec, en la sección "Reglas de texto".

- [ ] **Step 5: Correr `npm test`**

Expected:
- `themes.test.js` pasa completo.
- `styles.lint.test.js` sigue fallando. Lo arregla la Tarea 3; no lo saltes.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json vite.config.js src/lib/themes.js src/lib/themes.test.js src/styles.lint.test.js
git commit -m "Fase 11: catálogo de temas y pruebas de contraste y estilo"
```

### Task 2: Tema en la base de datos

**Files:**
- Create: `supabase/13_fase11_temas.sql`

**Interfaces:**
- Produces:
  - `party_json()` ahora incluye `'theme', theme`.
  - `admin_set_theme(p_theme text) returns void`.
  - `owner_create_party(p_name text, p_slug text, p_password text, p_theme text default 'fiesta') returns json`.
  - `owner_list_parties()` devuelve una columna extra `theme text`, al final.
- Errores (copy exacto): `'Tema desconocido'`; admin: `'Solo el admin puede hacer esto'`.

- [ ] **Step 1: Escribir el script**

Debe poder correrse de nuevo sin romper nada:
- `alter table events add column if not exists theme text not null default 'fiesta'`.
- Constraint `events_theme_check` con la lista de `THEME_IDS`: drop if exists y luego add.
- `update events set theme='halloween' where slug='halloween-2026'`.
- Re-grant de columnas, con `theme` agregado: `grant select (id, slug, name, active, created_at, enabled_games, theme) on public.events to anon, authenticated`.
- `party_json()` con `theme`.
- `admin_set_theme`: mismo patrón que `admin_set_games` en `11_fase10_multifiesta.sql:283-296`. Valida contra la lista, actualiza `events.theme` y toca `dashboard_state.updated_at`.
- `owner_create_party`:
  - primero `drop function if exists public.owner_create_party(text, text, text)`;
  - después crear la versión de 4 parámetros con el cuerpo de `11_fase10_multifiesta.sql:369-390`, más la validación del tema y `theme` en el insert.
- `owner_list_parties`: `drop function if exists public.owner_list_parties()` y recrear con `theme` al final.
- Grants de execute para `authenticated, anon`, iguales a los del script 11 para las funciones nuevas o recreadas.

- [ ] **Step 2: Probar en una transacción revertida (MCP `execute_sql`, proyecto `kkbcfomfgjjwnuxagozn`)**

Run: `begin;` + el contenido del script + `select party_json() is not null, (select theme from events where slug='halloween-2026');` + `rollback;`

Expected: sin errores; el tema es `halloween`.

- [ ] **Step 3: Aplicar con `apply_migration` (nombre `fase11_temas`) y verificar**

Run (`execute_sql`):
- `select slug, theme from events;`
- `select pg_get_function_identity_arguments(oid) from pg_proc where proname='owner_create_party';`

Expected:
- `halloween-2026 | halloween`, y el resto en `fiesta`.
- Una sola firma: `p_name text, p_slug text, p_password text, p_theme text`.
- Una llamada a `owner_create_party` con solo 3 argumentos con nombre sigue resolviendo, gracias al default.

- [ ] **Step 4: Commit**

```bash
git add supabase/13_fase11_temas.sql
git commit -m "Fase 11: tema por fiesta en la base de datos"
```

### Task 3: Tokens CSS, componentes base, fuentes e íconos

**Files:**
- Modify: `src/styles.css` (se reescribe), `index.html`, `src/App.jsx`, `src/main.jsx`, `package.json`
- Create: `src/components/ThemeSync.jsx`, `src/components/Icon.jsx`, `src/components/Spinner.jsx`
- Modify: los 3 `QRCodeSVG` (`src/pages/admin/Party.jsx:16`, `src/pages/Dashboard.jsx:94,99`): `fgColor="#18181B"`

**Interfaces:**
- Consumes: `applyTheme`, `readSavedTheme`, `getTheme` (Tarea 1); `party.theme` dentro de `useDashboard().data` (Tarea 2).
- Produces:
  - Variables CSS:
    - por tema: `--page --surface --ink --text --text-on-page --muted --primary --on-primary --secondary --on-secondary --question --ok --danger --font-display --font-body --radius --shadow --shadow-sm`. `--ok: #34D399` y `--danger: #EF4444` son iguales en todos los temas.
    - `--font-giant`: Bricolage Grotesque, salvo en `[data-theme="halloween"]`, donde es Creepster.
  - Clases base que usan las etapas 2 a 4:

    | Clase | Uso |
    |---|---|
    | `.btn` + `.primary` / `.secondary` / `.ok` / `.danger` / `.ghost-btn` | Botón: `.small` mide 44px y el normal 56px; al presionar, `translate(2px,2px)` + `--shadow-sm` |
    | `.card` | Superficie con borde y sombra |
    | `.question-card` | Color `--question`, `rotate(-1deg)` |
    | `.pill` | Etiqueta |
    | `.answer` / `.answer.selected` | Botón de respuesta a todo el ancho; seleccionado en `--primary` con ✓ |
    | `.tabs` | Pestañas |
    | `.topbar` | Barra superior |
    | `.display` | Fuente de títulos |
    | `.giant` | Números gigantes de la TV |
    | `.muted` | Texto suave |
    | `.error` / `.success` | Mensajes de estado |

  - `<ThemeSync />`: no renderiza nada. Aplica el tema con `applyTheme(data?.party?.theme)` y pone `document.title = data?.party?.name || 'Juegos de fiesta'`.
  - `Icon.jsx` exporta, de `@tabler/icons-react`, los íconos que se vayan necesitando, con un wrapper de `stroke` 2.25, más `ThemeIcon({ size })`, que renderiza el ícono del tema de `<html data-theme>`.
  - `<Spinner />` usa `ThemeIcon` girando.

- [ ] **Step 1: Instalar `@tabler/icons-react`** con `npm i @tabler/icons-react`.

- [ ] **Step 2: Reescribir `src/styles.css`**
  - Un bloque `[data-theme="…"]` por tema, con los colores de `THEMES`; `:root` es igual a `fiesta`.
  - Todas las reglas existentes conservan sus nombres de clase: las pantallas siguen funcionando sin tocar el JSX. Sus colores pasan a variables.
  - Se eliminan degradados, `blur` y los hex sueltos.
  - Fondo del `body`: `var(--page)` plano.
  - `.spooky` pasa a ser un alias de `.display`, para no romper el JSX existente.

- [ ] **Step 3: Actualizar `index.html`**
  - Google Fonts: `Bricolage+Grotesque:opsz,wght@12..96,800`, `Nunito:wght@600;800` y `Creepster`; se quita `Outfit`.
  - Título: `Juegos de fiesta`.
  - `theme-color`: `#FFFBF0`.
  - Favicon: SVG en línea de un cuadrado coral con borde de tinta.
  - Script en línea, antes de `#root`, que pone `data-theme` desde `localStorage['pg-theme']` (try/catch), para que no parpadee.

- [ ] **Step 4: Montar el tema en las rutas**
  - En `src/App.jsx`, renderizar `<ThemeSync />` dentro de `PartyScope`, junto a `<Routes>`.
  - En `NoParty`, llamar `applyTheme('fiesta')` en un efecto.

- [ ] **Step 5: Verificar**

Run: `npm test && npm run build`
Expected: todas las pruebas pasan, incluida `styles.lint.test.js`, y el build termina sin errores.

- [ ] **Step 6: Verificación visual**
  - Levantar el dev server en el puerto 5180 con `.claude/launch.json`.
  - Abrir `#/p/halloween-2026/` y `#/p/halloween-2026/dashboard`.
  - Hacer captura con `data-theme` forzado por JS a `fiesta`, `halloween` y `baby-nina`.
  - Esperado: nada invisible y texto legible en los tres temas. Que algunas pantallas aún no estén pulidas es normal en esta tarea.

- [ ] **Step 7: Commit**

```bash
git add -A src index.html package.json package-lock.json
git commit -m "Fase 11: tokens por tema, componentes base, fuentes e íconos"
```

### Task 4: Selector de tema (Mi fiesta y dueño)

**Files:**
- Create: `src/components/ThemePicker.jsx`
- Modify:
  - `src/pages/admin/Party.jsx`: el selector va arriba de `GamesPicker`.
  - `src/pages/AdminPanel.jsx`: pasar `theme={dashboard.data?.party?.theme}`.
  - `src/pages/Owner.jsx`: `CreateParty` agrega `p_theme`; `PartyRow` muestra el nombre del tema.

**Interfaces:**
- Consumes: `THEMES`, `getTheme` (Tarea 1); `admin_set_theme`, `owner_create_party(..., p_theme)`, `owner_list_parties().theme` (Tarea 2).
- Produces: `ThemePicker({ value: string, onChange: (id) => void, busy?: boolean })`.
  - Grilla de mini-cartas, con `repeat(auto-fill, minmax(140px, 1fr))`.
  - Cada carta usa los colores del tema **en estilo en línea, tomados de `THEMES`**. Así cada una se ve con sus propios colores aunque el tema activo sea otro.
  - La prueba lint solo revisa hex literales, y estos vienen de datos, así que no la rompe.
  - La elegida lleva borde de 3px y ✓.

- [ ] **Step 1: Implementar `ThemePicker` y usarlo en `Party.jsx`**
  - Llamar `supabase.rpc('admin_set_theme', { p_theme })`.
  - Si hay error, revertir la selección y mostrar `errorMessage(error)` en `.error`.
  - Título de la sección: `Tema de la fiesta`.

- [ ] **Step 2: Agregar el selector en `Owner.jsx`**
  - En `CreateParty`, agregar `<ThemePicker>` con `fiesta` por defecto y enviar `p_theme`.
  - En `PartyRow`, mostrar `getTheme(p.theme).name` en la línea de datos.

- [ ] **Step 3: Verificar**
  - Run: `npm test && npm run build` (esperado: pasa).
  - En el navegador:
    - Crear la fiesta de prueba `prueba-temas` por SQL con contraseña.
    - Entrar como anfitrión y abrir su `dashboard` en otra pestaña.
    - Cambiar a `navidad` en Mi fiesta.
  - Esperado: la TV y el panel cambian sin recargar en menos de unos 2 segundos.
  - Al recargar el panel no hay parpadeo de otro tema.
  - Borrar `prueba-temas` al terminar.

- [ ] **Step 4: Commit y pausa de etapa**
  - `git commit -m "Fase 11: selector de tema en Mi fiesta y en el panel del dueño"`
  - README: agregar una sección "Fase 11: temas" con el orden de instalación (correr el script 13) y la lista de temas.
  - Commit del README.
  - **Preguntar a Gabriel si publicar la etapa 1 (`git push origin main`).**

---

## Etapas 2 a 4: reestilizar pantallas

Aplica a cada tarea de esta sección:

- **Qué se reemplaza:**
  - emojis de decoración → componentes de `Icon.jsx`;
  - clases ad hoc → las clases base de la Tarea 3;
  - spinners 🎃 → `<Spinner />`;
  - textos "Halloween" fijos → `me.party?.name`.
- **Qué no se toca:** la lógica de datos, las llamadas RPC y los nombres de props.
- **Verificación por tarea:**
  - `npm test && npm run build` pasa.
  - Capturas a 375×812 (celular) o 1920×1080 (TV) en `fiesta`, `halloween` y `baby-nina`.
  - Revisar contra las Global Constraints: medidas de tocables, ≥ 18px en la TV, nada invisible en Halloween.
  - Se puede medir en el navegador con `getBoundingClientRect` sobre `button, a.btn, input`.
- **Commit** al final de cada tarea.

### Task 5: Entrada y espera (Etapa 2)

**Files:** `src/pages/Join.jsx`, `src/pages/HostLogin.jsx`, `src/pages/Waiting.jsx`, `src/pages/GuestApp.jsx` (topbar: `ThemeIcon` + nombre de la fiesta, 👑 → ícono `IconCrown`), `src/pages/Home.jsx`, `src/pages/Owner.jsx`, `src/pages/PrintCodes.jsx`

- [ ] **Step 1:** `Waiting`/`Join` siguen el mockup "sala de espera": `pill` con el nombre de la fiesta, título `.display` de 30px o más y la acción principal abajo, a todo el ancho.
- [ ] **Step 2:** En `Home`, las pestañas de juegos son `.tabs` con ícono y texto; el emoji del catálogo de juegos se queda.
- [ ] **Step 3:** Verificar (bloque común) y commit `"Fase 11: entrada, espera e inicio con el estilo nuevo"`. **Preguntar si publicar la etapa 2.**

### Task 6: Disfraz y Caza de códigos en el celular (Etapa 3)

**Files:** `src/components/CostumeVote.jsx`, `src/components/CodeHunt.jsx`

- [ ] **Step 1:** Las opciones de voto son `.answer`, y la opción votada lleva `.selected`.
- [ ] **Step 2:** El PIN de códigos usa `.pin-input` con el estilo de tarjeta; los aciertos usan `--ok` con ícono.
- [ ] **Step 3:** Verificar y commit `"Fase 11: disfraz y códigos con el estilo nuevo"`.

### Task 7: Personaje e Impostor en el celular (Etapa 3)

**Files:** `src/components/PersonaGame.jsx`, `src/components/FactTips.jsx`, `src/components/ImpostorGame.jsx`

- [ ] **Step 1:** La pista o pregunta activa es `.question-card` y las respuestas son `.answer` (mockup "pregunta activa"). La palabra secreta del impostor va en `.question-card`.
- [ ] **Step 2:** Verificar y commit `"Fase 11: personaje e impostor con el estilo nuevo"`.

### Task 8: Regalo y Hombre Lobo en el celular (Etapa 3)

**Files:** `src/components/GiftGame.jsx`, `src/components/WolfPlay.jsx`, `src/components/WolfNarrator.jsx`

- [ ] **Step 1:** La carta de rol del lobo es `.card` grande con el emoji del rol (contenido), y las acciones nocturnas son `.answer`.
- [ ] **Step 2:** Verificar y commit `"Fase 11: regalo y hombre lobo con el estilo nuevo"`. **Preguntar si publicar la etapa 3.**

### Task 9: TV y panel del anfitrión (Etapa 4)

**Files:**
- TV: `src/pages/Dashboard.jsx`, `src/components/{CostumeReveal,FinalResults,HuntBoard,PersonaBoard,ImpostorBoard,GiftBoard,WolfBoard,LeaderboardList}.jsx`
- Panel: `src/pages/AdminPanel.jsx`, `src/pages/admin/*.jsx`

- [ ] **Step 1:** TV según el mockup:
  - cronómetro `.giant` en un círculo `--primary`;
  - pregunta `.question-card` de 34px o más;
  - respuestas de 20px o más en dos columnas;
  - puntos en una columna `.card`, con el primer lugar en `--ok`.
  - La cuenta regresiva y `.reveal-q` usan `.giant`.
- [ ] **Step 2:** En el panel, las pestañas del `AdminPanel` usan íconos en lugar de emojis.
- [ ] **Step 3:** Verificar:
  - Bloque común.
  - En la TV, ejecutar `[...document.querySelectorAll('body *')].filter(e => e.childNodes.length && [...e.childNodes].some(n => n.nodeType===3 && n.textContent.trim()) && parseFloat(getComputedStyle(e).fontSize) < 18).length`. Esperado: `0`.
- [ ] **Step 4:** Commit `"Fase 11: pantalla de TV y panel con el estilo nuevo"`. **Preguntar si publicar la etapa 4.**

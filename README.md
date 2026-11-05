# 🎃 Party Games App · Fase 1

Registro de invitados con aprobación del admin, modo admin/invitado, puntos (dar, quitar y deshacer) y dashboard en vivo con QR para registrarse.

**Stack:** React + Vite · Supabase (base de datos, tiempo real y login anónimo) · Vercel o GitHub Pages. Costo: $0.

**Tiempo estimado de configuración:** 20–30 minutos.

---

## 0. Requisitos

- [Node.js](https://nodejs.org) 20 o superior (`node -v`)
- Cuenta en GitHub
- Cuenta en [supabase.com](https://supabase.com) (puedes entrar con GitHub)

---

## 1. Crear el proyecto en Supabase

1. Entra a supabase.com → **New project**.
2. Ponle un nombre (ej. `party-games`), una contraseña de base de datos (guárdala) y la región más cercana (**South America (São Paulo)**).
3. Espera 1–2 minutos a que termine de crearse.

### 1.1 Crear las tablas
1. Menú izquierdo → **SQL Editor** → **New query**.
2. Copia y pega todo el archivo `supabase/01_fase1_schema.sql` y presiona **Run**.
3. Debe decir *Success. No rows returned*.

> ⚠️ Volver a correr ese archivo **borra todos los datos** (está pensado para preparar el proyecto, no para usarlo durante la fiesta).

### 1.2 Activar el login anónimo
**Authentication → Sign In / Providers →** activa **Allow anonymous sign-ins** → **Save**.

Esto permite que cada celular tenga su propia sesión sin pedir correo ni contraseña.

### 1.3 ⚠️ Subir el límite de registros anónimos (MUY importante)
Supabase limita los inicios de sesión anónimos **por dirección IP** (30 por hora por defecto). En la fiesta **todos usan el mismo wifi = la misma IP**, así que a partir del invitado 30 el registro fallaría.

**Authentication → Rate Limits →** sube *Rate limit for anonymous users* a **300** → **Save**.

### 1.4 Copiar tus claves
Botón **Connect** (arriba) o **Project Settings → API Keys**. Copia:
- **Project URL** → `https://xxxx.supabase.co`
- **Publishable key** (o *anon public key* en proyectos antiguos)

Esta clave es pública por diseño: la seguridad la dan las reglas del SQL. **Nunca** uses la `service_role` / *secret key* en la app.

---

## 2. Correr la app en tu computadora

```bash
cd party-games
npm install
cp .env.example .env      # en Windows: copy .env.example .env
```

Edita `.env` con tus datos:
```
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_xxxxx
```

```bash
npm run dev
```

La terminal muestra dos URLs:
- `Local: http://localhost:5173/`, para tu compu.
- `Network: http://192.168.x.x:5173/`, que puedes abrir **desde tu celular** si está en el mismo wifi. Úsala para probar.

---

## 3. Hacerte admin

1. Abre la app (en tu celular o en la compu) y **regístrate** con tu nombre. Quedarás "esperando aprobación".
2. En Supabase → **SQL Editor**, abre `supabase/02_hacerme_admin.sql`, cambia `'Gabriel'` por el nombre exacto con el que te registraste y presiona **Run**.
3. En la app toca **Revisar**. Entrarás y verás el interruptor **Invitado / Admin** arriba a la derecha.

Desde ahí apruebas a todos los demás.

---

## 4. Subir a internet (elige UNA opción)

Primero sube el proyecto a un repositorio de GitHub:
```bash
git init
git add .
git commit -m "Fase 1: registro, puntos y dashboard"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/party-games.git
git push -u origin main
```
(`.env` está en `.gitignore` y no se sube.)

### Opción A: Vercel (recomendada, la más simple)
1. Entra a [vercel.com](https://vercel.com) con GitHub → **Add New → Project** → importa `party-games`.
2. Vercel detecta Vite solo. En **Environment Variables** agrega `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
3. **Deploy**. Te da una URL como `party-games-xxx.vercel.app`.
4. Desde ahí, **cada `git push` se publica solo** (igual que GitHub Pages).

### Opción B: GitHub Pages
1. En tu repo: **Settings → Pages → Source: GitHub Actions**.
2. **Settings → Secrets and variables → Actions → pestaña Variables → New repository variable**: crea `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
3. Haz un push (o en la pestaña **Actions** → *Deploy a GitHub Pages* → **Run workflow**).
4. Queda en `https://TU-USUARIO.github.io/party-games/`.

El archivo `.github/workflows/deploy.yml` ya hace el build. Si usas Vercel, puedes borrarlo.

---

## 5. URLs de la app

| Para quién | URL |
|---|---|
| Invitados (lleva el QR) | `https://tu-app/#/` |
| Dashboard (TV/proyector) | `https://tu-app/#/dashboard` |
| Dashboard sin QR | `https://tu-app/#/dashboard?noqr` |
| Admin | la misma de invitados; activa el interruptor **Admin** |

El panel de admin también muestra estas URLs en la sección **Enlaces**.

---

## 6. Prueba completa antes de la fiesta (10 min)

- [ ] Abre el dashboard en la compu o la TV.
- [ ] Desde un segundo celular (o una ventana de incógnito) regístrate como invitado de prueba.
- [ ] En tu celular (modo Admin) aparece la solicitud → **Aprobar**. El invitado entra solo y aparece en el dashboard.
- [ ] Dale +5 puntos → el dashboard muestra **+5** y reordena sin recargar.
- [ ] **Deshacer** el movimiento → vuelve a 0.
- [ ] En el celular de prueba: cierra el navegador y vuelve a abrir → sigue dentro.
- [ ] Prueba "Ya tengo perfil" desde otra ventana de incógnito → apruébalo → entra al mismo perfil.
- [ ] Borra los datos de prueba: Supabase → **Table Editor** → `players` → selecciona los de prueba → Delete. Sus puntos y dispositivos se borran en cascada.

## 7. Checklist del día

- Abre el proyecto de Supabase el mismo día (los proyectos gratuitos se pausan tras 7 días sin uso).
- Imprime el QR o deja el dashboard visible en la entrada.
- Pon la TV/compu del dashboard sin suspensión de pantalla (la app intenta mantenerla encendida en Chrome).
- Ten tu celular cargado: eres quien aprueba a todos.

---

## Cómo funciona el tiempo real aquí

```
Celular admin ──rpc('admin_add_points')──► Supabase (Postgres)
                                                │ inserta fila en points_ledger
                                                ▼
                                   Realtime (WebSocket) avisa:
                                   "cambió points_ledger"
                                                │
        ┌───────────────────────────┬───────────┴──────────────┐
        ▼                           ▼                          ▼
   Dashboard TV               Celular invitado             Celular invitado
   vuelve a pedir             vuelve a pedir               ...
   get_leaderboard()          get_leaderboard()
```

- **WebSocket (empuje):** la tabla general, las solicitudes del admin y los movimientos. Ver `src/hooks/useRealtimeRefresh.js`.
- **Patrón "aviso + volver a pedir":** el aviso solo dice *algo cambió*; la app vuelve a pedir los datos completos. Es más simple y nunca queda desincronizado.
- **Redes de seguridad:** si el celular estuvo bloqueado o se cortó el wifi, la app se pone al día al volver a la pantalla y cada 30 s.
- **Polling (consulta cada 3 s):** solo en la pantalla "esperando aprobación". Es corto y muy simple, así que no vale la pena un WebSocket.

## Seguridad (por qué nadie puede hacer trampa desde el celular)

- La app **solo puede leer** datos públicos (nombres y puntos visibles).
- Todo lo que escribe pasa por **funciones del servidor** (`register_player`, `admin_add_points`, …) que verifican quién eres. Por ejemplo, `admin_add_points` comprueba en el servidor que el dispositivo pertenece a un admin aprobado.
- Los datos curiosos (juego 4) están en `player_secrets`, que nadie puede leer desde la app.
- Cada celular necesita aprobación del admin, incluso para un perfil que ya existe.

## Estructura

```
supabase/
  01_fase1_schema.sql     tablas, seguridad y funciones
  02_hacerme_admin.sql    convertir tu usuario en admin
src/
  lib/supabase.js         cliente de Supabase
  lib/urls.js             URLs de registro y dashboard
  hooks/useMe.js          sesión anónima y estado del invitado
  hooks/useLeaderboard.js tabla general en vivo
  hooks/useRealtimeRefresh.js  patrón de tiempo real reutilizable
  pages/GuestApp.jsx      decide qué pantalla mostrar
  pages/Join.jsx          registro / "ya tengo perfil"
  pages/Waiting.jsx       esperando aprobación
  pages/Home.jsx          vista del invitado
  pages/AdminPanel.jsx    solicitudes, puntos y movimientos
  pages/Dashboard.jsx     pantalla de la TV
  components/LeaderboardList.jsx
```

## Problemas comunes

| Síntoma | Causa probable |
|---|---|
| Pantalla "Falta configurar Supabase" | Falta `.env` o las variables en Vercel/GitHub. Tras crear `.env`, reinicia `npm run dev`. |
| "Anonymous sign-ins are disabled" | Falta el paso 1.2. |
| Falla el registro después de ~30 personas | Falta el paso 1.3 (rate limit). |
| El dashboard no se actualiza solo | Revisa que la última línea del SQL (`alter publication…`) haya corrido sin error. Igual se actualiza cada 30 s. |
| "Solo el admin puede hacer esto" | Corre `02_hacerme_admin.sql` con tu nombre exacto. |

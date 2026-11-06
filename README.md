# 🎃 Party Games App

- **Fase 1:** registro con aprobación del admin, modo admin/invitado, puntos (dar, quitar y deshacer) y dashboard en vivo con QR.
- **Fase 2:** votación del mejor disfraz con revelación en pantalla, gestión de invitados y opción de borrar todo para una nueva fiesta. Ver [la sección de la fase 2](#fase-2-mejor-disfraz-y-limpieza).
- **Fase 3:** caza de códigos secretos de 6 caracteres, con hoja para imprimir y tablero en pantalla. Ver [la sección de la fase 3](#fase-3-caza-de-códigos).
- **Fase 4:** ¿Quién es el personaje?, con rondas de datos curiosos, votación con tiempo y revelación con gráfico. Ver [la sección de la fase 4](#fase-4-quién-es-el-personaje).
- **Fase 5:** El Impostor, más la tabla congelada y los resultados finales de la noche. Ver [la sección de la fase 5](#fase-5-el-impostor-y-resultados-finales).
- **Fase 6:** El Regalo Loco, más el QR del wifi en la pantalla. Ver [la sección de la fase 6](#fase-6-el-regalo-loco-y-wifi).
- **Fase 7:** Hombre Lobo, etapa 1: narrador, baraja sugerida, noche simultánea, alcalde y TV con la mesa. Ver [la sección de la fase 7](#fase-7-hombre-lobo-etapa-1).

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

> ⚠️ Volver a correr `01_fase1_schema.sql` **borra todos los datos** y rompe las tablas de la fase 2. Córrelo solo una vez. Para limpiar datos usa **Admin → 🧹 Ajustes**.

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

El panel de admin también muestra estas URLs en la pestaña **📺 Pantalla**.

---

## 6. Prueba completa antes de la fiesta (10 min)

- [ ] Abre el dashboard en la compu o la TV.
- [ ] Desde un segundo celular (o una ventana de incógnito) regístrate como invitado de prueba.
- [ ] En tu celular (modo Admin) aparece la solicitud → **Aprobar**. El invitado entra solo y aparece en el dashboard.
- [ ] Dale +5 puntos → el dashboard muestra **+5** y reordena sin recargar.
- [ ] **Deshacer** el movimiento → vuelve a 0.
- [ ] En el celular de prueba: cierra el navegador y vuelve a abrir → sigue dentro.
- [ ] Prueba "Ya tengo perfil" desde otra ventana de incógnito → apruébalo → entra al mismo perfil.
- [ ] Borra los datos de prueba: **Admin → 🧹 Ajustes → Borrar todo**.

## 7. Checklist del día

- Abre el proyecto de Supabase el mismo día (los proyectos gratuitos se pausan tras 7 días sin uso).
- Imprime el QR o deja el dashboard visible en la entrada.
- Pon la TV/compu del dashboard sin suspensión de pantalla (la app intenta mantenerla encendida en Chrome).
- Ten tu celular cargado: eres quien aprueba a todos.

---

## Fase 2: mejor disfraz y limpieza

### Instalar (2 minutos)
1. Supabase → **SQL Editor → New query** → pega todo `supabase/03_fase2_disfraces.sql` → **Run**. Debe decir *Success*. **No borra nada** de la fase 1 y se puede correr varias veces.
2. Sube el código (`git add . && git commit -m "Fase 2" && git push`). Vercel lo publica solo.

### Panel de admin (pestañas)
| Pestaña | Qué hace |
|---|---|
| 👥 Invitados | Aprobar solicitudes. Lista de invitados: ✏️ corregir nombre o disfraz (ej. marcó "sin disfraz" por error) y 🗑 eliminar. |
| ✨ Puntos | Dar o quitar puntos y deshacer movimientos manuales. |
| 🎭 Disfraces | Abrir y cerrar la votación, revelar el podio y configurar los puntos. |
| 🔍 Códigos | Crear e imprimir códigos, empezar o terminar la caza, reglas de puntos (fase 3). |
| 🕵️ Personaje | Lanzar rondas, revelar, descartar datos y configurar las reglas: tiempo, puntos por adivinar y bonus del dueño (fase 4). |
| 🃏 Impostor | Elegir jugadores, número de impostores y palabra; abrir votaciones de defensa o eliminación (fase 5). |
| 🎁 Regalo | El Regalo Loco: escritura, lectura, votación y revelación (fase 6). |
| 🐺 Lobo | Abrir la mesa del Hombre Lobo, asignar o cambiar el narrador, cancelar y configurar puntos (fase 7). |
| 📺 Pantalla | Elegir qué muestra el dashboard, 🔒 congelar la tabla, 🏆 resultados finales, 📶 wifi y enlaces. |
| 🧹 Ajustes | **Reiniciar puntos y votaciones**, o **Borrar todo (nueva fiesta)**: elimina a todos menos a los admins y permite renombrar la fiesta. Se confirma escribiendo `BORRAR`. |

### Cómo correr el concurso en la fiesta
1. **🎭 Disfraces → Abrir votación.** A los invitados les aparece la tarjeta "Vota por el mejor disfraz".
2. Cada invitado toca a los disfrazados en el orden que prefiere (el primero es su 1.º), reordena con ▲▼ y quita con ✕. **Se guarda solo** con cada cambio. Nadie se ve a sí mismo en la lista.
3. Cuando llega alguien disfrazado, aparece en todos los celulares con la etiqueta **¡Nuevo!**.
4. **Cerrar votación y calcular.** Se calcula el resultado y se generan los puntos **ocultos**. La pantalla sigue mostrando la tabla general.
5. **📺 Mostrar revelación en la pantalla**, luego **Revelar 3.er lugar**, **Revelar 2.º** y **Revelar 1.º**. Cada paso tiene una cuenta regresiva 3-2-1 en la TV.
6. Al revelar el 1.º, los puntos del concurso se suman a la tabla general.
7. **Volver a tabla general.**

Si te equivocas: **Paso atrás** deshace la última revelación, y **Reabrir votación** borra los resultados pero conserva los votos.

### Cómo se calcula el ganador (Borda normalizado)
- En cada voto con *n* disfrazados posibles (todos menos el votante), el 1.º recibe 1 punto, el último 0, y los del medio la parte proporcional: `(n − posición) / (n − 1)`.
- Quien no fue ordenado en ese voto recibe 0.
- El puntaje final es el **promedio** de todos los votos. Así no importa cuántos disfrazados haya, y nadie pierde por no poder votarse a sí mismo.
- Desempate: más veces en 1.er lugar, luego más veces en 2.º. Si sigue empatado, se marca con ⚠️ en "Ver resultados" y puedes ajustarlo con puntos manuales.
- Puntos a la tabla general (editables antes de cerrar): 🥇 15 · 🥈 10 · 🥉 6 · resto de disfrazados 2.

**Para que la votación sea justa**, recuerda a los invitados que actualicen su voto cuando llegue gente nueva: el que no aparece en un voto recibe 0 de ese votante. La etiqueta **¡Nuevo!** sirve para eso.

### Antes de la fiesta
- [ ] Corre `03_fase2_disfraces.sql`.
- [ ] Prueba el flujo completo con 2 o 3 invitados de prueba (abrir, votar, cerrar, revelar).
- [ ] **🧹 Ajustes → Borrar todo** para empezar la fiesta limpia. Tú sigues como admin.

---

## Fase 3: caza de códigos

### Instalar
1. Supabase → **SQL Editor → New query** → pega todo `supabase/04_fase3_codigos.sql` → **Run**. No borra nada y se puede correr varias veces.
2. `git add . && git commit -m "Fase 3: caza de códigos" && git push`

### Preparar los códigos (antes de la fiesta)
1. **Admin → 🔍 Códigos → ＋ Crear códigos** (ej. 8). Cada uno tiene 6 caracteres, por ejemplo `K7PX3M`. No se usan caracteres que se confunden (0/O, 1/I/L).
2. Opcional: toca **📍 agregar ubicación** en cada código para anotar dónde lo esconderás. Solo lo ves tú.
3. **🖨 Imprimir códigos** abre una hoja lista para imprimir. Recorta las tarjetas y escóndelas.
   - Esa página solo funciona en un dispositivo vinculado a tu perfil de admin. Para imprimir desde la compu: abre la app ahí, usa **"Ya tengo perfil"** y aprueba esa solicitud desde tu celular.
4. Usa **🧹 Ajustes → Borrar todo** sin miedo: **los códigos se conservan**. Solo se borran los hallazgos y los puntos. Para borrar los códigos usa **🗑 Borrar todos los códigos** en la pestaña Códigos.

### Durante la fiesta
1. **▶︎ Empezar la caza.** A los invitados les aparece la tarjeta 🔍 *Caza de códigos*.
2. Quien encuentra un código lo escribe en la app (acepta minúsculas, espacios y guiones).
3. Puntos según el orden de llegada **a ese código**: 1.º 10 · 2.º 8 · 3.º 6 · 4.º a 6.º 4 · 7.º en adelante 2. Máximo 4 códigos por persona. Todo se puede cambiar en **⚙️ Reglas**.
4. **📺 Mostrar en pantalla:** la TV muestra qué códigos se descubrieron, quién encontró cada uno primero, los últimos hallazgos y el top de cazadores.
5. **■ Terminar la caza** cuando quieras cerrarla.

**Protección:** tras 5 códigos incorrectos en un minuto, esa persona debe esperar un minuto, para evitar que alguien pruebe al azar. Si borras un código, también se quitan los puntos que dio.

---

## Fase 4: ¿Quién es el personaje?

### Instalar
1. Supabase → **SQL Editor → New query** → pega todo `supabase/05_fase4_personaje.sql` → **Run**. No borra nada y se puede correr varias veces.
2. `git add . && git commit -m "Fase 4: quién es el personaje" && git push`

### Los datos curiosos
- Al registrarse, cada invitado puede escribir un dato (opcional). Ve una explicación e **ideas de ejemplo** (🔄 para ver otras).
- El texto deja claro que **no es anónimo para siempre**: se muestra sin nombre para adivinar, pero al final de la ronda se revela de quién es, y conviene evitar cosas muy personales.
- Cada invitado puede tener **hasta 2 datos**. En su celular, la tarjeta **🤫 Mis datos curiosos** tiene el botón *"Si tienes otra anécdota o dato, agrégala aquí"*, y ahí también se editan o borran los datos que aún no salieron.
- Cada ronda saca **un dato al azar de todo el pool**. Como cualquiera puede tener varios datos, **nadie puede adivinar por descarte** al final.

### Cómo jugar
1. **Admin → 🕵️ Personaje → ▶︎ Nueva ronda.** Se elige un dato al azar que no haya salido, y **la pantalla cambia sola** a este juego.
2. La TV muestra el dato (sin el nombre de su dueño), la cuenta regresiva (30 s) y cuántos han votado.
3. En los celulares aparece arriba la tarjeta para votar. Se toca un nombre y el voto se puede cambiar mientras quede tiempo. El dueño del dato ve "🤫 ¡Es tu dato!" y no vota.
4. **🎭 Revelar quién es:** la TV muestra al personaje y un gráfico de los votos, y en cada celular aparece si acertó. Los puntos se suman solos.
5. La persona puede contar su historia, y luego **▶︎ Siguiente ronda**.

**Puntos** (editables en ⚙️ Reglas):
- Adivinar: **+5**.
- Dueño del dato (puntos extra por participar): **+5** cuando su dato sale. **Si no lo atrapan** (menos de la mitad de los votos acierta), **se duplican: +10**. La pantalla muestra "🎯 ¡Atrapado!" o "😎 ¡No lo atraparon! Puntos x2".

**Si sale un dato que no conviene:** **🚫 Descartar dato** (ese dato no vuelve a salir) o **↩︎ Cancelar ronda** (vuelve al pool). Con **👀 Ver de quién es** puedes ver al dueño antes de revelar.

Al reiniciar desde **🧹 Ajustes**, las rondas se borran pero los datos se conservan y vuelven a estar disponibles.

---

## Fase 5: El Impostor y resultados finales

### Instalar
1. Supabase → **SQL Editor → New query** → pega todo `supabase/06_fase5_impostor_final.sql` → **Run**. No borra nada y se puede correr varias veces.
2. `git add . && git commit -m "Fase 5: impostor y resultados finales" && git push`

### El Impostor (Admin → 🃏 Impostor)
1. **Elige a los jugadores.** Todos vienen marcados; toca un nombre para sacarlo.
2. **Número de impostores:** la app sugiere cuántos y explica por qué, pero lo controlas con − / ＋.
3. **Palabra:** 🎲 al azar del banco, con filtro opcional de categoría, o ✍️ una tuya con su pista.
4. **▶︎ Repartir y empezar.** La pantalla cambia sola y muestra el **orden para hablar**.
5. Cada jugador **mantiene presionada** su carta para verla. La tripulación ve la palabra; el impostor ve "ERES IMPOSTOR" y una pista general.
6. **Votaciones:**
   - **🗣 Defensa:** en la TV se ve en vivo **quién votó a quién**, pero nadie sale. Sirve para que el más votado se defienda.
   - **☠️ Eliminación:** al cerrar, sale el más votado (con empate, nadie sale) y la TV muestra si **era impostor o inocente**.
   - Mientras la votación está abierta, puedes cambiar entre defensa y eliminación.
7. **Fin de la ronda:**
   - **🛡 Gana la tripulación** cuando eliminan a todos los impostores: **+5** a cada tripulante.
   - **🕵️ Ganan los impostores** si igualan en número a la tripulación, o si uno adivina la palabra: **+12** a cada impostor. Cada impostor tiene **un intento** para adivinar, aunque ya lo hayan eliminado.
   - También puedes terminar a mano (🏁) eligiendo quién ganó.

**Banco de palabras:** 67 palabras en 6 categorías (Lugares de La Paz, Comida paceña, Cotidiano y cultura, Países, Objetos, Animales), con **2 pistas generales** cada una. El impostor recibe una de las dos al azar. Las pistas no delatan la categoría y algunas tienen doble sentido a propósito (Llama → "Fuego", Reloj → "Muñeca", Chile → "Picante"). Las palabras ya usadas se evitan mientras queden otras.

### Final de la noche (Admin → 📺 Pantalla)
- **🔒 Congelar tabla** (opcional): desde ese momento la TV y los celulares muestran los puntos de ese instante, y los juegos siguen sumando a escondidas. Tú, como admin, ves los puntos reales.
- **🏆 Resultados de la noche:** la TV muestra **a todos con sus puntos**, el podio y el mejor disfraz. Si la tabla estaba congelada, cada uno muestra cuánto sumó al final ("+17 al final").
- **🧹 Ajustes → Reiniciar** también descongela la tabla.

---

## Fase 6: El Regalo Loco y wifi

### Instalar
1. Supabase → **SQL Editor → New query** → pega todo `supabase/07_fase6_regalo_wifi.sql` → **Run**. No borra nada y se puede correr varias veces.
2. `git add . && git commit -m "Fase 6: regalo loco y wifi" && git push`

### 📶 QR del wifi en la pantalla (Admin → 📺 Pantalla → 📶 Wifi de la casa)
- Escribe el **nombre de la red** (exacto, con mayúsculas) y la **contraseña**, y toca **Guardar wifi**. La tabla general muestra un segundo QR para conectarse, debajo del QR de registro.
- Se guarda en Supabase, **no en GitHub**. Se conserva al reiniciar, así que sirve para próximas fiestas.
- Ojo: el QR contiene la contraseña, así que quien tenga el enlace de la pantalla podría leerla. Es lo mismo que pegar el QR en la pared.
- **Pruébalo:** escanea el QR de la pantalla con tu celular y confirma que conecta.

### El Regalo Loco (Admin → 🎁 Regalo)
1. **Elige jugadores** (mínimo 4; con 10 a 15 la lectura no se hace larga) → **▶︎ Empezar a escribir**. La pantalla cambia sola.
2. Cada jugador escribe en su celular **3 partes a ciegas**:
   - 1️⃣ **¿Qué le regalas a X?** (a quien le tocó, como amigo secreto)
   - 2️⃣ **¿Para qué sirve…?** un regalo que no conoce
   - 3️⃣ **¿Qué exclama…?** alguien que recibe un regalo que no conoce

   La app reparte para que **cada uno escriba 1 de cada parte** y nunca de su propia frase. La TV muestra el progreso.
3. **✅ Cerrar escritura:** se arman las frases. Si alguien no escribió su parte, se rellena con algo al azar.
4. **Lectura:** con ◀︎ ▶︎ pasas los regalos uno por uno en la TV para leerlos en voz alta.
5. **🗳 Abrir votación:** cada uno marca sus **3 favoritas** (las suyas aparecen bloqueadas). La TV muestra todas las frases numeradas.
6. **Cerrar votación** y luego **revelar 3.º → 2.º → 1.º**, con cuenta regresiva en la TV.
7. **Puntos** a **los 3 autores** de cada frase ganadora: 🥇 **10** · 🥈 **6** · 🥉 **4**. Se suman al revelar el 1.º.

---

## Fase 7: Hombre Lobo (etapa 1)

### Instalar
1. Supabase → **SQL Editor → New query** → pega todo `supabase/08_fase7_lobo.sql` → **Run**. No borra nada y se puede correr varias veces.
2. `git add . && git commit -m "Fase 7: hombre lobo" && git push`

**Roles de esta etapa:** 🐺 Lobo · 👤 Aldeano · 🔮 Vidente · 🧪 Bruja · 🏹 Cazador, más 🎖️ Alcalde (se vota el día 1). Alcanza para jugar de 6 a 25 personas. Los roles avanzados (Cupido, Tonto, Traidor, Feroz, Infectador, Zorro, Flautista, Anciano, Lobo Blanco y Niña) quedan para la etapa 2, según `fase5-hombre-lobo.md` del proyecto.

### Cómo se juega
1. **Admin → 🐺 Lobo:** elige un **narrador** (no juega; puede ser cualquiera, incluso tú) → **🚪 Abrir mesa**.
2. A los invitados les aparece **"🐺 Unirme al Hombre Lobo"**. El narrador ve la lista en su celular, puede quitar gente y toca **🔒 Cerrar mesa**.
3. **Baraja:** la app sugiere una **explicando por qué** (porcentaje de lobos, cuándo conviene la Bruja, el alcalde desde 12 jugadores). El narrador ajusta con ＋/−: los aldeanos se calculan solos y hay un **medidor de balance** 🟢🟡🔴 con avisos. También elige si hay alcalde, si la baraja es pública y los minutos de debate. Luego **🃏 Repartir**.
4. **Reparto:** roles y **asientos al azar**. Cada celular dice "Siéntate entre X e Y" y la TV dibuja la mesa en círculo con la explicación de los roles. Cada uno **mantiene presionada** su carta para verla; los lobos ven a su manada.
5. El narrador avanza con **▶︎ Siguiente fase** y tiene un **guion para leer en voz alta** en cada una:
   - 🌙 **Noche, todos a la vez:** los lobos eligen víctima y ven en vivo lo que elige su manada; la Vidente mira una carta; **los demás responden "¿De quién sospechas?"**, así nadie se delata por no tocar el celular.
   - 🧪 **Turno de la Bruja:** ve a la víctima y puede salvarla o envenenar a alguien (una vez cada poción).
   - ☀️ **Amanecer:** la TV anuncia a los muertos **con su rol**.
   - 🎖️ **Alcalde** (día 1) → 🗣 **Debate** con temporizador → 🗳 **Votación** en el celular (el alcalde vale doble; con empate, nadie muere) → ⚖️ **Veredicto**, donde la TV muestra **quién votó a quién**.
   - 🏹 Si muere el **Cazador**, dispara desde su celular. Si muere el **Alcalde**, elige a su sucesor.
6. **Fin:** gana la aldea cuando mueren todos los lobos, o los lobos cuando igualan a los aldeanos vivos. La TV revela todas las cartas.
   - **Puntos:** **+8** al bando ganador y **+2 extra** a los ganadores que sobrevivieron.

**El narrador** ve todos los roles, quién ya respondió, la víctima de la manada y las pociones. Puede **💀 matar o 💚 revivir** a mano y **terminar la partida** declarando un ganador. Si alguien no responde a tiempo, pierde su acción.

**Seguridad:** los roles nunca viajan por el canal en vivo. Cada celular pide **su propia vista** al servidor, y el **admin no ve roles** en su panel, por si juega.

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
  01_fase1_schema.sql     tablas, seguridad y funciones (correr UNA vez)
  02_hacerme_admin.sql    convertir tu usuario en admin
  03_fase2_disfraces.sql  concurso de disfraces, modos de pantalla, gestión y reinicio
  04_fase3_codigos.sql    caza de códigos
  05_fase4_personaje.sql  ¿Quién es el personaje?
  06_fase5_impostor_final.sql  El Impostor, congelar tabla y resultados finales
  07_fase6_regalo_wifi.sql     El Regalo Loco y wifi
  08_fase7_lobo.sql            Hombre Lobo (etapa 1)
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
  pages/AdminPanel.jsx    pestañas del admin
  pages/admin/*.jsx       Invitados, Puntos, Disfraces, Pantalla, Ajustes
  pages/Dashboard.jsx     pantalla de la TV (cambia según el modo)
  hooks/useCostume.js     estado del concurso para el invitado
  hooks/useDashboard.js   modo de la pantalla
  components/CostumeVote.jsx    votación del invitado
  components/CostumeReveal.jsx  revelación con cuenta regresiva
  components/CodeHunt.jsx       caza de códigos (invitado)
  components/HuntBoard.jsx      caza de códigos (pantalla)
  hooks/useHunt.js              estado de la caza
  pages/PrintCodes.jsx          hoja para imprimir códigos (#/imprimir-codigos)
  components/PersonaGame.jsx    ¿Quién es el personaje? (votar + mis datos curiosos)
  components/FactTips.jsx       explicación e ideas para escribir datos curiosos
  components/PersonaBoard.jsx   ¿Quién es el personaje? (pantalla)
  hooks/usePersona.js           estado del juego + cuenta regresiva sincronizada
  hooks/useLiveRpc.js           RPC + tiempo real genérico
  lib/impostor.js               sugerencia de impostores
  components/ImpostorGame.jsx   El Impostor (carta, votar, adivinar)
  components/ImpostorBoard.jsx  El Impostor (pantalla)
  components/FinalResults.jsx   resultados de la noche (pantalla)
  components/GiftGame.jsx       El Regalo Loco (escribir, votar)
  components/GiftBoard.jsx      El Regalo Loco (pantalla)
  pages/admin/Gift.jsx, Wifi.jsx, Wolf.jsx
  lib/wolfRoles.js              roles, baraja sugerida, balance y guion
  components/WolfPlay.jsx       Hombre Lobo en el celular (carta, acciones)
  components/WolfNarrator.jsx   panel del narrador
  components/WolfBoard.jsx      Hombre Lobo en la TV
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

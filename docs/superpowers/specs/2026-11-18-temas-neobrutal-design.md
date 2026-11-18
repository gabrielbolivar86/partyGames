# Rediseño: estilo "cartas y stickers" + temas por fiesta

Fecha: 2026-11-18 · Estado: borrador para aprobar

## Por qué

La app nació como "Fiesta de Halloween": fondo oscuro morado, naranja, letra Creepster y emojis 🎃 por todas partes. Desde la Fase 10 hay varias fiestas (las de Gabriel y las de sus amigos), y no todas son de Halloween: puede ser Navidad, un baby shower, una revelación de género o una fiesta cualquiera. Cada anfitrión debe poder elegir cómo se ve **su** fiesta, y la app en general debe sentirse como un juego social moderno (Jackbox, Kahoot, Among Us), divertido y táctil, no como una página genérica.

## Metas

- Un estilo visual único para toda la app: **neo-brutalismo suave**, como cartas de juego o stickers físicos.
- **8 temas** que el anfitrión elige por fiesta; se aplican en su panel, en la TV y en los celulares de los invitados.
- El tema por defecto ("Fiesta") es azul y rojo, alegre.
- Celular: botones grandes para el pulgar, sin toques accidentales.
- TV: todo se lee desde el sillón (texto mínimo 18px).

## No-metas

- Colores personalizados a mano por el anfitrión (posible después).
- Cambiar reglas o lógica de los juegos.
- Modo claro/oscuro automático según el teléfono: el tema manda.

## Anti-metas (sería un fracaso aunque funcione)

- Degradados, neón, glassmorphism o sombras difuminadas.
- Texto que no se lee: tinta sobre fondo oscuro, blanco sobre colores claros, texto de reglas en la TV de menos de 18px.
- Un tema que rompe una pantalla (algo invisible o ilegible en Halloween, que es el único oscuro).
- Emojis como decoración por todos lados.

## El sistema visual (fijo en todos los temas)

- **Tinta** `#18181B`: contornos y texto principal sobre superficies claras.
- **Bordes** `2px solid` tinta. **Sombra dura** `4px 4px 0` tinta (3px en elementos chicos). Esquinas `12–16px`.
- Botón presionado: se mueve 2px hacia la sombra (`translate(2px,2px)` y sombra `2px 2px 0`), como apretar una carta.
- **Letras** (Google Fonts):
  - Títulos, cronómetros y puntos: **Bricolage Grotesque 800**.
  - Texto: **Nunito 600/800**.
- **Íconos**: Tabler (`@tabler/icons-react`), trazo grueso y uniforme (`stroke={2.25}`).
- **Tarjeta de pregunta/reto**: color propio del tema y ligeramente inclinada (-1°), como una carta recién sacada.
- **Celular** (mejores prácticas):
  - Tocables de al menos 56px de alto, 12px de separación y ancho completo en respuestas.
  - Acción principal abajo, al alcance del pulgar.
  - Texto base 16px y retos/preguntas 18px o más.
  - La opción elegida se pinta de color y lleva ✓.
- **TV**: pregunta ≥ 34px, respuestas ≥ 20px, nada por debajo de 18px. Cronómetro en círculo grande. Puntos en columna, con el primer lugar resaltado.

## Los 8 temas

Cada tema define el fondo de la página y 4 colores con función fija:

- **Principal**: botón principal y opción elegida.
- **Secundario**: botones secundarios y la segunda opción destacada.
- **Pregunta**: la tarjeta de pregunta o reto.
- **Superficie**: tarjetas y botones neutros.

Además define un ícono y una letra de títulos.

| Tema | id | Fondo | Principal | Secundario | Pregunta | Superficie | Ícono |
|---|---|---|---|---|---|---|---|
| Fiesta (default) | `fiesta` | `#FFFBF0` | `#FF5D5D` | `#4D7CFE` | `#FACC15` | `#FFFFFF` | confetti |
| Halloween | `halloween` | `#2B2140` | `#FF8A3D` | `#A78BFA` | `#A3E635` | `#F4F1FF` | pumpkin-scary |
| Navidad | `navidad` | `#FFF4E4` | `#D62839` | `#1B7F4E` | `#9ED9A8` | `#FFFFFF` | christmas-tree |
| Baby shower niño | `baby-nino` | `#DCEFFF` | `#2E9BEA` | `#3CCFC0` | `#FFC93C` | `#FFFFFF` | baby-carriage |
| Baby shower niña | `baby-nina` | `#FFE3EE` | `#F0569A` | `#B43C7A` | `#FFB6D3` | `#FFFFFF` | baby-carriage |
| Revelación de género | `revelacion` | `#F7F1FF` | `#F0569A` | `#2E9BEA` | `#C9B6FF` | `#FFFFFF` | help-hexagon |
| Neutro verde | `verde` | `#F1F4EC` | `#2F8F5B` | `#8DB596` | `#DCE8C8` | `#FFFFFF` | leaf |
| Neutro azul | `azul` | `#EEF3FA` | `#2F5FD0` | `#7FA8E8` | `#CFE0FA` | `#FFFFFF` | droplet |

Reglas de texto (contraste medido, WCAG AA):

- **Sobre Principal y Secundario** el texto de botón va en negrita a 18px o más. Así cuenta como "texto grande" y basta un contraste de 3:1. El color del texto (`--on-primary` / `--on-secondary`) depende del tema:

  | Tema | Sobre Principal | Sobre Secundario |
  |---|---|---|
  | `fiesta` | blanco (3.0) | blanco (3.7) |
  | `halloween` | tinta (7.6) | tinta (6.5) |
  | `navidad` | blanco (5.0) | blanco (5.0) |
  | `baby-nino` | blanco (3.0) | tinta (9.2) |
  | `baby-nina` | blanco (3.2) | blanco (5.4) |
  | `revelacion` | blanco (3.2) | blanco (3.0) |
  | `verde` | blanco (4.0) | tinta (7.8) |
  | `azul` | blanco (5.7) | tinta (7.3) |

- Texto chico (menos de 18px) sobre Principal o Secundario va siempre en tinta, o simplemente no se pone ahí.
- Sobre Pregunta y Superficie: siempre tinta.
- Halloween es el único tema con fondo oscuro. El texto que va directo sobre el fondo usa `#F4F1FF` (y el texto suave `#C9C0E0`); dentro de tarjetas sigue siendo tinta. Contornos y sombras en `#0D0A14`.

**Colores de estado** (iguales en todos los temas, porque significan algo en los juegos): correcto / aprobado = menta `#34D399`, error / eliminar = rojo `#EF4444`, con texto en tinta. Si en un tema chocan con Principal (Navidad usa rojo), igual se acompañan de ícono y texto, no solo color.

**Letra de títulos**: Bricolage Grotesque en todos. **Llamada mía:** Halloween conserva Creepster solo en los números y títulos gigantes de la TV (cuenta regresiva, cronómetro de Personaje, "?" de revelación), como guiño. Si no gusta, se quita cambiando una variable.

## Cómo se construye (decidido)

**Enfoque elegido: tema completo** (colores + letra + ícono), elegido por el anfitrión en "Mi fiesta". Descartados:

- Solo colores: un baby shower con letra de terror no sirve.
- Colores a mano: da más formas de que una fiesta quede ilegible. Queda para después.

### Datos

- `supabase/13_fase11_temas.sql`:
  - Columna `events.theme text not null default 'fiesta'`, con un check contra la lista de ids.
  - `halloween-2026` queda en `'halloween'`.
  - Se incluye `theme` en el grant de columnas visibles de `events`.
  - `party_json()` devuelve `theme`, así llega por `my_status()` y `get_dashboard()`.
  - Nuevo `admin_set_theme(p_theme text)`: valida el id y toca `dashboard_state.updated_at` para que la TV cambie al momento.
  - `owner_create_party` acepta `p_theme text default 'fiesta'`.

### Frontend

- `src/lib/themes.js`: lista de temas (id, nombre, ícono, colores, letra de títulos) y la función `applyTheme(id)`. Esa función pone `data-theme` en `<html>` y actualiza el `meta theme-color`. El título de la pestaña pasa a ser el nombre de la fiesta. El favicon es uno solo, neutro, para todas las fiestas (llamada mía: cambiarlo por tema no aporta casi nada).
- `src/styles.css` se reescribe sobre variables:
  - `--page`, `--surface`, `--ink`, `--text`, `--text-on-page`, `--muted`
  - `--primary`, `--on-primary`, `--secondary`, `--on-secondary`, `--question`
  - `--ok`, `--danger`
  - `--font-display`, `--font-body`

  Un bloque `[data-theme="…"]` por tema y ningún color fijo fuera de esos bloques. Hoy hay ~160 colores escritos a mano, pensados solo para fondo oscuro; todos pasan a variables.
- Aplicar el tema: un componente dentro de `PartyScope` (`src/App.jsx`) usa `useDashboard()` y llama `applyTheme(data.party.theme)`. `get_dashboard()` ya escucha `dashboard_state` en tiempo real y `admin_set_theme` lo toca, así que un cambio de tema llega solo, sin recargar, a la TV, a los celulares y al panel. Mientras carga, y en `#/owner`, se usa `fiesta`. Se guarda el último tema en localStorage para que no "parpadee" al abrir.
- **Selector de tema** en "🏠 Mi fiesta" (`src/pages/admin/Party.jsx`), arriba de los juegos: una grilla de 8 mini-cartas con la vista previa de cada tema (como los mockups aprobados), con la elegida marcada. También aparece un selector simple en el formulario de "Nueva fiesta" del dueño.
- `index.html`:
  - Cargar las fuentes Bricolage Grotesque y Nunito (Creepster se mantiene para Halloween; Outfit se quita).
  - Título genérico: "Juegos de fiesta".
  - Favicon neutro.
- Textos fijos de Halloween ("Fiesta de Halloween", 🎃 en la barra) pasan a usar el nombre de la fiesta y el ícono del tema.

### Emojis

Hay 482 emojis en 42 archivos.

- **Regla**: los emojis de "decoración de interfaz" se reemplazan por íconos Tabler. Eso incluye pestañas del panel, títulos de secciones, botones, estados vacíos, barra superior y spinners.
- Los emojis que **son contenido del juego** se quedan, porque son parte de la gracia. Por ejemplo: la carta de rol del Hombre Lobo, el emoji de cada juego en el catálogo y los regalos.
- El spinner 🎃 pasa a ser un ícono del tema girando.

## Etapas (cada una se publica sola y deja la app usable)

1. **Base y temas**: variables, los 8 temas, fuentes, componentes base (botón, carta, pill, input, pestañas, barra), `applyTheme`, SQL 13, selector en Mi fiesta y en el dueño. Al terminar, toda la app ya usa los colores nuevos aunque algunas pantallas aún no estén pulidas.
2. **Entrada y espera**: registro (`Join`), login de anfitrión, pantalla de espera o aprobación, inicio del invitado (`Home`), dueño (`Owner`).
3. **Juegos en el celular**, uno por uno: Disfraz, Códigos, Personaje, Impostor, Regalo, Hombre Lobo.
4. **TV** (`Dashboard` y los `*Board`, `CostumeReveal`, `FinalResults`) y el panel del anfitrión (`admin/*`).

## Verificación

- `npm run build` en cada etapa.
- En el navegador, recorrer cada pantalla tocada con al menos `fiesta`, `halloween` (oscuro) y `baby-nina`.
- En celular (375px): ningún tocable de menos de 44px de alto (la meta son 56px en acciones principales) y sin scroll horizontal.
- En la TV (1920×1080): ningún texto de menos de 18px.
- Cambiar el tema en Mi fiesta y ver que la TV y un celular abiertos cambian sin recargar.

## Lo que queda a criterio del builder

- Componentes exactos y cómo se reparte el CSS, siempre que todo color salga de las variables.
- Qué emoji es "contenido" y cuál es "decoración" en casos dudosos (aplicando la regla de arriba).
- Animaciones: pocas, rápidas y físicas (presionar, voltear carta, aparecer). Nada de brillos.

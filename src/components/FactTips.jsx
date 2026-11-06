import { useState } from 'react'

const EXAMPLES = [
  'Me quedé dormido en el cine… viendo una película de terror',
  'Aprendí a andar en bici a los 20 años',
  'Una vez me confundieron con un famoso en la calle',
  'Tengo una colección de más de 100 tazas',
  'Me caí en el escenario en mi graduación',
  'Gané un concurso de comer tacos',
  'Le tengo pánico a las mariposas',
  'Viví 3 meses en otro país sin hablar el idioma',
  'Me encerré afuera de mi casa en pijama',
  'Tuve una banda de rock que tocó una sola vez',
  'Me perdí en un aeropuerto y casi pierdo el vuelo',
  'Fui campeón de ajedrez en el colegio',
  'Sé recitar el abecedario al revés en 10 segundos',
  'Una vez saludé a alguien que no me estaba saludando… en pleno centro comercial',
]

function pick(n, exclude = []) {
  const pool = EXAMPLES.filter((e) => !exclude.includes(e))
  return [...pool].sort(() => Math.random() - 0.5).slice(0, n)
}

/**
 * Explicación + ideas para escribir un buen dato curioso.
 * Deja claro que NO es anónimo para siempre: al final de la ronda se revela de quién es.
 */
export default function FactTips() {
  const [examples, setExamples] = useState(() => pick(3))
  return (
    <div className="fact-tips">
      <p>Algo <b>gracioso o curioso</b> de ti que pocos sepan. Sale en pantalla sin tu nombre y, al final de la ronda, se revela que eres tú.</p>
      <p className="fact-bonus">🎁 Puntos extra si sale, <b>¡x2 si no te atrapan!</b></p>
      <p className="fact-warn">⚠️ Nada muy personal.</p>
      <div className="fact-examples">
        <span className="small muted">Ideas:</span>
        <ul>{examples.map((e) => <li key={e}>“{e}”</li>)}</ul>
        <button type="button" className="link-btn" onClick={() => setExamples(pick(3, examples))}>🔄 Otras ideas</button>
      </div>
    </div>
  )
}

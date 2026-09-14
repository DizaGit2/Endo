# -*- coding: utf-8 -*-
"""
Contenido en español del documento de revisión clínica para el especialista.
Fuente de verdad de los valores: clinical-signoff-pack.md (C-01 … C-16, PO-interim
2026-07-14). Aquí solo se traduce y se explica sin jerga técnica.

Convención de marcado: **texto** = negrita. Los bloques de `decision` pueden ser
str (párrafo), ("bullets", [...]), ("numbered", [...]),
("table", header, rows, anchos_cm, tamaño_fuente), ("note", texto) o ("quote", texto).
"""

META = {
    "title": "Revisión clínica para el especialista",
    "subtitle": "Dieciséis decisiones médicas que necesitan su validación antes de incorporarse a la aplicación",
    "for": "Especialista en ginecología / endocrinología reproductiva (los puntos C-09 y C-11 los revisará además un bioestadístico).",
    "from": "Carolina, responsable del producto Lumen, y el equipo de desarrollo.",
    "date": "21 de agosto de 2026",
    "version": "1.1 (primera ronda; el punto C-16 se añadió el 21 de agosto de 2026)",
    "status": "Las decisiones de este documento son **provisionales**: las fijó Carolina como punto de partida, "
              "apoyándose en guías clínicas publicadas. **Ninguna ha sido validada todavía por un médico.** "
              "Solo se incorporará a la aplicación lo que usted apruebe. **El punto C-16 es la excepción: no lleva "
              "decisión provisional, porque Carolina prefirió no inventar una respuesta a una pregunta clínica.**",
}

INTRO = [
    ("h", "Qué es Lumen, en pocas palabras"),
    ("p", "Lumen es una aplicación para el celular dirigida a personas con endometriosis. Permite anotar día a día "
          "cómo se sienten (dolor, sangrado, ánimo, energía, otros síntomas), llevar el calendario del ciclo menstrual, "
          "guardar los resultados de sus análisis hormonales, registrar la medicación que toman, el peso y la actividad "
          "física, y generar un informe ordenado para llevar a la consulta."),
    ("p", "**Lumen no diagnostica ni trata.** Ordena la información que la propia paciente anota y le muestra patrones de "
          "sus datos, siempre con la indicación de que se trata de orientación, no de consejo médico."),

    ("h", "Por qué necesitamos su ayuda"),
    ("p", "Para funcionar, la aplicación necesita una serie de definiciones médicas: cuántos días dura cada fase del ciclo, "
          "qué rango de estradiol se considera habitual en cada fase, qué medicamentos ofrecer en la lista, qué síntomas "
          "merecen un aviso de «consulte con su médico», entre otras. **El equipo que construye la aplicación no debe "
          "inventar esas definiciones.**"),
    ("p", "Carolina, responsable del producto, eligió valores provisionales basándose en guías y fuentes publicadas "
          "(FIGO, ACOG, ESHRE, NICE, ASRM, Mayo Clinic Laboratories, OMS). Le pedimos que los confirme, corrija o rechace "
          "con su criterio clínico. Lo que usted firme se incorporará a la aplicación con su nombre, la fecha y la fuente "
          "que indique; lo que no, se quedará fuera hasta resolverlo con usted."),

    ("h", "Cómo está organizado este documento y cómo responder"),
    ("p", "Hay **dieciséis puntos**, agrupados en cuatro bloques (A. el ciclo y sus fases; B. hormonas y análisis; "
          "C. lo que la aplicación calcula y muestra; D. población, catálogos y seguridad). Cada punto tiene la misma "
          "estructura:"),
    ("numbered", [
        "**Un título** que resume de qué se trata.",
        "**¿Para qué se usa en la app?** — dónde y cómo interviene ese dato en la aplicación.",
        "**Decisión provisional de Carolina** — el valor o la regla que se propone incorporar, y en qué se basa.",
        "**Pregunta para usted** — lo que necesitamos que responda.",
        "**Su respuesta** — marque «De acuerdo», «Modificar» (indicando el valor o la redacción que propone y, si "
        "puede, la fuente) o «No estoy de acuerdo»; añada comentarios y firme con fecha.",
    ]),
    ("p", "Puede escribir a mano sobre una copia impresa o completarlo en la computadora. Al final encontrará una "
          "tabla resumen y un espacio para la firma general. Si algún punto escapa a su especialidad, indíquelo y "
          "pase al siguiente."),

    ("h", "Tres reglas que ya están decididas (para tenerlas en cuenta)"),
    ("p", "Estas tres reglas son la base de todo lo demás. No le pedimos que las rediseñe, pero sí que nos avise si "
          "alguna le parece clínicamente inadecuada."),
    ("numbered", [
        "**Ningún límite impide anotar datos.** Los ciclos en la endometriosis son irregulares por naturaleza y muchas "
        "pacientes están en tratamientos que suprimen la menstruación (por ejemplo, dienogest) o directamente no "
        "menstrúan. Por eso, todos los rangos y límites de este documento sirven **únicamente** para decidir qué datos "
        "usa la aplicación en sus cálculos y con cuánta confianza muestra una predicción. La paciente siempre puede "
        "anotar cualquier valor. Si aun así considera que algún límite es inseguro, dígalo.",
        "**Los valores de referencia llevan fecha de vigencia.** Si en el futuro se corrige un rango (por ejemplo, el de "
        "una hormona), los análisis antiguos se siguen evaluando con el rango que estaba vigente en la fecha en que se "
        "hicieron. Una corrección nunca «reescribe» el historial de la paciente.",
        "**No hay inteligencia artificial que decida por su cuenta.** La aplicación aplica reglas fijas y transparentes "
        "—las de este documento— y todo lo que muestra es orientativo.",
    ]),

    ("callout", "Dónde le pedimos especial atención", [
        "**Seguridad de la paciente:** C-15 (avisos ante síntomas de alarma), C-06 (rangos hormonales), "
        "C-13 (dosis de medicamentos) y C-11 (redacción de los hallazgos sobre ánimo y ciclo).",
        "**Dos puntos en los que Carolina eligió algo distinto a lo que recomendaba la revisión bibliográfica** "
        "—su opinión es especialmente valiosa ahí—: C-03 (usa el promedio, y no la mediana, para calcular la duración "
        "habitual del ciclo) y C-02 (muestra una «ventana fértil» en el calendario).",
        "**Dos ampliaciones propuestas por Carolina que conviene confirmar:** los motivos para pausar el seguimiento "
        "del ciclo (C-12) y las categorías de medicamentos (C-13).",
    ]),
]

SECTIONS = [
    {"key": "A", "title": "Bloque A · El ciclo menstrual y sus fases",
     "intro": "Estos cinco puntos definen cómo la aplicación dibuja el calendario del ciclo, cómo estima la ovulación y "
              "la próxima menstruación, y cómo mide la regularidad. Son la base del calendario, de la pantalla de inicio "
              "y de las predicciones."},
    {"key": "B", "title": "Bloque B · Hormonas y análisis de laboratorio",
     "intro": "Estos tres puntos definen cómo la aplicación interpreta los resultados de laboratorio que la paciente "
              "guarda: con qué rangos los compara, en qué unidades los guarda y qué hace con el GLP-1."},
    {"key": "C", "title": "Bloque C · Lo que la aplicación calcula y muestra a partir de los datos",
     "intro": "Estos tres puntos definen el indicador de «datos suficientes», las tarjetas que animan a completar "
              "información y los «hallazgos» (patrones) que la aplicación muestra a la paciente y en el informe para "
              "el médico. Los puntos C-09 y C-11 los revisará además un bioestadístico; si la parte estadística escapa "
              "a su ámbito, céntrese en el contenido clínico."},
    {"key": "D", "title": "Bloque D · Población, catálogos y seguridad",
     "intro": "Estos cinco puntos definen a quién va dirigida la aplicación y qué pasa cuando no hay menstruación, la "
              "lista de medicamentos, el vocabulario de estadios, cirugías y síntomas, y —el más importante— los avisos "
              "de seguridad ante síntomas de alarma, y el mapa corporal."},
]

ITEMS = [
    # ------------------------------------------------------------------ A
    {
        "code": "C-01", "section": "A",
        "title": "Cómo se delimitan las cuatro fases del ciclo",
        "short": "Delimitación de las cuatro fases del ciclo",
        "tags": ["Calendario del ciclo", "Pantalla de inicio", "Detalle del día", "Gráfico hormonal"],
        "usage": [
            "El calendario del ciclo colorea cada día según la fase en que está la paciente: menstrual, folicular, "
            "ovulatoria o lútea. Ese mismo dato aparece en la pantalla de inicio («hoy estás en fase …»), en el detalle "
            "de cada día y en el informe para el médico.",
            "Además, la fase sirve para comparar cada análisis hormonal con el rango habitual de esa fase (punto C-06) "
            "y para agrupar los síntomas por fase en los hallazgos (punto C-11). La paciente puede corregir a mano la "
            "fase de un día si no coincide con su realidad.",
            "Estado actual: la aplicación ya registra las menstruaciones y tiene el calendario, pero **todavía no calcula "
            "las fases** (mientras tanto muestra «fases no disponibles»). El cálculo se construirá con las reglas que "
            "usted valide.",
        ],
        "decision": [
            "Las fases se calculan con reglas fijas a partir de dos datos que anota la paciente —el **primer día** y el "
            "**último día** de cada menstruación— y de un **día de ovulación estimado**. La ovulación se estima contando "
            "**14 días hacia atrás** desde el inicio previsto de la siguiente menstruación (se toma una fase lútea de "
            "14 días como ancla de cálculo).",
            ("table", ["Fase", "Empieza", "Termina"], [
                ["Menstrual", "Primer día de sangrado menstrual", "Último día de sangrado menstrual"],
                ["Folicular", "Día siguiente al fin del sangrado", "3 días antes de la ovulación estimada"],
                ["Ovulatoria", "2 días antes de la ovulación estimada", "1 día después de la ovulación estimada (banda de 4 días)"],
                ["Lútea", "2 días después de la ovulación estimada", "Día anterior a la siguiente menstruación"],
            ], [2.8, 6.6, 7.1]),
            "Si la ovulación **no puede estimarse** (historial irregular, menstruación suprimida o ausente), la aplicación "
            "solo marca la fase menstrual a partir del sangrado anotado y muestra las otras tres como «desconocidas», con "
            "confianza baja.",
            "Ejemplo con un ciclo de 28 días: ovulación estimada el día 15; la banda lútea visible dura unos 12 días (los "
            "14 días son el ancla de cálculo, no la duración que se muestra).",
        ],
        "sources": "Reed & Carr, «The Normal Menstrual Cycle» (Endotext, 2018); guías ACOG sobre métodos basados en el "
                   "conocimiento de la fertilidad; Wilcox, Weinberg & Baird (BMJ 2000 / NEJM 1995).",
        "question": [
            "¿Le parecen correctas estas reglas para delimitar las cuatro fases? En particular: **la fase lútea fija de "
            "14 días como ancla** y **la banda ovulatoria de 4 días** (de 2 días antes a 1 día después de la ovulación "
            "estimada). Si cambiaría alguna duración o algún límite, indique cuál y por qué.",
        ],
    },
    {
        "code": "C-02", "section": "A",
        "title": "Cómo se estima el día de ovulación y la «ventana fértil»",
        "short": "Estimación de la ovulación y ventana fértil",
        "tags": ["Calendario del ciclo", "Detalle del día", "Decisión de Carolina distinta a la recomendación"],
        "usage": [
            "El día de ovulación estimado determina dónde cae la fase ovulatoria en el calendario (punto C-01) y, por "
            "tanto, cómo se reparten las demás fases.",
            "Además, Carolina decidió que el calendario muestre, como capa informativa sombreada, una «ventana fértil». "
            "Se vería en el calendario del ciclo y en el detalle del día, siempre acompañada de un aviso de que no sirve "
            "para evitar ni para buscar un embarazo.",
            "Estado actual: hoy solo existe el interruptor «Mostrar ventana fértil» en los ajustes del ciclo (apagado por "
            "defecto). La estimación de la ovulación y la ventana se construirán con las reglas que usted valide.",
        ],
        "decision": [
            ("bullets", [
                "**Método:** la ovulación se estima **restando 14 días** a la fecha prevista de la próxima menstruación "
                "(y no «a la mitad del ciclo», que solo es correcto en ciclos de exactamente 28 días).",
                "**Fase ovulatoria mostrada:** ovulación ± 2 días.",
                "**Ventana fértil:** se dibuja desde **5 días antes de la ovulación hasta el día de la ovulación** (6 días), "
                "**solo a título informativo**, con el aviso obligatorio: «No sirve para prevenir el embarazo ni para "
                "programar la concepción».",
                "Si la aplicación no tiene suficiente confianza en el ciclo (punto C-03) o la paciente está en pausa o "
                "con la menstruación suprimida (punto C-12), la ventana se oculta o se ensancha; nunca impide anotar nada.",
            ]),
            ("note", "La revisión bibliográfica recomendaba **no** mostrar la ventana fértil: Lumen es una aplicación "
                     "de endometriosis, no de anticoncepción ni de fertilidad. Carolina decidió incluirla con el aviso "
                     "obligatorio. Su opinión sobre este punto es especialmente importante."),
        ],
        "sources": "ACOG, «Fertility Awareness-Based Methods»; Wilcox (BMJ 2000 / NEJM 1995); ASRM, «Optimizing Natural "
                   "Fertility» (2022).",
        "question": [
            "¿Es **aceptable mostrar una ventana fértil** a esta población (pacientes con endometriosis, muchas con ciclos "
            "irregulares o en tratamiento hormonal), teniendo en cuenta que los métodos basados en el conocimiento de la "
            "fertilidad tienen tasas de fallo relevantes en uso típico?",
            "Y, aparte de eso, ¿le parece correcto el **método de estimación** (14 días hacia atrás, banda de ± 2 días)?",
        ],
    },
    {
        "code": "C-03", "section": "A",
        "title": "Cómo se calcula la duración habitual del ciclo y de la menstruación",
        "short": "Duración habitual del ciclo y de la menstruación; límites",
        "tags": ["Calendario del ciclo", "Pantalla de inicio", "Ajustes del ciclo", "Decisión de Carolina distinta a la recomendación"],
        "usage": [
            "Con la duración habitual del ciclo la aplicación predice cuándo vendrá la próxima menstruación, sitúa las fases "
            "(punto C-01) y mide la regularidad (punto C-05). Se ve en el calendario, en la pantalla de inicio («próxima "
            "menstruación en unos X días») y en los ajustes del ciclo.",
            "Al crear la cuenta, la paciente indica cuánto le suele durar el ciclo y la menstruación. Cuando ya hay "
            "suficientes ciclos anotados, la aplicación pasa a usar su propio cálculo en lugar de ese dato inicial.",
            "Estado actual: la aplicación ya guarda lo que la paciente indica al crear la cuenta y muestra el aviso de "
            "«¿seguro?» ante valores extremos. El cálculo automático (promedio de 6 ciclos, límites 21–45 días) se "
            "construirá tras su validación.",
        ],
        "decision": [
            ("bullets", [
                "**Forma de calcular:** el **promedio (media)** de los **últimos 6 ciclos completos**, tanto para la duración "
                "del ciclo como para la de la menstruación.",
                "**Mínimo de datos:** hacen falta **al menos 3 ciclos completos** para que el cálculo reemplace al dato que "
                "dio la paciente al inicio.",
                "**Qué ciclos entran en el cálculo:** solo los ciclos de **21 a 45 días** y las menstruaciones de **1 a 10 "
                "días**. Los que quedan fuera se guardan y se muestran igual, pero no se usan para calcular (y reducen la "
                "confianza de la predicción).",
                "**Aviso por posible error al escribir** (nunca bloquea): si la paciente escribe un ciclo fuera de 10–120 "
                "días o una menstruación fuera de 1–30 días, la aplicación pregunta «¿seguro?», pero guarda el dato.",
            ]),
            ("note", "La revisión bibliográfica recomendaba usar la **mediana**, que resiste mejor los ciclos atípicos "
                     "(frecuentes en la endometriosis). Carolina eligió el **promedio**, con la mitigación de que solo "
                     "se promedian ciclos dentro de 21–45 días, de modo que los más extremos ya quedan excluidos."),
        ],
        "sources": "FIGO 2018 (Munro et al.: frecuencia normal 24–38 días, duración ≤ 8 días), ampliado hacia ACOG "
                   "(alrededor del 90 % de los ciclos dura entre 21 y 45 días); ESHRE 2022 para la irregularidad.",
        "question": [
            "Para esta población, ¿prefiere el **promedio** o la **mediana**?",
            "¿Le parecen adecuados los **límites de inclusión** (ciclo 21–45 días, menstruación 1–10 días), el mínimo de "
            "3 ciclos y la ventana de los últimos 6 ciclos? Indique cualquier cambio.",
        ],
    },
    {
        "code": "C-04", "section": "A",
        "title": "Qué cuenta como menstruación y qué como «manchado»; cómo detecta la aplicación el primer día",
        "short": "Menstruación vs. manchado; detección del primer día",
        "tags": ["Registro diario", "Calendario del ciclo", "Detalle del día"],
        "usage": [
            "Cada día la paciente puede anotar su sangrado en una escala de cuatro niveles. Con esa escala la aplicación "
            "decide automáticamente cuándo empieza una nueva menstruación (y, por tanto, un nuevo ciclo), sin que la "
            "paciente tenga que marcarlo expresamente. Se usa en el registro diario, en el calendario y en el detalle "
            "del día. La paciente siempre puede corregir a mano.",
            "Estado actual: la escala de cuatro niveles ya existe en la aplicación; la detección automática del primer "
            "día todavía no, y se construirá con la regla que usted valide.",
        ],
        "decision": [
            ("bullets", [
                "**Escala de sangrado:** 1 = manchado · 2 = ligero · 3 = moderado · 4 = abundante. **Manchado** = sangrado "
                "que no requiere protección sanitaria (definición FIGO 2018).",
                "**Qué cuenta como menstruación:** un día cuenta como sangrado menstrual si el nivel es **2 o más**. El "
                "manchado (nivel 1) por sí solo no cuenta.",
                "**Primer día de una nueva menstruación:** el primer día con nivel ≥ 2 que llega tras **al menos 3 días sin "
                "sangrado menstrual** (valor tolerante con la endometriosis; ajustable entre 2 y 3 días). El manchado de los "
                "días previos se considera manchado premenstrual, pero el «día 1» es el primer día con nivel ≥ 2.",
                "**Lo que nunca pasa:** el manchado nunca crea una menstruación por sí solo; en pacientes con la "
                "menstruación suprimida, el manchado intermenstrual no genera nada; **la corrección manual de la paciente "
                "siempre manda**.",
                "El nivel 4 (abundante) se asocia a las señales de sangrado menstrual abundante —empapar la protección en "
                "1–2 horas o coágulos de 2,5 cm o más— que se usan en los avisos de seguridad (punto C-15).",
            ]),
        ],
        "sources": "FIGO 2018 (Munro et al.); convenciones de registro de la aplicación Clue; gráfico PBAC de Higham (1990).",
        "question": [
            "¿Está de acuerdo con la **escala de cuatro niveles**, con que **el manchado no cuente como menstruación** y con "
            "la regla de **«3 días sin sangrado» para separar dos menstruaciones**? ¿Cambiaría algo?",
        ],
    },
    {
        "code": "C-05", "section": "A",
        "title": "Cómo se define si un ciclo es «regular» o «irregular», y qué efecto tiene",
        "short": "Definición de regularidad y su efecto en las predicciones",
        "tags": ["Calendario del ciclo", "Ajustes del ciclo", "Confianza de las predicciones"],
        "usage": [
            "La aplicación muestra una etiqueta de regularidad (en el calendario y en los ajustes del ciclo) y, sobre todo, "
            "la usa para decidir con **cuánta confianza** predice la próxima menstruación: cuanto más irregular es el "
            "ciclo, más amplio es el margen que se muestra («entre el 3 y el 17») y menor la confianza.",
            "Estado actual: hoy es la propia paciente quien indica, al crear la cuenta, si su ciclo es «regular», «algo "
            "irregular» o «irregular». El cálculo automático se construirá tras su validación.",
        ],
        "decision": [
            ("bullets", [
                "**Cómo se mide:** la diferencia entre el ciclo **más corto** y el **más largo** de los últimos 6 ciclos "
                "(mínimo 3 ciclos completos).",
                "**Tramos:** **Regular** si la diferencia es ≤ 7 días (criterio FIGO) · **Algo irregular** si es de 8 a 14 "
                "días (definido por el producto) · **Irregular** si es ≥ 15 días (definido por el producto).",
                "**Efecto sobre la predicción:** Regular → confianza completa, margen de ± 2 días · Algo irregular → "
                "confianza reducida (× 0,7), margen de ± 4 días · Irregular → confianza baja (× 0,4), margen de ± 7 días · "
                "Datos insuficientes o menstruación suprimida → no se predice una fecha, solo un rango.",
                "En esta primera versión se usa el umbral plano de 7 días para todas las edades (la graduación por edad "
                "de FIGO queda para más adelante). No se añade ningún mensaje «tranquilizador» a «algo irregular».",
            ]),
        ],
        "sources": "FIGO 2018 (regularidad = variación entre el ciclo más corto y el más largo, ≤ 7 días para 26–41 años); "
                   "ACOG, Committee Opinion 651. Los cortes de 8–14 / ≥ 15 días y los factores de confianza son una "
                   "decisión del producto, no de las guías.",
        "question": [
            "¿Le parecen razonables los **tres tramos** (≤ 7 / 8–14 / ≥ 15 días) y la forma en que **reducen la confianza y "
            "amplían el margen** de la predicción? ¿Propondría otros cortes u otra manera de expresarlo a la paciente?",
        ],
    },

    # ------------------------------------------------------------------ B
    {
        "code": "C-06", "section": "B",
        "title": "Rangos de referencia hormonales por fase del ciclo",
        "short": "Rangos de referencia hormonales",
        "tags": ["Gráfico hormonal", "Detalle de cada hormona", "Confirmación de un análisis", "Seguridad"],
        "usage": [
            "La paciente puede guardar los resultados de sus análisis hormonales (escribiéndolos o fotografiando el "
            "informe del laboratorio). La aplicación los muestra en un gráfico por fecha y por fase, y señala si cada "
            "valor está dentro o fuera del rango habitual **para la fase del ciclo en que se hizo el análisis**.",
            "Si la fase es desconocida o la menstruación está suprimida, no se aplica ningún rango. Un valor fuera de "
            "rango nunca impide guardarlo: solo se marca y no se usa en los cálculos de confianza.",
            "Estado actual: pendiente de construir; estos rangos se incorporarán cuando usted los valide.",
        ],
        "decision": [
            "Usar como fuente de referencia los rangos de **Mayo Clinic Laboratories** (dependen del método de análisis "
            "de cada laboratorio), por fase:",
            ("table", ["Hormona", "Fase o condición", "Desde", "Hasta", "Unidad"], [
                ["Estradiol", "Menstrual / folicular temprana", "25", "120", "pg/mL"],
                ["Estradiol", "Folicular", "25", "120", "pg/mL"],
                ["Estradiol", "Ovulatoria (pico de mitad de ciclo)", "30", "520", "pg/mL"],
                ["Estradiol", "Lútea", "35", "250", "pg/mL"],
                ["Progesterona", "Folicular", "0", "0,89", "ng/mL"],
                ["Progesterona", "Lútea", "1,8", "24", "ng/mL"],
                ["LH", "Folicular", "1,8", "11,8", "mUI/mL"],
                ["LH", "Pico de mitad de ciclo", "7,6", "89,1", "mUI/mL"],
                ["LH", "Lútea", "0,6", "14,0", "mUI/mL"],
                ["FSH", "Folicular", "3,03", "8,08", "mUI/mL"],
                ["FSH", "Pico de mitad de ciclo", "2,55", "16,69", "mUI/mL"],
                ["FSH", "Lútea", "1,38", "5,47", "mUI/mL"],
                ["Testosterona (total)", "Cualquier fase (mujer ≥ 19 años)", "8", "60", "ng/dL"],
                ["Cortisol", "Mañana (7–9 h)", "7", "25", "µg/dL"],
                ["Cortisol", "Tarde (15–17 h)", "2", "14", "µg/dL"],
                ["GLP-1", "Sin rango de referencia (ver punto C-08)", "—", "—", "pmol/L"],
            ], [3.6, 5.6, 2.3, 2.3, 2.1], 9),
            "El límite inferior del estradiol en las fases bajas se fija en 25 pg/mL (umbral de detección del inmunoensayo). "
            "En esta primera versión solo se maneja la testosterona **total** (la libre y la biodisponible quedan para "
            "más adelante).",
        ],
        "sources": "Catálogo de pruebas de Mayo Clinic Laboratories (estradiol, progesterona, LH, FSH, testosterona, "
                   "cortisol), 2025.",
        "question": [
            "¿**Confirma cada uno de estos rangos**, o prefiere anotar los de su laboratorio de referencia? Si hay alguna "
            "hormona o fase cuyo rango le parezca inadecuado para pacientes con endometriosis (o para pacientes en "
            "tratamiento hormonal), indíquelo junto con el valor que propone.",
        ],
    },
    {
        "code": "C-07", "section": "B",
        "title": "Unidades de medida aceptadas y conversiones entre ellas",
        "short": "Unidades aceptadas y conversiones",
        "tags": ["Carga de análisis", "Gráfico hormonal"],
        "usage": [
            "Los informes de laboratorio expresan las hormonas en unidades distintas según el país y el laboratorio (por "
            "ejemplo, estradiol en pg/mL o en pmol/L). Para que el gráfico sea comparable, la aplicación convierte cada "
            "valor a una unidad única por hormona, y guarda también el valor y la unidad originales tal como venían.",
            "Si la aplicación no reconoce una unidad, guarda el valor igualmente, lo marca como «unidad no reconocida» y "
            "simplemente no lo usa en los cálculos.",
            "Estado actual: pendiente de construir; se incorporará cuando usted lo valide.",
        ],
        "decision": [
            ("table", ["Hormona", "Unidad en la que se guarda", "Otras unidades que se aceptan y cómo se convierten"], [
                ["Estradiol", "pg/mL", "pmol/L × 0,2724; ng/L × 1"],
                ["Progesterona", "ng/mL", "nmol/L × 0,3145; µg/L × 1"],
                ["LH", "UI/L", "mUI/mL × 1 (son equivalentes)"],
                ["FSH", "UI/L", "mUI/mL × 1 (son equivalentes)"],
                ["Testosterona", "ng/dL", "nmol/L × 28,84; ng/mL × 100"],
                ["Cortisol", "µg/dL", "nmol/L × 0,03625"],
                ["GLP-1", "pmol/L", "pg/mL × 0,3032"],
            ], [3.2, 4.3, 9.0], 9.5),
            "Los factores se derivan del peso molecular de cada hormona (para LH y FSH, de la unidad internacional de la "
            "OMS). Se aceptan escrituras alternativas habituales («mcg», «ug», mayúsculas/minúsculas).",
        ],
        "sources": "AMA Manual of Style, 11.ª ed., §18; pesos moleculares de PubChem; estándares internacionales de la "
                   "OMS para LH y FSH.",
        "question": [
            "¿Son estas las **unidades que ve habitualmente** en los informes de sus pacientes? ¿**Falta alguna unidad** de "
            "uso frecuente en su país, o detecta algún **factor de conversión incorrecto**?",
        ],
    },
    {
        "code": "C-08", "section": "B",
        "title": "Qué hacer con el GLP-1",
        "short": "GLP-1: solo informativo, sin rango",
        "tags": ["Gráfico hormonal", "Registro de medicación"],
        "usage": [
            "El diseño original de la aplicación contemplaba el GLP-1 (una hormona intestinal) entre las hormonas que se "
            "pueden registrar. La pregunta es si debe tratarse como las demás —con rango de referencia, marca de alto/bajo "
            "y participación en los cálculos— o no.",
            "Estado actual: la paciente ya puede marcar el GLP-1 entre las hormonas que quiere seguir; el gráfico "
            "hormonal aún no está construido, así que la decisión se aplicará entonces.",
        ],
        "decision": [
            ("bullets", [
                "**Posponer** el GLP-1 como hormona con rango de referencia: no forma parte de los paneles habituales, no "
                "existe un rango de referencia validado, la extracción requiere condiciones especiales y no tiene una "
                "interpretación establecida en endometriosis.",
                "Si una paciente lo anota de todos modos, la aplicación **muestra el valor tal cual**, con la nota «sin rango "
                "de referencia estandarizado», sin marcarlo como alto o bajo y sin usarlo en ningún cálculo. Si alguna vez "
                "se guarda, la unidad será pmol/L (forma activa/intacta).",
                "Los **medicamentos** agonistas de GLP-1 (semaglutida, liraglutida, etc.) se registran en el apartado de "
                "medicación (punto C-13), no en el gráfico hormonal.",
                "Se reconsiderará solo si un clínico define un uso concreto en endometriosis **y** un laboratorio de "
                "referencia publica un método estandarizado con rango validado.",
            ]),
        ],
        "sources": "Bak et al. (Diabetes, Obesity and Metabolism, 2014); clasificación ATC/DDD de la OMS (A10BJ); ausencia "
                   "de una prueba de GLP-1 solicitable en Mayo, LabCorp o Quest.",
        "question": [
            "¿Está de acuerdo en dejar el GLP-1 **solo como dato informativo, sin rango**? ¿Conoce algún uso clínico del GLP-1 "
            "endógeno en endometriosis que justifique tratarlo de otra manera?",
        ],
    },

    # ------------------------------------------------------------------ C
    {
        "code": "C-09", "section": "C",
        "title": "El indicador de «cuán completos están sus datos» (0 a 100)",
        "short": "Indicador de datos completos (0–100)",
        "tags": ["Pantalla de inicio", "Pantalla que explica la confianza", "Informes", "Revisa también un bioestadístico"],
        "usage": [
            "La aplicación muestra a la paciente un número de 0 a 100 que expresa **cuántos datos tiene** para poder "
            "orientarla. No es una probabilidad ni una medida clínica: es una forma de decirle «con esto que has anotado, "
            "puedo afinar más o menos». Aparece en la pantalla de inicio, en la pantalla que explica la confianza de las "
            "predicciones y en los informes.",
            "Por debajo de cierto nivel, la aplicación deja de indicar una fase concreta y muestra solo un rango.",
            "Estado actual: pendiente de construir.",
        ],
        "decision": [
            "Suma de cuatro componentes, cada uno con un máximo:",
            ("table", ["Componente", "Puntos máximos", "Cómo se reparten"], [
                ["Análisis hormonales en las cuatro fases", "40", "10 puntos por cada fase que tenga al menos un análisis confirmado"],
                ["Historial de ciclos completos", "30", "0 / 8 / 15 / 22 / 26 / 28 / 30 puntos para 0, 1, 2, 3, 4, 5 y 6 o más ciclos"],
                ["Registros diarios (últimos 28 días)", "20", "Proporcional al número de días con registro, hasta 28"],
                ["Puntos marcados en el mapa corporal", "10", "2 puntos por cada punto marcado, hasta 5"],
            ], [5.8, 2.6, 8.1], 9.5),
            ("bullets", [
                "**Tramos que ve la paciente:** Bajo 0–39 · Medio 40–69 · Alto 70–100.",
                "Con **menos de 20 puntos** no se muestra una fase concreta, solo un rango.",
                "**Pacientes con la menstruación suprimida:** se les perdona el componente de historial de ciclos (30 puntos) "
                "y el resto se reescala para que el máximo siga siendo 100.",
                "Se llama «datos completos» a propósito, y no «confianza de la predicción», porque **no** es un instrumento "
                "validado: los pesos son un criterio de producto informado por la literatura. No incluye la regularidad del "
                "ciclo (eso se trata aparte, en el punto C-05).",
            ]),
        ],
        "sources": "Clue (umbral de 3 ciclos para predecir); Bull et al., npj Digital Medicine 2019; Li et al., "
                   "JAMIA 2022;29(1):3–11.",
        "question": [
            "¿Le parece razonable el **peso relativo** de cada componente (40 / 30 / 20 / 10) y que **no se tenga en cuenta la "
            "regularidad** del ciclo? Si cambiaría algún peso o algún tramo, indique cuál.",
        ],
    },
    {
        "code": "C-10", "section": "C",
        "title": "Las tarjetas que animan a completar información",
        "short": "Tarjetas de «te falta información»",
        "tags": ["Pantalla de inicio", "Pantalla que explica la confianza"],
        "usage": [
            "Cuando faltan datos, la pantalla de inicio muestra una tarjeta (solo una cada vez) que invita a la paciente a "
            "completar algo: hacer el registro diario, anotar más ciclos, usar el mapa corporal o añadir un análisis de una "
            "fase que falta. Cada tarjeta se puede posponer («quizás más tarde»: desaparece 7 días).",
            "Estado actual: pendiente de construir.",
        ],
        "decision": [
            "Cuatro tarjetas, en este orden de prioridad (primero lo más básico y lo que menos esfuerzo cuesta):",
            ("numbered", [
                "**«Prueba un registro diario»** — si hay menos de 3 registros en los últimos 14 días. Texto: «Un registro "
                "diario rápido —cómo te sientes, tu energía, cualquier síntoma— ayuda a Lumen a aprender tus patrones con el "
                "tiempo. Solo toma un momento.»",
                "**«Sigue anotando tus ciclos»** — si hay menos de 3 ciclos confirmados. Texto: «Cada ciclo es distinto. "
                "Anotar algunos ciclos ayuda a Lumen a aprender tu ritmo y a ajustar sus predicciones a ti.»",
                "**«Marca dónde lo sientes»** — si no hay ningún punto en el mapa corporal. Texto: «Marcar dónde aparecen los "
                "síntomas añade detalle a tu panorama y puede hacer más claros tus patrones e informes.»",
                "**«Afina tu panorama hormonal»** — si faltan fases con análisis. Texto: «Lumen aprende tus hormonas fase por "
                "fase. Añadir un estudio de cada fase ayuda a que tus predicciones sean más precisas.»",
            ]),
            ("bullets", [
                "Redacción en lenguaje llano y alentadora; **nunca presenta la irregularidad como un problema** ni hace "
                "afirmaciones sobre la salud.",
                "Las tarjetas de ciclos y de análisis **no se muestran** si el seguimiento del ciclo está en pausa (punto "
                "C-12) o si la paciente tiene anotado un medicamento que suprime la menstruación.",
            ]),
            ("note", "Los textos son una traducción del original en inglés; la redacción final de cada idioma se ajustará, "
                     "pero el contenido y el tono son los que se someten a su revisión."),
        ],
        "sources": "Tono de los textos: CDC Clear Communication Index; estándar de contenidos del NHS. Los umbrales vienen de "
                   "los puntos C-03 y C-09.",
        "question": [
            "¿Ve algún **riesgo clínico** en estos mensajes (por ejemplo, que presionen a la paciente, que den a entender algo "
            "erróneo o que resulten inadecuados para alguien con la menstruación suprimida)? ¿Cambiaría el orden o la "
            "redacción de alguno?",
        ],
    },
    {
        "code": "C-11", "section": "C",
        "title": "Los «hallazgos»: qué patrones se muestran, con qué mínimos y cómo se redactan",
        "short": "Hallazgos: definición de dolor, mínimos y redacción",
        "tags": ["Hallazgos", "Informe para el médico", "Seguridad", "Revisa también un bioestadístico"],
        "usage": [
            "En la sección «Hallazgos», la aplicación muestra a la paciente patrones de **sus propios datos**: en qué momento "
            "del ciclo suele ser peor el dolor, el dolor promedio por fase, la relación entre actividad física y dolor al "
            "día siguiente, y la relación entre ánimo bajo y fase del ciclo. Estos textos van también al informe para el "
            "médico. Siempre se presentan como asociaciones, nunca como causas.",
            "Estado actual: la escala de dolor de 0 a 10 y el vocabulario de síntomas ya existen en la aplicación; los "
            "hallazgos se construirán tras su validación.",
        ],
        "decision": [
            ("bullets", [
                "**Qué se entiende por «dolor»:** el valor **máximo del día**, en una escala de 0 a 10, entre los dolores "
                "propios de la endometriosis: dismenorrea, dolor pélvico no menstrual, dispareunia profunda y superficial, "
                "disquecia y dolor lumbar. **No** se incluyen náuseas, fatiga, ánimo, hinchazón ni cefalea.",
                "**Mínimos para mostrar un hallazgo:** al menos 10 días con datos emparejados (preferiblemente 20) y una "
                "asociación de cierta magnitud (correlación de Spearman de 0,30 o más, que es un mínimo para filtrar ruido, "
                "no un umbral de relevancia clínica; o una diferencia de alrededor del 15 % entre grupos). **Nunca se "
                "muestran valores p.**",
                "**Redacción obligatoria no causal:** se permite «se asocia con», «se relaciona con», «tiende a»; se prohíbe "
                "«causa», «reduce», «mejora», «previene». Pie fijo en todos los hallazgos: «Patrones en tus propios datos: "
                "asociaciones, no consejo médico ni prueba de causa.»",
            ]),
            "Los cuatro hallazgos previstos:",
            ("table", ["Hallazgo", "Qué muestra", "Mínimos"], [
                ["Pico de dolor", "En qué día respecto al inicio de la menstruación suele alcanzar el máximo el dolor "
                                  "(«En tus registros, el dolor ha tendido a alcanzar su punto máximo unos N días antes de tu "
                                  "periodo, en el X % de los ciclos»)", "3 ciclos con dolor anotado; se repite en al menos el 60 % de ellos"],
                ["Dolor por fase", "Dolor promedio en cada fase del ciclo", "3 días con dolor en cada fase"],
                ["Actividad y dolor", "Compara el dolor del día siguiente tras días con 30 minutos o más de actividad, frente "
                                      "a días con menos (los 30 minutos son un umbral ilustrativo, no una «dosis»)", "10 días; 5 en cada grupo"],
                ["Ánimo y ciclo", "Porcentaje de días con ánimo bajo en cada fase. Se eliminó el corte de «estradiol < 120 pg/mL» "
                                  "que había en el diseño original. Solo para pacientes sin supresión. El mecanismo del "
                                  "estrógeno se explica en una pantalla aparte, no en el titular.", "3 ciclos con ánimo anotado; 3 días válidos por fase"],
            ], [2.8, 9.2, 4.5], 9),
        ],
        "sources": "Schober 2018 (uso de Spearman); Haber et al., AJE 2022, y FTC 2023 (límites al lenguaje causal); "
                   "escalas de dolor ESHRE/ASRM; Schmidt, JAMA Psychiatry 2015 (caída del estrógeno, no nivel absoluto).",
        "question": [
            "¿Le parece correcta la **definición de «dolor»** (máximo diario de los dolores propios de la endometriosis, "
            "excluyendo náuseas, fatiga, ánimo, hinchazón y cefalea)?",
            "¿La **redacción no causal** le parece suficiente para que la paciente no saque conclusiones indebidas? "
            "¿Ve algún riesgo en mostrar «ánimo y ciclo» sin mencionar el estrógeno en el titular?",
            "(Los mínimos estadísticos los revisará además un bioestadístico; si desea opinar sobre ellos, es bienvenido.)",
        ],
    },

    # ------------------------------------------------------------------ D
    {
        "code": "C-12", "section": "D",
        "title": "A quién va dirigida la aplicación, y qué pasa cuando no hay menstruación",
        "short": "Población objetivo y pausa del seguimiento del ciclo",
        "tags": ["Creación de la cuenta", "Ajustes del ciclo", "Calendario del ciclo", "Ampliación de Carolina"],
        "usage": [
            "Al crear la cuenta, la aplicación pregunta por la última menstruación. Pero muchas pacientes con endometriosis "
            "no menstrúan: por el tratamiento (dienogest, DIU hormonal, análogos), por un embarazo, por una cirugía o por la "
            "menopausia. Para ellas hay un camino alternativo al crear la cuenta y un botón de **«pausar el seguimiento del "
            "ciclo»**, visible en los ajustes del ciclo y en el calendario.",
            "Mientras el seguimiento está en pausa, el calendario no muestra fases («fases no disponibles») y esos periodos "
            "no entran en ningún cálculo; la paciente puede seguir anotando todo lo demás.",
            "Estado actual: la pausa con estos cinco motivos y la reanudación libre **ya están construidas**; la regla de "
            "seguridad sobre el embarazo se aplicará al construir la interpretación hormonal, y el camino alternativo al "
            "crear la cuenta está previsto. Si usted pide cambios, se ajustará.",
        ],
        "decision": [
            ("bullets", [
                "**Población objetivo:** personas que menstrúan, en edad reproductiva. Es un **objetivo de diseño**, no un "
                "filtro de entrada: la aplicación no rechaza a nadie por edad (cualquier edad mínima es una decisión legal "
                "aparte), no hay límite superior de edad y el enfoque es inclusivo en cuanto al género.",
                "**Un único mecanismo de pausa**, con un motivo a elegir: **embarazo · supresión hormonal · cirugía · "
                "menopausia · otro** (esta lista de motivos es una ampliación propuesta por Carolina).",
                "**Reanudar** el seguimiento es siempre posible y lo decide la paciente, **sea cual sea el motivo** (decisión "
                "de Carolina). Al reanudar, empieza un ciclo nuevo desde cero (no se «empalma» con el anterior).",
                "La aplicación puede **sugerir** la pausa (por ejemplo, si lleva mucho tiempo sin menstruación anotada), pero "
                "**nunca la activa por su cuenta**.",
                "Durante la pausa se puede seguir anotando todo, incluido el manchado.",
                "**Regla de seguridad:** si el motivo es **embarazo**, la aplicación deja de interpretar los rangos hormonales "
                "por completo (los análisis se pueden seguir guardando); **no** se sustituyen por rangos de no embarazada.",
            ]),
        ],
        "sources": "ESHRE 2022 y NICE NG73 (el tratamiento hormonal de primera línea suprime la ovulación y la menstruación); "
                   "cohorte con dienogest ENVISIOeN (Reproductive Sciences 2022: amenorrea del 3,5 % al 70,8 % a los 24 "
                   "meses); OMS / ACOG sobre menopausia.",
        "question": [
            "¿La **lista de motivos de pausa** (embarazo, supresión hormonal, cirugía, menopausia, otro) es completa y correcta?",
            "¿Está de acuerdo con que la paciente pueda **reanudar el seguimiento en cualquier momento**, incluso tras una "
            "histerectomía o en la menopausia? ¿Y con **desactivar la interpretación hormonal durante el embarazo**?",
        ],
    },
    {
        "code": "C-13", "section": "D",
        "title": "Lista inicial de medicamentos para endometriosis, con dosis orientativas",
        "short": "Lista de medicamentos y dosis típicas",
        "tags": ["Registro de medicación", "Seguridad", "Ampliación de Carolina"],
        "usage": [
            "En el registro de medicación, la paciente elige su tratamiento de una lista y anota cuándo lo toma. Siempre "
            "puede escribir «otro» a mano. La dosis que aparece junto a cada medicamento es **orientativa** —sirve para "
            "reconocerlo y seleccionarlo más rápido— y **nunca una recomendación**.",
            "Algunos de estos medicamentos (los que suprimen la menstruación) además le indican a la aplicación que no "
            "debe esperar ciclos (puntos C-10 y C-12).",
            "Estado actual: pendiente de construir; la lista se incorporará cuando usted la valide.",
        ],
        "decision": [
            ("table", ["Medicamento", "Forma", "Dosis típica (orientativa)", "Categoría"], [
                ["Dienogest", "comprimido", "2 mg una vez al día, continuo", "hormonal"],
                ["Anticonceptivo combinado (levonorgestrel + etinilestradiol)", "comprimido", "EE 20–35 µg + LNG 100–150 µg al día; a menudo continuo", "hormonal"],
                ["Acetato de noretisterona", "comprimido", "5 mg/día (2,5–15)", "hormonal"],
                ["Acetato de medroxiprogesterona", "comprimido / depot", "oral 10 mg 1–3 veces al día; depot 104 mg SC o 150 mg IM cada 3 meses", "hormonal"],
                ["DIU de levonorgestrel (SIU-LNG)", "DIU", "52 mg, ~20 µg/día, hasta 5–8 años", "hormonal"],
                ["Leuprorelina (leuprolida)", "inyección depot", "3,75 mg mensual / 11,25 mg cada 3 meses; **≤ 6 meses sin terapia de reemplazo (add-back)**", "hormonal"],
                ["Goserelina", "implante SC", "3,6 mg mensual / 10,8 mg cada 3 meses; **≤ 6 meses sin add-back**", "hormonal"],
                ["Elagolix", "comprimido", "150 mg una vez al día, o 200 mg dos veces al día (**≤ 6 meses**)", "hormonal"],
                ["Relugolix combinado", "comprimido", "relugolix 40 mg + estradiol 1 mg + NETA 0,5 mg, un comprimido al día", "hormonal"],
                ["Danazol", "cápsula", "200–800 mg/día repartidos (efectos androgénicos; poco usado)", "hormonal"],
                ["Letrozol", "comprimido", "2,5 mg una vez al día (fuera de indicación; habitualmente con progestina o anticonceptivo)", "hormonal"],
                ["Píldora de solo drospirenona", "comprimido", "4 mg una vez al día (24/4 o continuo)", "hormonal"],
                ["Naproxeno", "comprimido", "250–500 mg dos veces al día (máx. ~1000–1250 mg/día)", "dolor"],
                ["Ibuprofeno", "comprimido", "400 mg cada 6–8 h (máx. 1200 sin receta; con receta ~2400–3200, según el país)", "dolor"],
                ["Paracetamol", "comprimido", "500–1000 mg cada 4–6 h (máx. 3–4 g/día)", "dolor"],
                ["Ácido tranexámico", "comprimido", "1–1,3 g tres veces al día durante la menstruación (≤ ~4 días por ciclo)", "sangrado"],
                ["Omega-3 (EPA + DHA)", "cápsula", "~1–2 g/día", "suplemento"],
                ["Vitamina D3 (colecalciferol)", "comprimido / gotas", "800–2000 UI/día", "suplemento"],
                ["Magnesio", "comprimido", "~200–400 mg de magnesio elemental/día", "suplemento"],
                ["Semaglutida", "inyección / comprimido", "según el producto", "metabólico"],
                ["Dulaglutida", "inyección", "según el producto", "metabólico"],
                ["Liraglutida", "inyección", "según el producto", "metabólico"],
                ["Exenatida", "inyección", "según el producto", "metabólico"],
                ["Lixisenatida", "inyección", "según el producto", "metabólico"],
                ["Tirzepatida", "inyección", "según el producto", "metabólico"],
            ], [4.6, 2.6, 7.0, 2.3], 8.5),
            ("bullets", [
                "**Categorías:** hormonal · dolor · suplemento · **sangrado** · **metabólico** (las dos últimas son una "
                "ampliación propuesta por Carolina).",
                "Los agonistas de GLP-1 se incluyen en la lista por la decisión del punto C-08. Cada medicamento lleva su "
                "código ATC de la OMS, verificado.",
            ]),
        ],
        "sources": "Índice ATC/DDD de la OMS (2025/26); ESHRE 2022; NICE NG73 y NG88; fichas técnicas (Visanne, Lupron, "
                   "Orilissa, Ryeqo).",
        "question": [
            "¿Son correctos los **nombres y las dosis típicas**? ¿**Falta algún medicamento** que use con frecuencia en su "
            "práctica, o **sobra alguno**? ¿Le parecen bien las **cinco categorías**?",
        ],
    },
    {
        "code": "C-14", "section": "D",
        "title": "Estadios de la endometriosis, lista de cirugías y vocabulario de síntomas",
        "short": "Estadios, cirugías y vocabulario de síntomas",
        "tags": ["Perfil de la paciente", "Informe para el médico", "Formulario de síntomas"],
        "usage": [
            "En su perfil, la paciente puede indicar —si lo sabe— el estadio de su endometriosis y las cirugías que ha "
            "tenido; esos datos van al informe para el médico. La aplicación no los deduce ni los usa para alarmar "
            "(nunca dice «estadio alto = peor»).",
            "También se revisó el vocabulario de síntomas y desencadenantes que la paciente puede anotar en el registro "
            "diario y en el formulario de síntomas.",
            "Estado actual: el estadio (I–IV, opcional) y el vocabulario de síntomas ya están en la aplicación; la lista "
            "de cirugías se construirá más adelante.",
        ],
        "decision": [
            ("bullets", [
                "**Estadios rASRM I–IV:** I mínima (1–5 puntos) · II leve (6–15) · III moderada (16–40) · IV severa "
                "(más de 40). Lo introduce la paciente, es **opcional**, la aplicación **nunca lo deduce** y **no lo relaciona "
                "con el dolor**. La clasificación #Enzian queda para una versión futura (por ahora, texto libre opcional).",
                "**Lista de cirugías** (se pueden marcar varias, más «otra»): laparoscopia diagnóstica · escisión · "
                "ablación/fulguración · quistectomía de endometrioma · adhesiólisis · histerectomía · ooforectomía · "
                "resección intestinal · ureterólisis. Se mantienen separadas «escisión» y «ablación». La vía de abordaje "
                "(laparoscópica, abierta, robótica) queda para más adelante.",
                "**Vocabulario de síntomas:** se **mantiene «dolor en pecho u hombro»** (la endometriosis torácica o "
                "diafragmática existe); se usa **«ánimo bajo»** en lugar de «depresión» (no es un cribado); los "
                "desencadenantes (esfuerzo físico, mal sueño, clima) se tratan como coincidencias, nunca como causas; "
                "**«sangrado menstrual abundante»** es una casilla independiente (término FIGO) que no se duplica con el "
                "nivel 4 de la escala de sangrado, y su umbral de alarma se define junto con el punto C-15.",
            ]),
        ],
        "sources": "Clasificación revisada de la ASRM (1996/1997, Fertility and Sterility 67:817–21); ESHRE 2022; "
                   "Keckstein, #Enzian 2021; FIGO 2018; literatura sobre endometriosis torácica (Nezhat 2024).",
        "question": [
            "¿Son correctos los **estadios** y la **lista de cirugías**? ¿Falta algún procedimiento o síntoma habitual en su "
            "práctica? ¿Está de acuerdo con usar **«ánimo bajo»** y con mantener **«dolor en pecho u hombro»**?",
        ],
    },
    {
        "code": "C-15", "section": "D",
        "title": "Avisos ante síntomas de alarma",
        "short": "Avisos de seguridad ante síntomas de alarma",
        "tags": ["Registro diario", "Formulario de síntomas", "SEGURIDAD — lo revisa también el equipo legal"],
        "usage": [
            "Si la paciente anota ciertos síntomas, la aplicación muestra, **después de guardar**, una nota breve y en tono "
            "calmado que le sugiere consultar. No bloquea nada, no diagnostica, no nombra ninguna enfermedad, se puede "
            "cerrar y aparece como máximo una vez por cada anotación que la dispare. Ocurre en el registro diario y en el "
            "formulario de síntomas.",
            "Estado actual: no está construido; se construirá solo cuando usted y el equipo legal lo validen.",
        ],
        "decision": [
            "**Pie fijo** que acompaña a todos los avisos (texto literal):",
            ("quote", "«Lumen no es un servicio médico ni de emergencias y no puede evaluar tus síntomas. Si estás "
                      "preocupada, contacta a tu médico o a un servicio de urgencias; y si parece una emergencia, llama de "
                      "inmediato al número de emergencias de tu zona.»"),
            "**Las seis situaciones que disparan el aviso, y el texto de cada una:**",
            ("numbered", [
                "**Dolor en el máximo de la escala (10 de 10):** «Anotaste un dolor en lo más alto de la escala. Un dolor tan "
                "intenso —sobre todo si es repentino o el peor que hayas sentido— merece una revisión pronto.»",
                "**Sangrado muy abundante** (el nivel máximo de la escala, o empapar una toalla o tampón por hora durante 2 "
                "horas o más, o coágulos más grandes que una moneda, ≈ 2,5 cm): «Anotaste un sangrado muy abundante. Empapar "
                "una toalla o tampón cada hora durante un par de horas seguidas, o expulsar coágulos más grandes que una "
                "moneda, merece una revisión.»",
                "**Fiebre de 38,0 °C o más junto con dolor pélvico:** «Anotaste fiebre junto con dolor pélvico. Esa combinación "
                "merece una revisión pronto.»",
                "**Desmayo o sensación de desmayo:** «Anotaste sensación de desmayo o pérdida de conocimiento. Merece una "
                "revisión, sobre todo si va acompañado de dolor o de sangrado abundante.»",
                "**Dolor intenso cuando no se ha descartado un embarazo:** «Anotaste dolor intenso y existe la posibilidad de "
                "que estés embarazada. Si lo estás, un dolor repentino o de un solo lado puede ser una emergencia y debe "
                "revisarse con urgencia.»",
                "**No poder orinar o evacuar:** «Anotaste que no puedes orinar (o evacuar). Esto puede ser grave; por favor, "
                "hazlo revisar de inmediato.»",
            ]),
            ("bullets", [
                "La fiebre dispara el aviso desde **38,0 °C** (el marcador de urgencia de la enfermedad inflamatoria pélvica "
                "es 38,3 °C; se eligió el umbral más bajo a propósito).",
                "El tamaño de coágulo «≈ 2,5 cm» se mantiene en todos los idiomas.",
            ]),
            ("note", "Los textos son una traducción del original en inglés; la redacción final de cada idioma se ajustará, "
                     "pero **las situaciones, los umbrales y el tono** son los que se someten a su revisión."),
        ],
        "sources": "ACOG (sangrado menstrual abundante, sangrado uterino anormal, enfermedad inflamatoria pélvica); NHS y "
                   "Mayo Clinic (embarazo ectópico); NIDDK (retención urinaria); Mayo Clinic (obstrucción intestinal); "
                   "NICE NG12 y BJGP (safety-netting).",
        "question": [
            "¿Son estas **seis situaciones** las correctas, y sus **umbrales** adecuados (por ejemplo, fiebre desde 38,0 °C, "
            "coágulos de 2,5 cm o más)?",
            "¿**Falta alguna situación de alarma** que, a su juicio, deba avisarse (o sobra alguna)?",
            "¿La **redacción** le parece lo bastante clara y prudente: ni alarmista ni tranquilizadora en exceso?",
        ],
    },
    {
        "code": "C-16", "section": "D",
        "title": "Mapa corporal: ¿cada zona va en la vista de frente, en la de espalda, o en ambas?",
        "short": "Mapa corporal: frente / espalda",
        "tags": ["Formulario de síntomas", "Mapa corporal", "Informe para el médico"],
        "decision_label": "Aquí NO hay decisión provisional de Carolina",
        "usage": [
            "En la pantalla del **mapa corporal**, la paciente marca sobre una silueta **dónde le duele**. Cada marca "
            "guarda dos cosas: la **zona anatómica** (las ocho que usted ya revisó en el punto C-14) y el **lado**: "
            "**frente** o **espalda**.",
            "Las zonas están ratificadas. **El reparto entre frente y espalda no lo está**, y no hemos encontrado "
            "ninguna fuente publicada que lo establezca.",
            "Importa más de lo que parece: ese dato **nunca se le muestra de vuelta a la paciente**, y la primera "
            "versión **no permite corregir ni borrar** un síntoma ya registrado. Un valor equivocado se escribe una "
            "sola vez, de forma invisible, y ya no se puede arreglar. Más adelante estas marcas se dibujarán como un "
            "**mapa de calor sobre una figura humana**, que es donde un reparto equivocado se convertiría en una "
            "afirmación anatómica visible.",
        ],
        "decision": [
            ("note", "Este es el único punto del documento **sin una decisión provisional**. Carolina consideró que "
                     "es una pregunta clínica y prefirió no inventar una respuesta."),
            "**Mientras usted no lo resuelva, la versión 1 sale con una sola silueta, sin selector de "
            "frente/espalda, y no guarda ningún lado.** Así no se almacena nada sin validar y no se cierra "
            "ninguna puerta: cuando usted responda, se añade el selector y nada de lo ya guardado queda mal.",
        ],
        "sources": "Ninguna: es una pregunta abierta, no un valor tomado de la literatura.",
        "question": [
            "Para cada zona —**bajo vientre, pelvis, zona lumbar (espalda baja), piernas, intestinal/rectal, vejiga, "
            "vaginal, pecho u hombro**—, ¿la aplicación debería ofrecerla en la vista **de frente**, en la de "
            "**espalda**, en **ambas**, o **no preguntar el lado** en esa zona?",
            "Tenga en cuenta que **«pecho u hombro»** está en el vocabulario precisamente por el **dolor referido de "
            "hombro por irritación del nervio frénico**, que no es limpiamente anterior ni posterior. Si su respuesta "
            "es «registren dónde señala la paciente y no pregunten frente o espalda», es una respuesta válida y el "
            "selector se queda fuera.",
            "**Segunda pregunta, dentro del mismo punto:** en la lista de ocho zonas **no hay ninguna para el "
            "abdomen superior** (la zona por debajo de las costillas y por encima del ombligo). Hoy, en la "
            "silueta, un toque en esa zona se registra como **«pecho u hombro»**, sencillamente porque es la "
            "zona marcada más cercana. ¿Conviene añadir una zona de abdomen superior, conviene que esa franja "
            "**no sea tocable** (y la paciente la elija de la lista escrita), o le parece aceptable que se "
            "registre como «pecho u hombro»?",
        ],
    },
]
CLOSING = {
    "summary_title": "Resumen de sus respuestas",
    "summary_intro": "Para facilitar la revisión, le pedimos que traslade aquí su respuesta a cada punto. Si marcó "
                     "«Modificar» o «No estoy de acuerdo» en algún punto, recuerde dejar el detalle en el recuadro "
                     "correspondiente.",
    "blocks": [
        ("h", "Cómo devolvernos el documento"),
        ("p", "Envíe el documento firmado (en papel escaneado o en formato digital) a Carolina, responsable del "
              "producto. A partir de ahí:"),
        ("bullets", [
            "Cada punto que usted haya marcado **«De acuerdo»** se incorporará a la aplicación tal como está, con su "
            "nombre, la fecha y la fuente.",
            "Cada punto marcado **«Modificar»** se incorporará con el valor o la redacción que usted indique.",
            "Cada punto marcado **«No estoy de acuerdo»** se mantendrá fuera de la aplicación hasta que lo resolvamos "
            "con usted en una breve conversación.",
        ]),
        ("p", "Si prefiere comentar alguno de los puntos de viva voz, con gusto organizamos una reunión corta. "
              "Muchas gracias por su tiempo y por su criterio: son lo que convierte a Lumen en una herramienta segura "
              "para las pacientes."),
    ],
}

# DOCUMENTO v3.0 — PARTE 1 de 4
## F1 — Core del Pipeline / Motor de Retención
### HU1.1 a HU1.4

---

# F1.HU1.1 — Construir universo comercial base del ciclo

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.1 | Versión: 3.0
- Componente: RETENTION_CORE_COMMERCIAL
- Rol principal: Sistema (Pipeline / Core Comercial)
- Roles consumidores: Framework, Motor de Segmentación, Publicación

---

### Necesidad de negocio

Como sistema de retención, necesito construir mensualmente el universo comercial base del ciclo consolidado por advertiser_id, incluyendo tanto clientes elegibles como no elegibles, para establecer una base analítica única, trazable y auditable que permita al proceso identificar qué advertisers participan en el modelo, cuáles quedan fuera del universo y por qué motivo.

---

### Resultado esperado

Una base analítica mensual persistida en `rw_int_advertiser` y `rw_int_product`, consolidada por `cycle_id` y `advertiser_id`, que:
- Materializa el universo comercial evaluado del ciclo
- Identifica advertisers elegibles y no elegibles
- Persiste trazabilidad explícita de exclusión
- Consolida score base comercial
- Expone señales comerciales para consumo downstream
- Habilita procesamiento completo en Framework y Engine sin relectura de fuentes externas

---

### Alcance funcional

Este componente construye el dominio comercial base del pipeline y es responsable de:
1. Construir el universo analítico comercial del ciclo
2. Consolidar productos por advertiser
3. Calcular score base comercial
4. Identificar elegibilidad de universo
5. Persistir advertisers fuera de universo con trazabilidad explícita
6. Materializar señales comerciales base para Framework y Engine
7. Registrar trazabilidad operativa del componente

Este componente **no** asigna etiquetas de retención, no ejecuta jerarquía de segmentación y no consume fuentes no comerciales.

---

### Definiciones operativas

**Unidad de análisis**

La unidad analítica del componente es: `1 advertiser_id × 1 cycle_id`. Cada advertiser evaluado en el ciclo debe persistirse exactamente una vez en `rw_int_advertiser`, independientemente de si es elegible o no para scoring.

**Universo evaluado del ciclo**

El universo comercial evaluado se construye a partir de advertisers presentes en IAM con relación comercial detectable en el ciclo. El componente debe incluir:
- Advertisers con al menos un producto comercial en el ciclo
- Advertisers con base comercial incompleta pero identificables en IAM
- Advertisers sin producto elegible, persistidos explícitamente como fuera de universo

El universo evaluado no representa solo advertisers elegibles; representa el universo comercial analizado del ciclo.

**Determinación de elegibilidad**

Cada advertiser evaluado debe clasificarse como:
- `flg_universe_eligible = 1`: advertiser elegible para scoring comercial
- `flg_universe_eligible = 0`: advertiser fuera de universo, persistido por trazabilidad

La elegibilidad se determina con base en existencia y validez de productos comerciales para el ciclo.

**Trazabilidad de exclusión**

Todo advertiser fuera de universo debe persistirse explícitamente con:
- `flg_universe_eligible = 0`
- `out_universe_reason_code`
- `flg_risk_indeterminate = 1`
- `risk_indeterminate_reason_code = out_universe_reason_code`

Esto garantiza que el advertiser no desaparece del universo analítico, conserva trazabilidad de exclusión, puede ser procesado por el motor y puede generar resultado final con etiqueta INDETERMINADO.

**Motivos de exclusión — Catálogo controlado**

Core Comercial debe persistir un motivo estructurado en `out_universe_reason_code`:
- `NO_ELIGIBLE_PRODUCT`
- `ONLY_EXPIRED_PRODUCTS`
- `NO_ACTIVE_CONTRACT`
- `MISSING_COMMERCIAL_BASIS`

El valor persistido debe reutilizarse sin transformación como `risk_indeterminate_reason_code`.

**Consolidación de productos**

El componente consolida en `rw_int_product` los productos comerciales detectados para el advertiser en el ciclo, incluyendo: producto origen, estatus comercial, elegibilidad de producto, score unitario, monto asociado e indicador de producto digital. Cada producto se persiste como insumo auditable del score comercial.

**Score comercial base**

`score_total = SUM(score_producto_elegible)`

El score calculado en este componente representa únicamente el score comercial base y no constituye clasificación de riesgo.

**Señales comerciales requeridas en `rw_int_advertiser`**
- `score_total`
- `contract_amount_total`
- `has_digital_product`
- `has_rezago`
- `flg_universe_eligible`
- `out_universe_reason_code`
- `flg_risk_indeterminate`
- `risk_indeterminate_reason_code`

**Señal de rezago**

Core Comercial materializa la señal de rezago como indicador binario:
- `has_rezago = 1`: advertiser con rezago detectado
- `has_rezago = 0`: advertiser sin rezago detectado

Core Comercial **no** asigna etiqueta SP. La interpretación de esta señal corresponde exclusivamente al Motor de Segmentación.

**Trazabilidad operativa**

El componente registra trazabilidad obligatoria mediante `pkg_rw_control` en `rw_batch` y `rw_source_load`. Fuentes de lectura registradas (exactamente tres): `IAM_ADVERTISER`, `IAM_SLS_DIGITAL_INFO`, `SAP_REZAGO`.

---

### Criterios de aceptación

**CA1 — Construcción del universo analítico**
DADO QUE existe información comercial disponible para el ciclo
CUANDO se ejecuta RETENTION_CORE_COMMERCIAL
ENTONCES el sistema construye el universo comercial evaluado del ciclo y persiste un registro por cada advertiser_id en rw_int_advertiser, incluyendo elegibles y no elegibles.

**CA2 — Persistencia de elegibilidad**
DADO QUE un advertiser fue evaluado en el ciclo
CUANDO se persiste en rw_int_advertiser
ENTONCES el sistema registra explícitamente su condición de elegibilidad mediante flg_universe_eligible.

**CA3 — Persistencia de exclusión**
DADO QUE un advertiser no cumple criterios de elegibilidad
CUANDO se persiste en rw_int_advertiser
ENTONCES el sistema registra flg_universe_eligible = 0, out_universe_reason_code, flg_risk_indeterminate = 1 y risk_indeterminate_reason_code = out_universe_reason_code.

**CA4 — Persistencia de productos**
DADO QUE un advertiser tiene productos comerciales detectables en el ciclo
CUANDO se ejecuta el componente
ENTONCES el sistema persiste el detalle de productos en rw_int_product con score unitario, monto, estatus y elegibilidad por producto.

**CA5 — Cálculo de score comercial**
DADO QUE un advertiser tiene productos elegibles
CUANDO se calcula su score
ENTONCES el sistema persiste score_total como suma de scores de productos elegibles del ciclo.

**CA6 — Señal de rezago**
DADO QUE existe información de rezago para el advertiser
CUANDO se consolida la señal comercial
ENTONCES el sistema persiste has_rezago como indicador binario sin asignar segmentación.

**CA7 — Persistencia de señal digital comercial**
DADO QUE un advertiser tiene al menos un producto digital elegible
CUANDO se consolida su base comercial
ENTONCES el sistema persiste has_digital_product = 1.

**CA8 — Trazabilidad del componente**
DADO QUE se ejecuta RETENTION_CORE_COMMERCIAL
CUANDO inicia y finaliza el proceso
ENTONCES el sistema registra trazabilidad en rw_batch y rw_source_load exclusivamente mediante pkg_rw_control.

**CA9 — Consumo downstream**
DADO QUE finaliza exitosamente RETENTION_CORE_COMMERCIAL
CUANDO los componentes downstream consumen rw_int_advertiser
ENTONCES disponen de una base comercial consolidada, trazable y lista para Framework y Engine sin relectura de IAM o SAP.

---

### Dependencias
- `pkg_rw_quality`, `pkg_rw_control`
- IAM: `AAM_WORK.AAM_ADVERTISER`
- IAM productos: `report_work.SLS_DIGITAL_INFO`
- SAP Rezago: `SAP_USER.CRON_DATOS_REZAGO`

### Exclusiones explícitas

Este componente no: asigna etiquetas de retención, ejecuta jerarquía de segmentación, asigna nivel de riesgo, interpreta CQ / TA / CS, procesa tráfico digital, publica resultados ni recalcula señales downstream. La responsabilidad del componente termina en la construcción del universo comercial base.

---

# F1.HU1.2 — Identificar señales de queja, atención abierta y silencio

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.2 | Versión: 3.0
- Rol principal: Sistema (Motor de Retención)
- Roles consumidores: Negocio, Retención, Atención al Cliente, Motor de Segmentación

---

### Necesidad de negocio

Como sistema de retención, necesito identificar mensualmente a los clientes que presentan señales de queja, atención abierta o silencio en sus interacciones, para reconocer oportunamente fricción operativa, desgaste en la experiencia y ausencia de contacto, y así habilitar decisiones de retención con señales auditables, comparables y ejecutables.

---

### Resultado esperado

Una evaluación mensual por cliente que permita:
- Identificar señales independientes de queja, atención abierta y silencio
- Determinar cuándo una señal aplica y cuándo no
- Distinguir entre clientes sin señal y clientes no evaluables
- Evidenciar interacciones excluidas, incompletas o no clasificables
- Entregar señales funcionales ejecutables y auditables para el motor de segmentación

---

### Alcance funcional

1. Clasificar interacciones relevantes de atención
2. Determinar señales funcionales por cliente
3. Activar señales independientes de queja, atención abierta y silencio
4. Excluir interacciones no válidas para retención
5. Resolver ambigüedad de clasificación a nivel interacción
6. Evidenciar condiciones de calidad y completitud
7. Entregar señales auditables para consumo downstream

Esta historia **no** asigna etiqueta final, no prioriza señales a nivel cliente y no clasifica riesgo.

---

### Reglas de negocio

**1. Unidad funcional de evaluación**

La evaluación funcional se realiza a dos niveles:
- Nivel de evaluación: interacción individual
- Nivel de resultado: cliente consolidado del ciclo

Cada interacción se clasifica primero de manera individual. Las señales se consolidan posteriormente por cliente. La precedencia funcional aplica sobre la interacción. La coexistencia funcional aplica sobre el cliente.

**2. Ventanas funcionales de evaluación**

- Queja (CQ): interacciones dentro de los últimos **120 días** previos al cierre del ciclo
- Atención Abierta (TA): interacciones abiertas dentro de los últimos **90 días** previos al cierre del ciclo
- Silencio (CS): ausencia total de interacciones dentro de los últimos **90 días** previos al cierre del ciclo

Las ventanas son móviles respecto a la fecha de cierre del ciclo. La actividad digital no participa en la evaluación de silencio.

**3. Catálogo funcional de clasificación**

Cada interacción se clasifica con base en el catálogo funcional vigente de retención, que define para cada combinación: tipo de interacción, subtipo, clasificación funcional, elegibilidad y criterio de activación.

El catálogo debe identificar explícitamente si una interacción: activa señal CQ, activa señal TA, queda excluida o no es clasificable. El catálogo forma parte obligatoria de esta historia como anexo funcional ejecutable y es criterio formal de validación funcional.

**4. Regla de precedencia a nivel interacción**

Una interacción no puede activar simultáneamente múltiples clasificaciones funcionales. Precedencia obligatoria: **CQ > TA > Excluido**

- Si una interacción califica para CQ y TA → se clasifica como CQ
- Si una interacción califica para TA y Excluido → se clasifica como TA
- Una interacción solo puede aportar a una clasificación funcional

La precedencia aplica sobre la interacción individual, no sobre el cliente consolidado.

**5. Regla de activación — Queja (CQ)**

La señal CQ se activa cuando el cliente cumple al menos una de estas condiciones:
- Tiene más de 2 interacciones del mismo par tipo/subtipo clasificado como CQ
- Tiene al menos 3 pares distintos tipo/subtipo clasificados como CQ

La señal CQ se activa por recurrencia o diversidad funcional de fricción. Interacciones fuera del catálogo CQ no participan en esta evaluación.

**6. Regla de activación — Atención Abierta (TA)**

La señal TA se activa cuando el cliente presenta al menos una interacción clasificada como TA, abierta y vigente dentro de la ventana funcional.

Solo activan TA las interacciones: clasificadas en catálogo TA, abiertas o activas y funcionalmente relevantes para seguimiento.

No activan TA: interacciones administrativas, cerradas, fuera de catálogo, no accionables o no clasificables.

**7. Regla de activación — Silencio (CS)**

La señal CS se activa cuando el cliente no presenta ninguna interacción válida dentro de la ventana funcional de 90 días. La actividad digital no inhibe ni modifica esta señal.

**8. Regla de exclusión**

Una interacción debe excluirse cuando: es administrativa, no es accionable, no pertenece al catálogo funcional, está fuera de ventana, carece de información mínima, es duplicada o no tiene clasificación funcional válida. Las interacciones excluidas no activan señales. Toda exclusión debe quedar evidenciada funcionalmente.

**9. Regla de deduplicación**

Cada interacción se contabiliza una sola vez. La deduplicación se resuelve a nivel interacción con unicidad funcional, antes de aplicar clasificación funcional.

**10. Regla de calidad y no evaluable**

Un cliente se marca como no evaluable cuando sus interacciones no permiten determinar señales funcionales de forma confiable (información incompleta, clasificación insuficiente, interacciones no interpretables, ausencia de atributos mínimos).

Debe distinguirse explícitamente entre: cliente sin señal, cliente con señal, cliente no evaluable y cliente con información insuficiente.

**11. Evidencia funcional por cliente**

El resultado expone por cliente: señales activadas, cantidad de interacciones relevantes, motivo funcional de activación, última interacción válida, condición de no evaluación cuando aplique y evidencia de exclusión o incompletitud. La salida debe ser auditable por negocio sin interpretación técnica.

**12. Contrato funcional downstream**

El resultado: permite coexistencia de señales, no resuelve prioridad a nivel cliente, no asigna etiqueta final, no clasifica riesgo y no determina acción. La jerarquía de segmentación corresponde al motor.

---

### Criterios de aceptación

**CA1 — Clasificación de interacciones**
DADO QUE existen interacciones disponibles en el ciclo
CUANDO el sistema evalúa cada interacción
ENTONCES clasifica cada una con base en el catálogo funcional vigente y determina si activa CQ, TA, queda excluida o no es clasificable.

**CA2 — Precedencia de clasificación**
DADO QUE una interacción puede mapear a múltiples clasificaciones
CUANDO el sistema resuelve su clasificación funcional
ENTONCES aplica precedencia CQ > TA > Excluido y asigna una única clasificación por interacción.

**CA3 — Activación de CQ**
DADO QUE un cliente presenta interacciones clasificadas como CQ
CUANDO el sistema evalúa recurrencia y diversidad funcional
ENTONCES activa la señal CQ únicamente si cumple los criterios funcionales definidos para queja.

**CA4 — Activación de TA**
DADO QUE un cliente presenta interacciones clasificadas como TA
CUANDO el sistema evalúa vigencia y condición funcional
ENTONCES activa la señal TA únicamente si existe al menos una interacción abierta, vigente y relevante.

**CA5 — Activación de CS**
DADO QUE un cliente no presenta interacciones válidas dentro de la ventana funcional
CUANDO el sistema consolida señales
ENTONCES activa la señal CS independientemente de la actividad digital.

**CA6 — Exclusión funcional**
DADO QUE existen interacciones fuera de alcance funcional
CUANDO el sistema evalúa señales
ENTONCES excluye dichas interacciones sin activar señales y conserva evidencia funcional de exclusión.

**CA7 — Deduplicación**
DADO QUE existen interacciones duplicadas
CUANDO el sistema evalúa el universo funcional
ENTONCES contabiliza cada interacción una sola vez antes de clasificar señales.

**CA8 — Calidad y no evaluable**
DADO QUE existen clientes con información insuficiente o no interpretable
CUANDO el sistema consolida señales
ENTONCES distingue explícitamente entre cliente sin señal, cliente con señal y cliente no evaluable.

**CA9 — Evidencia funcional**
DADO QUE una señal fue activada o excluida
CUANDO negocio consulta el resultado
ENTONCES puede identificar señal, evidencia, motivo funcional y condición de evaluación del cliente.

**CA10 — Consumo downstream**
DADO QUE finaliza la evaluación funcional
CUANDO el motor consume el resultado
ENTONCES recibe señales independientes, coexistentes, auditables y sin jerarquía de cliente.

---

### Exclusiones

Esta historia no: asigna etiqueta principal, resuelve jerarquía de cliente, clasifica riesgo, interpreta actividad digital, define acciones ni ejecuta segmentación final.

---

# F1.HU1.3 — Incorporar señales de interacción digital del cliente

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.3 | Versión: 2.0
- Rol principal: Sistema (Motor de Retención)
- Roles consumidores: Negocio, Retención, Marketing, Motor de Segmentación

---

### Necesidad de negocio

Como sistema de retención, necesito incorporar mensualmente la interacción digital atribuible a cada cliente, para reconocer su nivel de actividad digital observable y complementar la lectura de engagement con señales de uso asociadas a sus dominios digitales.

---

### Resultado esperado

Una vista mensual de interacción digital por cliente que permita:
- Identificar sesiones digitales atribuibles a cada cliente
- Conocer el volumen total de sesiones del ciclo por cliente
- Visualizar todos los dominios o sitios asociados al cliente con su volumen de sesiones
- Complementar la lectura de engagement con señales digitales observables
- Habilitar al motor de segmentación con una señal digital consolidada y auditable

---

### Alcance funcional

1. Identificar interacción digital atribuible por cliente
2. Consolidar sesiones digitales del ciclo por cliente
3. Asociar interacción digital a los dominios o sitios del cliente
4. Exponer detalle funcional por dominio y vista consolidada por cliente
5. Entregar señal digital auditable para consumo downstream

Esta historia **no** clasifica engagement, no interpreta intención y no asigna segmentación.

---

### Reglas de negocio

**1. Unidad funcional de evaluación**
- Nivel de evaluación: dominio o sitio digital
- Nivel de resultado: cliente consolidado del ciclo

La señal digital debe conservar ambos niveles: detalle por dominio/sitio y consolidado por cliente.

**2. Ventana funcional de evaluación**

Solo se consideran sesiones ocurridas dentro de la ventana mensual del ciclo evaluado. No se consideran sesiones fuera del periodo del ciclo.

**3. Señal funcional digital**

La señal expresa actividad digital observable mediante:
- Volumen mensual de sesiones por cliente
- Volumen mensual de sesiones por dominio/sitio asociado

La señal no representa intención, conversión ni performance. Representa únicamente interacción digital observable atribuible al cliente.

**4. Regla de atribución funcional**

Una sesión solo puede formar parte de la señal digital de un cliente cuando puede atribuirse a uno de sus dominios o sitios asociados. El tráfico no atribuible, huérfano o sin asociación funcional válida no debe exponerse.

**5. Consolidación por cliente**

El total del cliente corresponde a la suma de sesiones atribuibles de todos sus dominios o sitios asociados.

**6. Visibilidad por dominio o sitio**

Para cada dominio o sitio debe quedar visible al menos: dominio o sitio asociado y volumen de sesiones del ciclo. La historia no limita la lectura a un único dominio principal.

**7. Regla de exclusión funcional**

No forman parte de la señal funcional digital: sesiones sin asociación válida a cliente, sesiones sin dominio identificable, sesiones fuera del ciclo ni sesiones sin atribución funcional válida.

**8. Evidencia funcional por cliente**

El resultado expone por cliente: total de sesiones del ciclo, dominios o sitios con actividad digital, volumen de sesiones por dominio/sitio y última actividad digital observable del ciclo. La salida debe ser auditable funcionalmente por negocio sin interpretación técnica.

**9. Contrato funcional downstream**

El resultado: expone interacción digital atribuible, conserva detalle por dominio/sitio, entrega total consolidado por cliente, no clasifica engagement, no asigna etiqueta y no clasifica riesgo. La interpretación funcional corresponde al motor.

---

### Criterios de aceptación

**CA1 — Identificación de interacción digital**
DADO QUE existe actividad digital en el ciclo
CUANDO el sistema evalúa sesiones digitales
ENTONCES identifica únicamente sesiones atribuibles a clientes con asociación funcional válida.

**CA2 — Consolidación por cliente**
DADO QUE un cliente presenta actividad digital atribuible
CUANDO el sistema consolida la señal digital
ENTONCES expone el total mensual de sesiones del ciclo para ese cliente.

**CA3 — Visibilidad por dominio**
DADO QUE un cliente tiene actividad digital en múltiples dominios o sitios
CUANDO el sistema presenta la señal digital
ENTONCES expone todos los dominios o sitios asociados con su volumen de sesiones del ciclo.

**CA4 — Exclusión funcional**
DADO QUE existen sesiones sin asociación válida o fuera de alcance
CUANDO el sistema consolida interacción digital
ENTONCES excluye dichas sesiones del resultado funcional visible para negocio.

**CA5 — Evidencia funcional**
DADO QUE negocio consulta la interacción digital del cliente
CUANDO revisa el resultado funcional
ENTONCES puede identificar total de sesiones, dominios asociados y volumen por dominio del ciclo.

**CA6 — Consumo downstream**
DADO QUE finaliza la consolidación de interacción digital
CUANDO el motor consume la señal digital
ENTONCES recibe una señal auditable, consolidada y sin interpretación anticipada.

---

### Exclusiones

Esta historia no: incorpora clics, clasifica engagement, interpreta intención digital, evalúa conversión, expone cobertura de atribución, clasifica riesgo, asigna etiquetas ni ejecuta segmentación final.

---

# F1.HU1.4 — Consolidar señales del cliente

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.4 | Versión: 2.0
- Rol principal: Sistema (Motor de Retención)
- Roles consumidores: Negocio, Retención, Motor de Segmentación

---

### Necesidad de negocio

Como sistema de retención, necesito consolidar mensualmente en una sola vista las señales comerciales, de atención y digitales de cada cliente, para disponer de un perfil único, consistente y auditable que permita evaluar su condición de retención sin reinterpretar fuentes ni perder trazabilidad funcional.

---

### Resultado esperado

Un perfil mensual consolidado por cliente que permita:
- Unificar señales comerciales, de atención y digitales en una sola vista
- Distinguir señales válidas de señales no concluyentes
- Conservar inconsistencias entre dominios sin ocultarlas
- Exponer condiciones de calidad y completitud que afecten la evaluación
- Dejar un perfil consolidado, auditable y evaluable para el motor

---

### Alcance funcional

1. Unificar señales del cliente en una sola vista mensual
2. Consolidar señales comerciales, de atención y digitales
3. Conservar consistencia funcional entre señales sin recalcularlas
4. Identificar inconsistencias entre dominios
5. Distinguir señales concluyentes de señales no concluyentes
6. Preservar trazabilidad funcional del perfil
7. Entregar un perfil consolidado listo para evaluación downstream

Esta historia **no** construye señales nuevas, no corrige señales upstream y no clasifica al cliente.

---

### Reglas de negocio

**1. Unidad funcional de consolidación**

Cada cliente debe contar con un único perfil consolidado mensual que reúna todas sus señales funcionales disponibles para el ciclo evaluado. La salida de esta historia es un perfil único por cliente.

**2. Señales que deben consolidarse**

El perfil consolidado del cliente integra como mínimo:
- Señales comerciales
- Señales de atención y calidad
- Señales de interacción digital
- Condición de elegibilidad
- Condición de indeterminación
- Condiciones de calidad y completitud

La consolidación no crea nuevas señales; unifica las señales existentes en un único perfil evaluable.

**3. Regla de consolidación**

Cada señal conserva: valor funcional original, estado de conclusión, evidencia funcional asociada y trazabilidad de origen. Cada señal debe conservar su significado funcional original.

**4. Regla de consistencia transversal**

Cuando existan señales inconsistentes entre dominios, el perfil consolidado: conserva las señales originales, conserva la inconsistencia detectada, la marca como condición funcional visible y no corrige ni normaliza automáticamente. La consolidación identifica inconsistencias; no las resuelve.

**5. Regla de no recalculo**

La consolidación no recalcula señales ni reinterpreta reglas de origen. Consume las señales tal como fueron construidas por sus dominios de origen.

**6. Regla de señal no concluyente**

Cuando una señal no pueda concluirse por información incompleta o inconsistente, el perfil consolidado: conserva señales válidas, marca únicamente la dimensión afectada como no concluyente y mantiene el perfil completo como evaluable. Una dimensión no concluyente no invalida el perfil completo del cliente.

**7. Regla de cliente evaluable**

Un cliente se considera evaluable mientras conserve al menos una combinación suficiente de señales concluyentes. El perfil distingue entre: cliente evaluable, cliente parcialmente concluyente y cliente no concluyente. La condición de evaluación debe quedar explícita.

**8. Evidencia funcional del perfil**

El perfil consolidado expone por cliente: señales disponibles, señales concluyentes, señales no concluyentes, inconsistencias detectadas, condiciones de calidad y completitud y motivo funcional de no conclusión cuando aplique. La salida debe ser auditable por negocio sin interpretación técnica.

**9. Contrato funcional downstream**

El resultado: unifica señales en una sola vista, conserva trazabilidad funcional, mantiene inconsistencias visibles, distingue señales válidas de no concluyentes, no clasifica riesgo, no asigna etiqueta y no define acción. La evaluación del perfil corresponde al motor.

---

### Criterios de aceptación

**CA1 — Consolidación de señales**
DADO QUE existen señales funcionales disponibles para el cliente
CUANDO el sistema consolida el perfil mensual
ENTONCES unifica sus señales comerciales, de atención y digitales en una sola vista por cliente.

**CA2 — Perfil único por cliente**
DADO QUE un cliente presenta múltiples señales en el ciclo
CUANDO el sistema consolida su información
ENTONCES genera un único perfil mensual consolidado para ese cliente.

**CA3 — Conservación de señales**
DADO QUE una señal fue construida por un dominio funcional
CUANDO se consolida el perfil del cliente
ENTONCES el sistema conserva su valor funcional original sin recalcularla ni reinterpretarla.

**CA4 — Inconsistencia entre dominios**
DADO QUE existen señales inconsistentes entre dominios
CUANDO el sistema consolida el perfil
ENTONCES conserva ambas señales y marca la inconsistencia como condición funcional visible.

**CA5 — Señal no concluyente**
DADO QUE una dimensión no puede concluirse por información incompleta
CUANDO el sistema consolida el perfil
ENTONCES conserva señales válidas y marca únicamente esa dimensión como no concluyente.

**CA6 — Cliente evaluable**
DADO QUE un cliente conserva señales concluyentes suficientes
CUANDO el sistema consolida el perfil
ENTONCES mantiene al cliente como evaluable para el motor.

**CA7 — Evidencia funcional**
DADO QUE negocio consulta el perfil consolidado
CUANDO revisa el resultado funcional
ENTONCES puede identificar señales, inconsistencias, dimensiones no concluyentes y condición de evaluación del cliente.

**CA8 — Consumo downstream**
DADO QUE finaliza la consolidación del perfil
CUANDO el motor consume el resultado
ENTONCES recibe un perfil único, consolidado, auditable y listo para evaluación.

# DOCUMENTO v3.0 — PARTE 2 de 4
## F1 — Core del Pipeline / Motor de Retención
### HU1.5, HU1.6 y HU1.7

---

# F1.HU1.5 — Evaluar cliente y asignar clasificación de retención

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.5 | Versión: 3.0
- Rol principal: Sistema (Motor de Retención)
- Roles consumidores: Negocio, Retención, Operación Comercial, Publicación

---

### Necesidad de negocio

Como sistema de retención, necesito evaluar mensualmente el perfil consolidado de cada cliente y asignarle una única clasificación de retención, para traducir sus señales en una decisión operable, priorizable y trazable que permita orientar acciones de seguimiento, protección y recuperación.

---

### Resultado esperado

Una clasificación mensual única por cliente con score numérico, etiqueta cualitativa y nivel de riesgo que permita:
- Evaluar el perfil consolidado del cliente
- Asignar una única clasificación de retención
- Determinar el nivel de prioridad del cliente
- Conservar trazabilidad de las señales que explican la decisión
- Entregar una salida operable para seguimiento y publicación

---

### Definiciones operativas

**Universo de clientes a evaluar**

Todos los clientes con al menos un producto en estatus Live, In Process, Draft o Suspended con monto al momento del cálculo. La unidad de cliente es el `advertiser_id` (con las limitaciones aceptadas en TR-01).

**Periodicidad del cálculo**
- Frecuencia: Mensual
- Momento de ejecución: **Día 04 de cada mes a las 09:00 hrs**
- Datos de referencia: Mes vencido (cierre del mes anterior)
- Configurable: Sí (vía panel HU1.7)

---

### Dimensión 1 — Cálculo del Score

**Fórmula**

`SCORE_cliente = Σ(score_producto)`

Para todos los productos del cliente en estatus Live, In Process, Draft o Suspended:
- Suma aditiva simple, sin tope máximo
- Productos en otros estatus (cancelados, vencidos sin renovación) no se cuentan
- Catálogo de scores: archivo de 113 productos provisto por Mercadotecnia (incluye oferta 2024 y oferta 2026)
- Valores posibles por producto: 0, 1, 100
- Fuente del catálogo: IAM (mapeo `Product_code → score`)

**Lógica de los valores**
- **Score 100:** productos de publicidad digital (Google Ads y Facebook Ads). Diferencian a clientes con campaña activa
- **Score 1:** productos de soluciones web con monto
- **Score 0:** productos vivos sin monto asociado
- Ningún cliente acumula más de 21 puntos solo con productos de soluciones web (regla validada por Mercadotecnia)

---

### Dimensión 2 — Asignación de Etiqueta

**Reglas de evaluación**
- Cada cliente recibe una sola etiqueta (exclusión mutua)
- Las etiquetas se evalúan en orden de prioridad. El primer match se asigna y las demás no se evalúan

**Jerarquía oficial:**

| Prioridad | Etiqueta | Segmento |
|---|---|---|
| 0 | INDETERMINADO | Cliente no concluyente / no evaluable |
| 1 | VP | Clientes de alto valor |
| 2 | CQ | Quejas explícitas |
| 3 | SP | Clientes sin pago — protección |
| 4 | FL | Falta de leads |
| 5 | TA | Casos abiertos (tickets) |
| 6 | CS | Cliente silencioso revisión |
| 7 | RB | Resto de los clientes (bajo) |

---

#### Condiciones por etiqueta

**INDETERMINADO**

La clasificación INDETERMINADO se asigna cuando el cliente no puede evaluarse de forma concluyente. Tiene **precedencia absoluta** sobre cualquier otra clasificación. Se asigna cuando se cumple al menos una de estas condiciones:
- Tiene algún producto activo con `product_code` no mapeado en el catálogo de scores
- Tiene `fecha_ultima_contratacion` nula o inválida
- Los datos de la fuente que determina su segmento no pudieron extraerse (ej. Panel Marketing falló y el cliente es candidato FL)
- Tiene cases con `fecha_apertura` nula o inválida
- Fue marcado con `flg_risk_indeterminate = 1` por Core Comercial (HU1.1)

Cuando se asigna INDETERMINADO, el sistema detiene la evaluación de jerarquía y no evalúa las demás etiquetas.

---

**VP — Clientes de alto valor**

Condiciones (todas deben cumplirse simultáneamente):
- Valor contrato > 120,000 MXN **Y**
- Score > 15 **Y**
- Score < 100 **Y**
- Cliente tiene al menos un producto de campaña digital (Google Ads o Facebook Ads)

> El "valor contrato" es la suma de montos de productos vigentes (estatus Live, In Process, Draft o Suspended) en IAM. La condición de "tener campaña" excluye explícitamente clientes que solo tengan soluciones web.

> Nota operativa: el flujo de contacto VP es manual y a cargo del supervisor de ventas. No hay automatización en este alcance. La intención es que el contacto sea personalizado.

---

**CQ — Quejas explícitas**

Un cliente recibe etiqueta CQ si cumple al menos **una** de las siguientes condiciones:

**Condición 1:** Tiene 3 o más cases abiertos en el mes de cálculo, donde los cases sean de cualquiera de los siguientes tipos:
- Seguimiento Pub. FyC
- Acreditaciones
- Facturación y Crédito
- Seguimiento a Pagos
- Atención despacho externo
- Retención Customer Care
- Aclaración de saldos
- Información y Dudas de su publicación
- Atención a Clientes

**Condición 2:** Tiene 2 o más cases del mismo tipo levantados por CAC en el periodo de cálculo.

**Condición 3:** Tiene la etiqueta manual "cliente con queja explícita" activa en IAM (creada por Voz del Cliente). Esta etiqueta tiene vigencia de **3 meses** desde su asignación.

**Validez del segmento:** el cliente debe tener al menos un producto en estatus In Process, Draft, Suspended o Live con monto al momento del cálculo. Si todos sus productos están **cancelados o expirados**, no aplica CQ.

**Mecanismo de salida:** cuando FDV (Fuerza de Ventas) retroalimenta el contacto con el cliente mediante la "campaña en oportunidades" en Pinbox, se cierra automáticamente la etiqueta CQ. Si no hay retroalimentación, el cliente permanece en CQ para seguimiento.

> Nota operativa: CQ es el único segmento con contacto humano directo (CAC). Los demás segmentos de Alto Riesgo solo reciben campaña automatizada.

---

**SP — Clientes sin pago / protección**

- Cliente con rezago en el mes que se está evaluando
- Fuente: tabla de rezago en el esquema `SAP_USER@UNOREP`, actualizada diariamente
- No se usa el campo `DELINQUENT STATUS` de IAM (descartado por no corresponder con el indicador deseado)

---

**FL — Falta de leads**

- Variable: visitas (no leads, en esta primera fase)
- Fuente: Panel Marketing
- Cálculo: suma de visitas a todos los sitios del cliente con al menos 30 días publicados
- Ventana temporal: mensual (mes vencido)

Condiciones:
- Cliente **con campaña digital** → debe tener al menos **60 visitas** en el mes. Si tiene menos, califica como FL
- Cliente **con sitio (sin campaña)** → debe tener al menos **20 visitas** en el mes. Si tiene menos, califica como FL

> Umbrales 60 y 20: son estimación inicial. Serán monitoreados para ajuste futuro vía panel HU1.7.

> En fases posteriores se debe definir cómo consolidar conversiones reales (leads) en un solo indicador, ya que actualmente están fragmentadas en varias fuentes.

---

**TA — Casos abiertos (tickets)**

- Cliente con cases abiertos de interacción con el cliente (catálogo definido en archivo "catalogo cases init source ctes ult 12m")
- Los cases deben tener más de **15 días** abiertos al momento del cálculo

> Pendiente: incorporar el detalle del archivo "catalogo cases init source ctes ult 12m" cuando se reciba del CAC.

---

**CS — Cliente silencioso revisión**

Todas las condiciones deben cumplirse simultáneamente:
- Cliente al corriente en sus pagos (no califica como SP)
- Sin ningún case registrado en los últimos **90 días**
- Score < 21 con más de 20 visitas en el mes (si calificara para FL, ya quedó en FL por jerarquía de prioridad)
- La última contratación del cliente debe ser anterior o igual al **31 de diciembre de 2025**

---

**RB — Resto de los clientes**

- Cualquier cliente activo que no haya calificado en ninguna de las etiquetas anteriores
- Incluye automáticamente a clientes con score total = 0
- Es la clasificación de fallback residual del modelo

---

### Dimensión 3 — Asignación del Nivel de Riesgo

| Etiqueta | Condición adicional | Nivel de Riesgo | Acción asignada |
|---|---|---|---|
| INDETERMINADO | — | Indeterminado | Revisión manual por AR |
| VP | — | Revisión | Trabajar con ventas (manual, supervisor de ventas) |
| CQ | — | Alto | Trabajar con CAC |
| SP | — | Alto | Envío de campaña |
| FL | — | Alto | Envío de campaña |
| TA | — | Alto | Envío de campaña |
| CS | Score > 21 | Medio | Envío de campaña |
| CS | Score ≤ 21 | Bajo | Envío de campaña |
| RB | — | Bajo | Sin acción en esta fase |

> SP, FL y TA (Alto Riesgo): la acción definida es solo envío de campaña automatizada. No hay contacto humano en esta fase. Solo CQ tiene contacto humano.

---

### Alcance funcional

Esta historia sí resuelve prioridad, sí clasifica y sí transforma señales en una decisión final. Debe permitir:
1. Evaluar el perfil consolidado del cliente
2. Aplicar reglas de clasificación de retención
3. Resolver una única clasificación final por cliente
4. Aplicar jerarquía estricta de precedencia
5. Conservar trazabilidad de señales secundarias
6. Determinar prioridad funcional de atención
7. Entregar resultado final para publicación y operación

Esta historia **no** recalcula señales upstream, no modifica reglas de origen, no ejecuta acciones de retención y no publica resultados.

---

### Criterios de aceptación

**CA1 — Ejecución del proceso de segmentación**
DADO QUE existen los datos requeridos en las fuentes definidas (IAM, SAP_USER@UNOREP, Panel Marketing, catálogo de productos)
CUANDO se ejecuta el proceso de segmentación el día 04 de cada mes a las 09:00 hrs con datos a mes vencido
ENTONCES cada cliente activo del universo recibe un score numérico, una etiqueta única y un nivel de riesgo asignado.

**CA2 — Clasificación única**
DADO QUE un cliente puede activar múltiples señales
CUANDO el sistema resuelve su clasificación
ENTONCES asigna una única clasificación final mutuamente excluyente.

**CA3 — Jerarquía de precedencia**
DADO QUE un cliente activa múltiples señales simultáneamente
CUANDO el sistema evalúa precedencia
ENTONCES aplica la jerarquía oficial INDETERMINADO → VP → CQ → SP → FL → TA → CS → RB y asigna el primer match válido.

**CA4 — Cálculo del score**
DADO QUE un cliente tiene uno o varios productos en estatus Live, In Process, Draft o Suspended
CUANDO se calcula su score
ENTONCES el sistema suma los scores de todos sus productos según el catálogo, resultando en un valor entero ≥ 0 sin tope máximo.

**CA5 — Asignación de nivel de riesgo**
DADO QUE un cliente recibió una etiqueta
CUANDO se mapea contra la matriz etiqueta → nivel de riesgo
ENTONCES el cliente queda clasificado en uno de los cuatro niveles: Revisión, Alto, Medio o Bajo, considerando el caso especial de CS donde el nivel depende del score (>21 = Medio, ≤21 = Bajo).

**CA6 — Clasificación INDETERMINADO**
DADO QUE un cliente no es concluyente o no es evaluable
CUANDO el sistema inicia la evaluación
ENTONCES asigna INDETERMINADO y detiene la evaluación de jerarquía.

**CA7 — Trazabilidad del cálculo**
DADO QUE se ejecuta el proceso de segmentación y un cliente recibe su clasificación
CUANDO el sistema genera el resultado
ENTONCES registra: fecha de cálculo, score numérico resultante, productos considerados con sus scores individuales, etiqueta asignada, condición específica que disparó la etiqueta, nivel de riesgo final y acción asignada.

**CA8 — Tratamiento de clientes sin productos válidos**
DADO QUE un cliente no tiene ningún producto en estatus Live, In Process, Draft o Suspended con monto
CUANDO se ejecuta el proceso
ENTONCES el cliente permanece persistido en el universo analítico y recibe clasificación INDETERMINADO cuando aplique.

**CA9 — Vigencia de la etiqueta manual de queja**
DADO QUE Voz del Cliente asignó manualmente la etiqueta "cliente con queja explícita" en IAM
CUANDO han transcurrido más de 3 meses desde la asignación
ENTONCES la etiqueta deja de considerarse para el cálculo del segmento CQ.

**CA10 — Cierre automático de CQ por retroalimentación**
DADO QUE un cliente está en segmento CQ
CUANDO FDV registra retroalimentación del contacto con el cliente vía la "campaña en oportunidades" en Pinbox
ENTONCES el cliente sale del segmento CQ en el siguiente cálculo.

**CA11 — Trazabilidad de señales secundarias**
DADO QUE una clasificación final fue asignada
CUANDO el sistema registra el resultado
ENTONCES conserva señales secundarias y reglas descartadas como evidencia de trazabilidad.

**CA12 — Clasificación fallback**
DADO QUE un cliente no activa ninguna regla previa
CUANDO el sistema completa la evaluación
ENTONCES asigna RB como clasificación residual final.

**CA13 — Resultado publicable**
DADO QUE finaliza la evaluación del cliente
CUANDO el sistema genera el resultado final
ENTONCES entrega una clasificación única, trazable y lista para publicación.

---

### Datos requeridos (insumos)

| Dato | Fuente | Periodicidad | Notas |
|---|---|---|---|
| Productos del cliente y estatus | IAM | Mensual (cierre de mes) | Estatus válidos: Live, In Process, Draft, Suspended |
| Catálogo de scores por producto | Archivo Mercadotecnia (113 productos) | Estática (con versiones) | Mapeo Product_code → score |
| Valor del contrato | IAM | Mensual | Suma de montos de productos vigentes |
| Cases abiertos por tipo y antigüedad | IAM | Mensual | Catálogo de cases en archivo "catalogo cases init source ctes ult 12m" |
| Etiqueta manual "queja explícita" | IAM | Diaria | Vigencia 3 meses |
| Rezago de pagos | SAP_USER@UNOREP | Diaria | Tabla específica de rezago |
| Visitas al sitio | Panel Marketing | Mensual | Solo sitios con ≥30 días publicados |
| Fecha de última contratación | IAM | Mensual | Para criterio CS |
| Retroalimentación FDV | Pinbox (campaña en oportunidades) | Diaria | Para cierre de CQ |

---

### Sistemas impactados

| Sistema | Rol | Acción requerida |
|---|---|---|
| IAM | Fuente principal | Lectura de productos, cases, etiquetas, valor contrato |
| SAP_USER@UNOREP | Fuente de morosidad | Lectura tabla de rezago |
| Panel Marketing | Fuente de visitas | Lectura de visitas por sitio |
| Pinbox | Fuente de retroalimentación | Lectura de campaña en oportunidades |
| Motor de segmentación (nuevo) | Procesamiento | Cálculo, almacenamiento de resultados, trazabilidad |

---

### Supuestos y limitaciones aceptadas

1. Identidad del cliente: se usa `advertiser_id`. Cambios de razón social pueden generar distorsión en métricas (TR-01 aceptado)
2. Visitas como proxy de leads: en esta fase se usa visitas por simplicidad y disponibilidad. Conversiones reales se abordarán en fases posteriores
3. Umbrales 60 y 20: son estimaciones iniciales, sujetas a calibración después del primer ciclo
4. NPS no integrado: la señal de queja viene exclusivamente vía cases o etiqueta manual en esta fase
5. VP y CQ no automatizados: el contacto es 100% humano (supervisor de ventas para VP, CAC para CQ)

---

### Dependencias

- **Bloqueante:** archivo "catalogo cases init source ctes ult 12m" del CAC (necesario para precisar TA y los tipos válidos en CQ)
- **Bloqueante:** acceso técnico al esquema SAP_USER@UNOREP para lectura de tabla de rezago
- **Bloqueante:** acceso técnico a Panel Marketing para extracción de visitas
- **Bloqueante:** HU1.7 debe estar diseñada con arquitectura que permita parametrización externa (no valores hardcoded)
- **No bloqueante (paralelo):** definición de la "campaña en oportunidades" en Pinbox para el cierre de CQ
- **No bloqueante:** definición del proceso del supervisor de ventas para VP

---

### Brechas pendientes

1. Mecanismo de carga de la etiqueta manual de queja: Voz del Cliente la captura directamente en IAM. Se requiere agregar el campo TAG en IAM
2. Definición de "interacción con el cliente" en el catálogo de tipos de case para TA: pendiente del archivo del CAC
3. Proceso de monitoreo de los umbrales (60 y 20 visitas): ¿quién los revisa, con qué frecuencia, qué criterio dispara un ajuste?

---

# F1.HU1.6 — Publicar resultado vigente del ciclo de retención

**Identificación**
- Feature: F1 — Core del Pipeline / Motor de Retención
- Historia: HU1.6 | Versión: 2.0
- Rol principal: Sistema (Motor de Retención)
- Roles consumidores: Negocio, Retención, Operación Comercial, Reporting

---

### Necesidad de negocio

Como sistema de retención, necesito publicar una única versión oficial del resultado del ciclo de retención, para asegurar que negocio, operación y seguimiento trabajen siempre sobre una sola versión vigente, consistente y trazable del resultado mensual.

---

### Resultado esperado

Una versión oficial y vigente del resultado del ciclo que permita:
- Disponer de una única salida oficial por ciclo
- Evitar ambigüedad entre corridas del mismo ciclo
- Asegurar que negocio consuma solo la versión vigente
- Conservar trazabilidad de versiones previas
- Habilitar consumo operativo y seguimiento sobre un resultado único y oficial

---

### Alcance funcional

1. Publicar una única versión oficial del resultado por ciclo
2. Desactivar la versión previamente vigente, cuando exista
3. Conservar histórico de corridas previas sin eliminarlas
4. Garantizar unicidad de resultado vigente por ciclo
5. Exponer la versión oficial para consumo de negocio y operación
6. Cerrar formalmente el ciclo una vez publicada la versión oficial

Esta historia **no** recalcula resultados, no reclasifica clientes y no modifica la lógica del modelo.

---

### Reglas de negocio

**1. Unidad funcional de publicación**

La publicación se realiza a nivel ciclo y corrida. Cada ciclo puede tener múltiples corridas ejecutadas, pero solo una puede quedar publicada como versión oficial vigente.

**2. Regla de versión oficial única**

Para cada ciclo debe existir una sola versión oficial vigente del resultado. No se permiten múltiples versiones oficiales simultáneas para un mismo ciclo. La versión oficial vigente es la única que puede ser consumida por negocio y operación.

**3. Regla de publicación**

Una corrida solo puede publicarse cuando su resultado haya sido completado de forma íntegra y esté listo para consumo operativo. La publicación no recalcula el resultado; únicamente lo oficializa.

**4. Regla de despublicación previa**

Cuando se publique una nueva versión oficial, el sistema desactiva primero la versión previamente vigente, si existe. La versión anterior debe dejar de estar vigente, pero debe conservarse en histórico. Despublicar no elimina resultados ni histórico; solo retira vigencia operativa.

**5. Regla de histórico**

Toda corrida ejecutada debe conservarse como histórico auditable del ciclo, independientemente de su vigencia. Las corridas históricas deben permanecer disponibles para trazabilidad, auditoría y comparación.

**6. Regla de unicidad operativa**

Negocio y operación deben consumir una sola versión del resultado por ciclo. No deben existir ambigüedades sobre qué resultado utilizar.

**7. Regla de cierre de ciclo**

Una vez publicada exitosamente la versión oficial, el ciclo queda formalmente cerrado, indica que ya tiene resultado oficial vigente, está disponible para consumo operativo y no requiere nueva evaluación para esa publicación.

**8. Trazabilidad de publicación**

La publicación conserva trazabilidad de: corrida publicada, corrida previamente vigente cuando exista, momento de publicación, versión vigente del ciclo y estado final del ciclo.

---

### Criterios de aceptación

**CA1 — Publicación de versión oficial**
DADO QUE existe una corrida completada del ciclo
CUANDO el sistema publica el resultado
ENTONCES la convierte en la única versión oficial vigente del ciclo.

**CA2 — Unicidad de versión vigente**
DADO QUE un ciclo puede tener múltiples corridas
CUANDO una versión se publica
ENTONCES el sistema garantiza que solo una quede vigente como oficial.

**CA3 — Despublicación previa**
DADO QUE existe una versión previamente vigente del ciclo
CUANDO el sistema publica una nueva versión oficial
ENTONCES desactiva primero la versión anterior sin eliminarla del histórico.

**CA4 — Conservación de histórico**
DADO QUE existen corridas previas del mismo ciclo
CUANDO se publica una nueva versión oficial
ENTONCES el sistema conserva todas las corridas anteriores como histórico auditable.

**CA5 — Consumo operativo**
DADO QUE negocio consulta el resultado del ciclo
CUANDO consume la salida oficial
ENTONCES accede únicamente a la versión vigente publicada.

**CA6 — Cierre de ciclo**
DADO QUE la publicación finaliza correctamente
CUANDO el sistema oficializa la versión vigente
ENTONCES el ciclo queda formalmente cerrado.

**CA7 — Trazabilidad de publicación**
DADO QUE una corrida fue publicada
CUANDO negocio audita la salida oficial
ENTONCES puede identificar la versión vigente, la corrida publicada, la versión reemplazada y el momento de publicación.

---

### Exclusiones

Esta historia no: recalcula resultados, reclasifica clientes, modifica señales, ejecuta acciones de retención, elimina histórico ni reabre ciclos automáticamente.

---

# F1.HU1.7 — Administrar parámetros configurables del modelo

## Identificación

* Feature: F1 — Motor de Segmentación
* Historia: HU1.7 | Versión: 2.1
* Rol principal: Product Owner (PO) / Mercadotecnia
* Roles consumidores: Motor de segmentación, Sistemas, Auditoría funcional

---

## Necesidad de negocio

Como Product Owner del modelo de retención, necesito administrar los parámetros configurables utilizados por el motor de segmentación, de modo que el negocio pueda ajustar umbrales, catálogos y reglas parametrizables sin requerir cambios de código ni despliegues técnicos, manteniendo trazabilidad completa de versiones y consistencia entre ciclos.

---

## Resultado esperado

Un panel administrativo que permita gestionar parámetros del modelo de retención mediante configuración controlada, con versionamiento, trazabilidad y aplicación diferida por ciclo, garantizando que:

* los cambios queden auditados,
* los resultados puedan reproducirse históricamente,
* y la lógica oficial del modelo permanezca estable y consistente.

---

## Contexto y justificación

El modelo de retención utiliza distintos parámetros que pueden cambiar con el tiempo debido a ajustes operativos o decisiones de negocio, por ejemplo:

* score por producto,
* umbrales de clasificación,
* catálogos de tipos de case,
* ventanas temporales,
* pesos configurables,
* parámetros de sensibilidad,
* reglas de exclusión controladas.

Actualmente estos valores podrían quedar embebidos en código o configuraciones técnicas difíciles de administrar, lo que genera:

* dependencia excesiva de Sistemas,
* riesgo operativo al modificar lógica productiva,
* falta de trazabilidad histórica,
* dificultad para auditar resultados pasados,
* inconsistencia entre ciclos.

La historia define un mecanismo formal de parametrización controlada para el modelo.

---

# Alcance funcional

La funcionalidad permite:

1. Consultar los parámetros vigentes del modelo.
2. Crear nuevas versiones de configuración.
3. Modificar parámetros autorizados.
4. Programar la aplicación de cambios para ciclos futuros.
5. Consultar historial de cambios.
6. Comparar versiones de parámetros.
7. Validar consistencia básica antes de publicar una versión.
8. Mantener trazabilidad completa de quién modificó qué y cuándo.

---

# Restricción funcional crítica — Jerarquía oficial del modelo

La jerarquía oficial de clasificación definida en HU1.5 es una regla funcional fija y no configurable desde el panel administrativo.

Orden oficial vigente:

1. INDETERMINADO
2. VP
3. CQ
4. SP
5. FL
6. TA
7. CS
8. RB

La funcionalidad de parametrización NO permite:

* reordenar etiquetas,
* eliminar etiquetas,
* crear nuevas etiquetas,
* modificar precedencias,
* alterar la lógica de exclusión mutua del modelo.

Cualquier modificación a la jerarquía oficial requiere cambio funcional formal, evaluación técnica y liberación controlada por Sistemas.

---

# Parámetros configurables permitidos

## Configuración editable por negocio

| Parámetro                         | Editable | Versionable |
| --------------------------------- | -------- | ----------- |
| Score por producto                | Sí       | Sí          |
| Umbral de clasificación           | Sí       | Sí          |
| Ventanas de tiempo                | Sí       | Sí          |
| Catálogo de tipos de case válidos | Sí       | Sí          |
| Pesos parametrizables             | Sí       | Sí          |
| Umbral de nulos críticos          | Sí       | Sí          |
| Sensibilidad de alertas           | Sí       | Sí          |

---

## Configuración NO editable desde panel

| Elemento                       | Motivo                       |
| ------------------------------ | ---------------------------- |
| Jerarquía oficial de etiquetas | Regla estructural del modelo |
| Lógica de precedencia          | Consistencia funcional       |
| Algoritmo de segmentación      | Control técnico              |
| Flujo ETL                      | Infraestructura técnica      |
| Reglas de publicación          | Gobernanza operativa         |

---

# Reglas funcionales

## RF1 — Aplicación diferida

Todo cambio publicado aplica únicamente al siguiente ciclo de ejecución.
Nunca modifica un ciclo ya ejecutado.

---

## RF2 — Versionamiento obligatorio

Toda modificación genera automáticamente una nueva versión de configuración.

La versión debe almacenar:

* fecha,
* usuario,
* parámetros modificados,
* valor anterior,
* valor nuevo,
* comentario opcional.

---

## RF3 — Inmutabilidad histórica

Las configuraciones utilizadas en ciclos anteriores permanecen congeladas y disponibles para auditoría histórica.

---

## RF4 — Validación previa

El sistema valida consistencia mínima antes de publicar una versión:

* tipos válidos,
* rangos permitidos,
* parámetros obligatorios,
* duplicados,
* referencias inexistentes.

---

## RF5 — Trazabilidad completa

Toda modificación debe quedar auditada.

---

## RF6 — Separación entre parametrización y lógica estructural

El panel administra únicamente parámetros de negocio autorizados.

No administra reglas estructurales del modelo.

---

# Criterios de aceptación

## CA1 — Consulta de configuración vigente

DADO QUE existe una versión vigente
CUANDO el PO consulta el panel
ENTONCES visualiza todos los parámetros configurables activos para el siguiente ciclo.

---

## CA2 — Modificación de parámetros permitidos

DADO QUE el PO cuenta con permisos válidos
CUANDO modifica un parámetro editable
ENTONCES el sistema registra el cambio y genera una nueva versión.

---

## CA3 — Aplicación diferida de cambios

DADO QUE existe una nueva versión publicada
CUANDO inicia el siguiente ciclo de segmentación
ENTONCES el motor utiliza exclusivamente la nueva versión vigente.

---

## CA4 — Conservación histórica

DADO QUE existen versiones anteriores
CUANDO un usuario autorizado consulta historial
ENTONCES puede visualizar configuraciones previas y sus diferencias.

---

## CA5 — Restricción sobre jerarquía oficial

DADO QUE el usuario administra parámetros del modelo
CUANDO intenta modificar la jerarquía oficial de etiquetas
ENTONCES el sistema no permite la operación e informa que la jerarquía es una regla estructural no configurable.

---

## CA6 — Validación de integridad

DADO QUE el usuario intenta publicar una nueva versión
CUANDO existen parámetros inválidos o inconsistentes
ENTONCES el sistema rechaza la publicación indicando los errores detectados.

---

## CA7 — Auditoría de cambios

DADO QUE se realizó una modificación
CUANDO se consulta la trazabilidad
ENTONCES el sistema muestra usuario, fecha, cambio realizado y versión afectada.

---

# Exclusiones

Esta historia no:

* modifica la lógica estructural del motor,
* altera la jerarquía oficial de etiquetas,
* recalcula ciclos históricos,
* administra procesos ETL,
* reemplaza control de cambios técnico,
* implementa despliegues automáticos de código.

---

# Dependencias

* HU1.5 debe soportar parametrización externa.
* Debe existir autenticación corporativa.
* Debe existir repositorio persistente de versiones.
* Debe existir catálogo inicial de parámetros.

---

# Supuestos y limitaciones

1. No existe rollback automático de ciclos históricos.
2. Los cambios nunca aplican al ciclo en ejecución.
3. El MVP considera un solo aprobador.
4. La jerarquía oficial del modelo permanece fija durante el MVP.
5. Cambios estructurales requieren intervención formal de Sistemas.


---

# DOCUMENTO v3.0 — PARTE 3 de 4
## F2 — Infraestructura de Datos
### HU2.1 Ingesta y mapeo de fuentes + HU2.2 Calidad de datos

---

# F2.HU2.1 — Ingesta y mapeo de fuentes (ETL)

**Identificación**
- Feature: F2 — Infraestructura de Datos
- Historia: HU2.1 | Versión: 2.0
- Rol principal: Sistemas (IT)
- Roles consumidores: Motor de segmentación, Tablero operativo, Reportes, Métricas

---

### Necesidad de negocio

Como área de Sistemas, necesito contar con un proceso estructurado de ingesta y normalización de información que consolide los datos de múltiples fuentes en un modelo unificado, de modo que el motor de segmentación (HU1.5) y el tablero operativo (HU3.1) puedan consumir datos consistentes, actualizados y confiables sin lógica ad-hoc en cada componente.

---

### Resultado esperado

Un conjunto de datos unificado, actualizado periódicamente y disponible en un repositorio central que alimente todos los componentes del sistema de retención (segmentación, tablero, reportes, métricas) con un contrato de datos estable.

---

### Contexto y justificación

El motor de segmentación (HU1.5) consume datos de múltiples fuentes con distintas características: IAM, SAP_USER@UNOREP, Panel Marketing, Pinbox, catálogo de productos y catálogo de tipos de case. Sin un proceso de ingesta estructurado, cada componente consultaría directamente cada fuente, generando:
- Lógica duplicada entre componentes
- Inconsistencia de criterios entre consumidores
- Mayor carga sobre los sistemas fuente
- Imposibilidad de auditar qué dato se usó en qué cálculo
- Dificultad para reprocesar datos históricos

Esta HU define el proceso de ingesta, transformación y carga (ETL) que alimenta a todos los demás componentes del sistema.

---

### Arquitectura propuesta — Tres capas

**Capa 1 — Extracción (Raw)**
Extrae datos de cada fuente sin transformación y los deposita en un área de staging con marca temporal. Los datos en esta capa representan exactamente lo que se recibió de la fuente.

**Capa 2 — Normalización (Staged)**
Aplica reglas de limpieza, mapeo y homologación. Genera tablas con estructura canónica ya validadas.

**Capa 3 — Consumo (Analytical)**
Expone vistas y tablas finales que consumen los componentes del sistema de retención. Es la única capa que los consumidores downstream deben consultar. Nunca deben acceder directamente a las fuentes originales.

> Esta arquitectura puede implementarse como un esquema dedicado o existente en la base de datos del motor, siempre que mantenga la separación de capas.

---

### Fuentes y estrategia de extracción

| # | Fuente | Datos extraídos | Mecanismo | Frecuencia |
|---|---|---|---|---|
| 1 | IAM | Clientes (advertisers), productos y estatus, cases, etiquetas, valor contrato, datos de contacto, agente/supervisor, división, campaña, categoría, población, vigencia, fecha última contratación | Consulta a BD de IAM (lectura directa o réplica) | Diaria (incremental) + mensual (completa) |
| 2 | SAP_USER@UNOREP | Tabla de rezago por cliente | Consulta a esquema SAP | Diaria |
| 3 | Panel Marketing | Visitas por sitio, antigüedad de publicación del sitio | API o extracción programada | Mensual (al cierre de mes) |
| 4 | Pinbox | Retroalimentación de FDV en "campaña en oportunidades" | Consulta a BD de Pinbox o API | Diaria |
| 5 | Catálogo de productos (scores) | Product_code, score | Importación desde panel HU1.7 | Bajo demanda (cuando Mercadotecnia actualice) |
| 6 | Catálogo de tipos de case | catalogo cases init source ctes ult 12m | Importación desde archivo de referencia | Bajo demanda |

---

### Modelo de datos unificado

El modelo se organiza alrededor de la entidad Cliente (advertiser) con las siguientes entidades relacionadas:

---

**Entidad: CLIENTE**

| Campo | Tipo | Fuente | Notas |
|---|---|---|---|
| advertiser_id | ID | IAM | Identificador único (con limitaciones TR-01) |
| nombre_cliente | Texto | IAM | |
| contact_name | Texto | IAM | First Name + Last Name |
| phone | Texto | IAM | Validado al momento de ingesta |
| cell_phone | Texto | IAM | Validado al momento de ingesta |
| email | Texto | IAM | Validado al momento de ingesta |
| id_agente | ID | IAM | |
| nombre_agente | Texto | IAM | |
| channel_code | Código | IAM | |
| id_supervisor | ID | IAM | |
| nombre_supervisor | Texto | IAM | |
| division | Código | IAM | |
| nombre_division | Texto | IAM | |
| town_name | Texto | IAM | Población |
| fecha_ultima_contratacion | Fecha | IAM | Usado en criterio CS |
| delinquent_status | Código | IAM | Informativo — no se usa para SP |
| tiene_rezago | Booleano | SAP_USER@UNOREP | Fuente oficial para SP |
| etiqueta_queja_manual | Fecha activación | IAM | Usado en CQ — vigencia 3 meses |

---

**Entidad: PRODUCTO_CLIENTE**

| Campo | Tipo | Fuente | Notas |
|---|---|---|---|
| advertiser_id | FK | IAM | |
| product_id | ID | IAM | |
| bc_product_id | ID | IAM | |
| product_code | Código | IAM | Mapeo contra catálogo de scores |
| product_name | Texto | IAM | |
| product_status | Código | IAM | Live / In Process / Draft / Suspended / Cancelado / otros |
| oc | Texto | IAM | |
| rc | Texto | IAM | |
| offer | Texto | IAM | Identifica oferta 2024 vs 2026 |
| category_name | Texto | IAM | |
| campaign_code | Código | IAM | |
| campaign_name | Texto | IAM | |
| monto | Numérico | IAM | Para valor contrato y detección de "con monto" |
| vigencia | Fecha | IAM | |
| esquema_pago | Código | IAM | Suscripción / Periodo forzoso / PPA |
| tiene_monto | Booleano | Calculado | `monto > 0` |
| score_producto | Numérico | Catálogo Mercadotecnia | Mapeado desde product_code |

---

**Entidad: CASE_CLIENTE**

| Campo | Tipo | Fuente | Notas |
|---|---|---|---|
| advertiser_id | FK | IAM | |
| case_id | ID | IAM | |
| tipo_case | Código | IAM | Mapeo contra catálogo de tipos de case |
| estatus_case | Código | IAM | Abierto / Cerrado / otros |
| fecha_apertura | Fecha | IAM | Para cálculo de antigüedad |
| fecha_cierre | Fecha | IAM | Cuando aplique |
| levantado_por | Código | IAM | Para condición 2 de CQ (cases levantados por CAC) |
| antiguedad_dias | Numérico | Calculado | (fecha actual − fecha_apertura) si abierto |

---

**Entidad: VISITAS_SITIO**

| Campo | Tipo | Fuente | Notas |
|---|---|---|---|
| advertiser_id | FK | IAM | |
| sitio_id | ID | Panel Marketing | |
| fecha_publicacion_sitio | Fecha | Panel Marketing | Para filtro "≥30 días publicados" |
| mes_medicion | Fecha | Panel Marketing | Mes al que corresponde la medición |
| visitas_mes | Numérico | Panel Marketing | Total de visitas en el mes |

---

**Entidad: RETRO_FDV**

| Campo | Tipo | Fuente | Notas |
|---|---|---|---|
| advertiser_id | FK | Pinbox | |
| fecha_contacto | Fecha | Pinbox | |
| resultado | Código | Pinbox | Para cierre automático de CQ |

---

**Entidades de referencia (catálogos)**
- `CATALOGO_SCORES_PRODUCTO` — product_code → score. Cargado desde panel HU1.7 cuando Mercadotecnia actualice
- `CATALOGO_TIPOS_CASE` — tipo_case → categoría funcional. Cargado desde "catalogo cases init source ctes ult 12m"

---

### Reglas de normalización

**1. Identificación de clientes**
El `advertiser_id` es la clave de unión entre todas las fuentes. Todo registro se relaciona a través de este identificador.

**2. Validación de campos de contacto**
Phone, cell_phone y email se marcan como válidos/inválidos al momento de la ingesta según reglas de formato definidas en HU2.2. El valor original se conserva; solo se añade el flag de validez.

**3. Productos con monto**
Se genera un flag `tiene_monto = true` por producto cuando el campo `monto > 0`. Este flag es relevante para los filtros del modelo de segmentación.

**4. Consolidación de visitas**
Las visitas de múltiples sitios del mismo cliente se suman a nivel `advertiser_id`, filtrando solo sitios con ≥30 días publicados al cierre del mes. El total se almacena como un campo consolidado por cliente.

**5. Antigüedad de cases**
Se calcula al momento de cada ingesta como diferencia entre fecha actual y fecha de apertura. Solo aplica a cases con estatus "abierto". El resultado se almacena en el campo `antiguedad_dias`.

**6. Vigencia de etiqueta manual de queja**
Se verifica la fecha de activación contra el momento del cálculo. Se genera un flag `queja_activa = true` si la activación es ≤ 3 meses. Si supera los 3 meses, el flag queda en false y el campo no se considera en CQ.

**7. Oferta del producto**
Se identifica si el producto pertenece a oferta 2024 o 2026 para permitir análisis segmentado. Este atributo no afecta la lógica del modelo de riesgo, ya que el catálogo de scores incluye ambas ofertas.

---

### Periodicidad de ejecución

| Proceso | Frecuencia | Horario sugerido |
|---|---|---|
| Extracción diaria de IAM (incremental) | Diaria | 02:00 AM |
| Extracción diaria de SAP_USER@UNOREP | Diaria | 02:30 AM |
| Extracción diaria de Pinbox | Diaria | 03:00 AM |
| Extracción mensual completa de IAM | Mensual — día 04 | 00:30 AM |
| Extracción mensual de Panel Marketing | Mensual — día 04 | 01:00 AM |
| Normalización y consolidación | Diaria y mensual | Inmediatamente después de extracciones |
| Ejecución del motor de segmentación (HU1.5) | Mensual — día 04 | 09:00 AM |

> Los horarios son sugerencias. Deben validarse con el equipo de infraestructura para no afectar ventanas de operación de los sistemas fuente.

---

### Fechas clave del primer ciclo

**Fecha objetivo del primer cálculo de segmentación:** 04 de mayo de 2026 a las 09:00 hrs, con datos a mes vencido de abril 2026.

**Carga inicial de datos históricos:** el proceso de ingesta arranca tomando datos históricos disponibles de las fuentes para garantizar que la primera ejecución del motor cuente con contexto suficiente (cases de meses previos, visitas de abril, productos vigentes, rezago actual). No se requiere calcular segmentaciones retroactivas para meses anteriores a mayo 2026.

**Excepción — Etiqueta manual de queja explícita:** esta etiqueta es un elemento nuevo que no existe actualmente en IAM. Al momento del arranque no habrá datos históricos de esta etiqueta. El primer cálculo solo considerará etiquetas manuales creadas entre el despliegue y el día 04 de mayo. La señal alcanzará efectividad plena en ciclos posteriores conforme se acumule base de etiquetas activas.

---

### Manejo de errores y reconciliación

**1. Fallo de extracción**
Si una fuente falla, el proceso registra el error, notifica al área de Sistemas y no bloquea la ejecución del resto de las fuentes. Los datos de la fuente fallida se marcan como "desactualizados" en el reporte de calidad.

**2. Reintentos**
Configuración de reintentos automáticos: máximo 3 intentos con intervalo de 15 minutos entre cada uno.

**3. Reconciliación**
Al final de cada ejecución se genera un reporte con: cantidad de registros extraídos por fuente, cantidad de registros normalizados, diferencias respecto a la ejecución anterior y errores encontrados.

**4. Impacto en el motor de segmentación**
Si al momento del cálculo mensual (HU1.5) alguna fuente tiene datos desactualizados, el motor ejecuta el cálculo con una advertencia y marca los clientes afectados con etiqueta de "datos incompletos" para revisión manual por el AR.

---

### Criterios de aceptación

**CA1 — Extracción diaria de IAM**
DADO QUE existen credenciales y acceso a IAM configurados
CUANDO se ejecuta el proceso de extracción diaria a las 02:00 AM
ENTONCES el sistema obtiene todos los cambios del día anterior en clientes, productos, cases y etiquetas, los deposita en la capa Raw con marca temporal y registra el volumen extraído.

**CA2 — Extracción de rezago desde SAP**
DADO QUE existe acceso configurado al esquema SAP_USER@UNOREP
CUANDO se ejecuta el proceso de extracción diaria
ENTONCES el sistema obtiene la tabla de rezago actualizada y la deposita en la capa Raw.

**CA3 — Extracción mensual de visitas**
DADO QUE existe acceso configurado a Panel Marketing
CUANDO se ejecuta el proceso de extracción el día 04 del mes
ENTONCES el sistema obtiene las visitas del mes anterior por sitio, filtra únicamente los sitios con ≥30 días de publicación al cierre del mes y las deposita en la capa Raw.

**CA4 — Normalización y consolidación**
DADO QUE los datos están en la capa Raw
CUANDO se ejecuta el proceso de normalización
ENTONCES el sistema aplica las reglas de mapeo, validación y consolidación, genera las entidades del modelo unificado y las deposita en la capa Analytical lista para consumo.

**CA5 — Unificación por advertiser_id**
DADO QUE un cliente tiene información en múltiples fuentes (IAM, SAP, Panel Marketing, Pinbox)
CUANDO se ejecuta la normalización
ENTONCES toda la información queda relacionada al mismo advertiser_id y puede consultarse como una vista integrada del cliente.

**CA6 — Cálculo de antigüedad de cases**
DADO QUE un case está en estatus abierto
CUANDO se ejecuta la normalización
ENTONCES el sistema calcula la antigüedad en días (fecha actual − fecha de apertura) y la almacena en el campo `antiguedad_dias`.

**CA7 — Suma de visitas por advertiser**
DADO QUE un cliente tiene múltiples sitios con visitas medidas
CUANDO se consolida la información
ENTONCES el sistema suma las visitas de todos los sitios del cliente que cumplen el criterio "≥30 días publicados" y genera un total mensual a nivel `advertiser_id`.

**CA8 — Mapeo de scores de productos**
DADO QUE un cliente tiene productos asignados en IAM
CUANDO se ejecuta la normalización
ENTONCES cada producto queda mapeado contra el catálogo de scores cargado desde el panel HU1.7, asignando el score correspondiente al `product_code`.

**CA9 — Detección de producto no mapeado**
DADO QUE un cliente tiene un producto cuyo `product_code` no existe en el catálogo de scores
CUANDO se ejecuta la normalización
ENTONCES el sistema registra una alerta indicando el `product_code` sin mapeo, asigna temporalmente score 0 al producto y genera un reporte para Mercadotecnia.

**CA10 — Manejo de fallo en una fuente**
DADO QUE una de las fuentes falla durante la extracción
CUANDO se intentan los 3 reintentos y todos fallan
ENTONCES el sistema: notifica a Sistemas, marca los datos de esa fuente como desactualizados, continúa con la normalización de las demás fuentes y registra el incidente en el reporte de reconciliación.

**CA11 — Reporte de reconciliación**
DADO QUE se ejecutó un ciclo de ingesta completo
CUANDO finaliza el proceso
ENTONCES el sistema genera un reporte con: fuentes procesadas, registros extraídos por fuente, registros normalizados, errores encontrados, comparación con la ejecución anterior y datos marcados como desactualizados.

**CA12 — Contrato de datos para consumidores**
DADO QUE HU1.5 (motor de segmentación), HU3.1 (tablero) u otras historias necesitan consumir datos
CUANDO realizan sus consultas
ENTONCES lo hacen contra la capa Analytical, nunca directamente contra las fuentes originales, garantizando consistencia de criterios entre todos los componentes.

**CA13 — Carga inicial histórica**
DADO QUE el sistema se despliega por primera vez
CUANDO se ejecuta la carga inicial
ENTONCES el sistema extrae y normaliza los datos históricos disponibles de IAM, SAP_USER@UNOREP, Panel Marketing y Pinbox necesarios para soportar el primer cálculo de segmentación el 04 de mayo de 2026, sin ejecutar cálculos retroactivos de segmentación.

---

### Supuestos y limitaciones aceptadas

1. Señal de queja manual madura progresivamente: la efectividad del segmento CQ vía etiqueta manual será parcial durante los primeros 3 meses de operación. Las condiciones 1 y 2 de CQ (cantidad de cases) no tienen esta limitación y operarán con efectividad plena desde el primer ciclo
2. Identidad del cliente: el `advertiser_id` es el identificador único. Cambios de razón social pueden generar distorsión en métricas históricas (TR-01 aceptado)

---

### Dependencias

- **Bloqueante:** acceso técnico a IAM (lectura directa o réplica)
- **Bloqueante:** acceso técnico al esquema SAP_USER@UNOREP
- **Bloqueante:** acceso técnico a Panel Marketing (API o extracción programada)
- **Bloqueante:** acceso técnico a Pinbox
- **Bloqueante:** catálogo de scores de Mercadotecnia (113 productos) para carga inicial
- **No bloqueante:** archivo "catalogo cases init source ctes ult 12m" (para catálogo de tipos de case)
- **No bloqueante:** HU1.7 operativa (para actualizaciones posteriores del catálogo de scores desde el panel)

---

# F2.HU2.2 — Calidad de datos

**Identificación**
- Feature: F2 — Infraestructura de Datos
- Historia: HU2.2 | Versión: 2.0
- Rol principal: Analista de Retención (AR) / Sistemas (IT)
- Roles consumidores: Retención, Sistemas, Motor de Segmentación

---

### Necesidad de negocio

Como Analista de Retención, necesito que el sistema detecte automáticamente datos faltantes, incompletos o atípicos en las fuentes que alimentan el motor de segmentación, para evitar que un cliente sea clasificado incorrectamente por mala calidad de información y poder solicitar corrección temprana antes de que impacte las acciones de contacto.

---

### Resultado esperado

Un mecanismo de monitoreo continuo que:
- Valida la calidad de los datos en cada ciclo de ingesta
- Genera alertas cuando se detectan problemas, agrupadas por severidad
- Etiqueta a los clientes afectados como "riesgo indeterminado" cuando aplique
- Expone un reporte de calidad que permite dar seguimiento a la remediación

---

### Contexto y justificación

El modelo de segmentación (HU1.5) es altamente sensible a la calidad de los datos de entrada:
- Si un cliente no tiene teléfono o email válidos, no puede ser contactado aunque esté en alto riesgo
- Si las visitas del sitio no se pudieron extraer de Panel Marketing, el segmento FL no puede calcularse correctamente para ese cliente
- Si el rezago no se actualizó desde SAP_USER@UNOREP, el segmento SP puede generar falsos negativos
- Si un `product_code` del cliente no existe en el catálogo de scores, el cálculo del score total queda incompleto
- Si la fecha de última contratación está vacía o es atípica, la condición del segmento CS no puede evaluarse

Sin un mecanismo de calidad de datos, el modelo clasifica clientes sobre información parcial y produce falsos positivos o negativos que degradan la efectividad del programa.

---

### Dimensiones de calidad evaluadas

1. **Completitud:** el dato existe y no es nulo/vacío
2. **Validez de formato:** el dato cumple el formato esperado (email con @, teléfono con dígitos suficientes, fecha parseable)
3. **Consistencia entre fuentes:** datos que deben coincidir entre fuentes realmente coinciden
4. **Frescura (actualización):** el dato fue actualizado dentro del plazo esperado según la frecuencia de extracción
5. **Valores atípicos:** detección de outliers que sugieren errores de captura

---

### Reglas de calidad por campo

**Campos críticos del CLIENTE**

| Campo | Regla | Nivel de severidad |
|---|---|---|
| advertiser_id | No nulo, único en el universo | Crítico |
| nombre_cliente | No nulo, longitud > 2 caracteres | Alto |
| phone O cell_phone | Al menos uno no nulo, formato válido (10 dígitos numéricos, sin letras) | Alto |
| email | Formato válido (contiene @, dominio válido) si no es nulo | Medio |
| fecha_ultima_contratacion | No nula, fecha parseable, ≤ fecha actual | Alto |

**Campos críticos de PRODUCTO_CLIENTE**

| Campo | Regla | Nivel de severidad |
|---|---|---|
| product_code | No nulo, existe en catálogo de scores | Crítico |
| product_status | No nulo, valor dentro de catálogo (Live / In Process / Draft / Suspended / Cancelado / otros) | Crítico |
| monto | Numérico, ≥ 0 | Alto |
| score_producto | No nulo después del mapeo | Crítico |

**Campos críticos de CASE_CLIENTE**

| Campo | Regla | Nivel de severidad |
|---|---|---|
| tipo_case | No nulo, existe en catálogo de tipos de case | Alto |
| estatus_case | No nulo | Crítico |
| fecha_apertura | No nula, fecha parseable, ≤ fecha actual | Crítico |

**Campos críticos de VISITAS_SITIO**

| Campo | Regla | Nivel de severidad |
|---|---|---|
| visitas_mes | Numérico, ≥ 0, < 1,000,000 | Medio |
| fecha_publicacion_sitio | No nula, fecha parseable | Alto |
| mes_medicion | No nula, corresponde al mes esperado | Crítico |

**Campos críticos de RETRO_FDV**

| Campo | Regla | Nivel de severidad |
|---|---|---|
| fecha_contacto | No nula, fecha parseable | Alto |
| resultado | Valor dentro de catálogo definido | Medio |

---

### Reglas de consistencia entre fuentes

**1. IAM vs SAP:** un `advertiser_id` que aparece con rezago en SAP debe existir en IAM. Si no existe, se registra alerta de severidad Alta.

**2. IAM vs Panel Marketing:** un sitio con visitas debe pertenecer a un `advertiser_id` existente en IAM con un producto de tipo sitio activo. Si no, se registra alerta de severidad Alta y se descarta el registro de la capa Analytical.

**3. IAM vs Catálogo de productos:** todos los `product_code` de clientes activos deben existir en el catálogo de scores. Si no, se registra alerta crítica y el producto se marca con score 0 temporal (ver CA3).

**4. IAM vs Pinbox:** un registro de retroalimentación en Pinbox debe corresponder a un `advertiser_id` existente con un case de tipo CQ previo. Si no, se registra alerta de severidad Media.

---

### Reglas de frescura

| Fuente | Frescura esperada | Umbral de alerta |
|---|---|---|
| IAM (extracción diaria) | ≤ 24 horas | Alerta Crítica si > 48 horas |
| SAP_USER@UNOREP (extracción diaria) | ≤ 24 horas | Alerta Crítica si > 48 horas |
| Panel Marketing (extracción mensual) | ≤ 3 días después del cierre de mes | Alerta Crítica si > 5 días |
| Pinbox (extracción diaria) | ≤ 24 horas | Alerta Crítica si > 48 horas |

---

### Detección de valores atípicos

Se implementan reglas simples de outliers basadas en umbrales fijos (no estadísticos en esta fase):

| Campo | Rango razonable | Se considera outlier si... |
|---|---|---|
| valor_contrato (suma de productos) | 0 a 10,000,000 MXN | Fuera de rango |
| score cliente (suma) | 0 a 500 | > 500 |
| visitas_mes por sitio | 0 a 500,000 | > 500,000 |
| cantidad de cases abiertos por cliente | 0 a 50 | > 50 |
| cantidad de productos por cliente | 1 a 100 | > 100 |

> En fases posteriores estos umbrales pueden migrarse a detección estadística (desviaciones estándar sobre la distribución real). Para el MVP se usan umbrales fijos revisables en el panel HU1.7.

---

### Mecanismo de alertas

Cada evento de calidad registra los siguientes atributos:
- Fecha/hora de detección
- Fuente afectada
- Campo afectado
- Regla violada
- Nivel de severidad: Crítico / Alto / Medio
- Cantidad de registros afectados
- Muestra de registros representativos
- Estado: Abierto / En revisión / Resuelto / Aceptado

**Agregación de alertas:** si múltiples clientes tienen el mismo problema (ej: 500 clientes con email inválido), se genera una sola alerta agregada con el conteo total y una muestra representativa, no alertas individuales.

**Canales de notificación según severidad:**
- **Crítico:** notificación inmediata al área de Sistemas (email corporativo o Teams) + entrada en el reporte de calidad
- **Alto:** entrada en el reporte de calidad del siguiente ciclo + notificación diaria consolidada a Sistemas
- **Medio:** solo en el reporte de calidad mensual

**Tasa de nulos agregada:** adicionalmente, el sistema calcula la tasa de nulos por campo y por fuente en cada ciclo de ingesta. Si la tasa supera un umbral configurable (por defecto: 5% para campos Críticos, 10% para campos Altos), se dispara una alerta aunque los registros individuales no la hayan generado.

---

### Condiciones para etiquetado como "riesgo indeterminado"

Un cliente se etiqueta como **riesgo indeterminado** cuando se cumple al menos una de estas condiciones:

1. Tiene algún producto activo con `product_code` no mapeado en el catálogo de scores
2. Tiene `fecha_ultima_contratacion` nula o inválida
3. Los datos de la fuente que determina su segmento no pudieron extraerse (ej: Panel Marketing falló y el cliente es candidato a FL)
4. Tiene cases con `fecha_apertura` nula o inválida

**Tratamiento de clientes con "riesgo indeterminado":**
- No reciben campañas automáticas mientras persista la condición
- Aparecen en sección específica del tablero (HU3.1) para que el AR pueda revisarlos manualmente
- Se incluyen en el reporte de calidad con detalle del problema
- Se recalculan en el siguiente ciclo una vez que los datos se corrijan en la fuente original

---

### Estructura del reporte de calidad

El reporte se genera al final de cada ciclo de ingesta (diario y mensual) con la siguiente estructura:

**Sección 1 — Resumen ejecutivo**
- Fecha del reporte
- Total de clientes procesados
- Total de clientes con datos completos
- Total de clientes con "riesgo indeterminado" (con desglose por causa)
- Porcentaje de completitud global

**Sección 2 — Alertas abiertas**
- Listado de eventos de calidad por nivel de severidad
- Fuente y campo afectado
- Cantidad de registros afectados
- Tendencia respecto al ciclo anterior (mejora / estable / degradación)

**Sección 3 — Tasa de nulos por campo crítico**
- Tabla con % de nulos por campo
- Comparativa con ciclos anteriores
- Indicador de tendencia

**Sección 4 — Recomendaciones de remediación**
- Lista priorizada de acciones sugeridas para Sistemas u otros responsables

---

### Criterios de aceptación

**CA1 — Validación de completitud y formato**
DADO QUE los datos se procesan en la capa de normalización
CUANDO un campo no cumple la regla de completitud o formato definida
ENTONCES el sistema registra un evento de calidad con severidad según la tabla de reglas e incluye el advertiser_id afectado.

**CA2 — Detección de teléfono y email inválidos**
DADO QUE el campo phone, cell_phone o email no cumple el formato esperado
CUANDO se procesa el cliente
ENTONCES el sistema marca esos campos como "inválidos" en el modelo unificado sin eliminar el valor original y genera una alerta agregada.

**CA3 — Detección de product_code no mapeado**
DADO QUE un cliente tiene un producto cuyo product_code no existe en el catálogo de scores
CUANDO se ejecuta la normalización
ENTONCES el sistema: (1) asigna score 0 temporal al producto, (2) marca al cliente como "riesgo indeterminado", (3) registra una alerta Crítica y (4) incluye el product_code en el reporte dirigido a Mercadotecnia.

**CA4 — Validación de consistencia entre fuentes**
DADO QUE se ejecuta la normalización
CUANDO se detecta un registro inconsistente entre fuentes (ej: sitio en Panel Marketing sin advertiser_id correspondiente en IAM)
ENTONCES el sistema registra una alerta con severidad Alta y descarta el registro inconsistente de la capa Analytical.

**CA5 — Validación de frescura de fuentes**
DADO QUE finalizó un ciclo de extracción
CUANDO una fuente no se actualizó dentro de su plazo esperado
ENTONCES el sistema genera una alerta Crítica de frescura y marca los datos de esa fuente como "desactualizados" en el reporte de calidad.

**CA6 — Detección de valores atípicos**
DADO QUE un valor numérico está fuera del rango razonable definido
CUANDO se ejecuta la normalización
ENTONCES el sistema registra una alerta de outlier con severidad Media y conserva el valor marcándolo con flag "atípico" para revisión manual.

**CA7 — Tasa de nulos agregada**
DADO QUE finalizó la normalización
CUANDO la tasa de nulos de un campo Crítico supera el 5% (configurable)
ENTONCES el sistema genera una alerta Crítica indicando el campo, la tasa actual y la tasa del ciclo anterior.

**CA8 — Etiquetado de riesgo indeterminado**
DADO QUE un cliente cumple al menos una condición de las definidas para "riesgo indeterminado"
CUANDO se ejecuta la segmentación
ENTONCES el cliente recibe la etiqueta "riesgo indeterminado" en lugar de una etiqueta normal y aparece en la sección correspondiente del tablero.

**CA9 — Agregación de alertas similares**
DADO QUE múltiples registros presentan el mismo tipo de problema
CUANDO se generan las alertas
ENTONCES el sistema las agrupa en un único evento con el conteo de registros afectados y una muestra representativa.

**CA10 — Notificación por severidad**
DADO QUE se genera un evento de calidad
CUANDO el evento es de severidad Crítica
ENTONCES el sistema envía notificación inmediata a Sistemas. Si es Alta, lo incluye en el consolidado diario. Si es Media, solo en el reporte mensual.

**CA11 — Reporte de calidad al cierre de ciclo**
DADO QUE finalizó un ciclo de ingesta
CUANDO se genera el reporte de calidad
ENTONCES el reporte incluye: resumen ejecutivo, alertas abiertas por severidad, tasa de nulos por campo crítico, comparativa con ciclos previos y recomendaciones de remediación.

**CA12 — Recálculo automático tras corrección**
DADO QUE un cliente fue etiquetado como "riesgo indeterminado" por datos incompletos
CUANDO los datos se corrigen en la fuente original y el siguiente ciclo los extrae correctamente
ENTONCES el sistema recalcula la segmentación del cliente en el siguiente ciclo y le asigna su etiqueta correspondiente, eliminando la etiqueta de riesgo indeterminado.

**CA13 — Consulta del reporte por parte del AR**
DADO QUE el rol Analista de Retención accede al reporte de calidad
CUANDO consulta el reporte del ciclo actual
ENTONCES puede ver el resumen ejecutivo, filtrar por severidad y fuente y descargar el listado completo de clientes etiquetados como "riesgo indeterminado".

---

### Supuestos y limitaciones aceptadas

1. No se corrigen datos automáticamente: el sistema detecta y reporta, pero no modifica datos en las fuentes originales. La corrección es responsabilidad del área dueña del dato
2. Outliers con umbrales fijos en MVP: la detección estadística (z-score, IQR) se considera para fases posteriores
3. Clientes con riesgo indeterminado no reciben acción automática hasta que se corrijan sus datos
4. Notificaciones vía canal único: no se implementa routing complejo de notificaciones a distintos responsables en el MVP
5. El AR no puede editar datos desde el tablero: ante un "riesgo indeterminado", el AR solo puede reportar al área responsable, no corregir directamente
6. Validación de email y teléfono es formal, no funcional: se valida formato pero no se verifica que el email existe o el teléfono está activo (eso requeriría servicios externos)

---

### Dependencias

- **Bloqueante:** HU2.1 en operación (la calidad de datos se ejecuta sobre el pipeline de ingesta)
- **Bloqueante:** canal de notificación definido (email corporativo o Teams de Sistemas)
- **No bloqueante:** reglas de calidad iniciales pueden cargarse hardcoded y migrarse al panel HU1.7 en iteración posterior
- **No bloqueante:** tablero de visualización del reporte puede ser un reporte exportable en primera iteración si el tablero no está listo

---

# DOCUMENTO v3.0 — PARTE 4 de 4 (FINAL)
## F3 — Consumo Operativo del Resultado (HU3.1 a HU3.5)
## F4 — Medición y Desempeño del Modelo (HU4.1 a HU4.3)

---

# F3.HU3.1 — Consultar cartera priorizada de clientes en riesgo

**Identificación**
- Feature: F3 — Consumo Operativo del Resultado
- Historia: HU3.1 | Versión: 3.0
- Rol principal: Usuario de negocio (Retención / Operación Comercial)
- Roles consumidores: Retención, Operación Comercial, Supervisión

---

### Necesidad de negocio

Como usuario de retención, necesito consultar la cartera vigente de clientes clasificados con riesgo accionable, para identificar rápidamente a quién atender primero, en qué orden y con qué contexto mínimo, priorizando la gestión operativa sobre los clientes con mayor necesidad de intervención.

---

### Resultado esperado

Una vista operativa de cartera priorizada que permita:
- Consultar únicamente clientes con clasificación accionable
- Excluir por defecto clientes de baja prioridad
- Ordenar la cartera por prioridad operativa
- Ordenar clientes dentro de cada grupo por valor comercial
- Visualizar contexto mínimo para decidir atención
- Habilitar gestión operativa inmediata sin reinterpretar el modelo

---

### Universo de datos mostrado

El tablero muestra todos los clientes activos del último ciclo de segmentación ejecutado, incluyendo: clientes en segmentos VP, CQ, SP, FL, TA, CS y RB, más los clientes etiquetados como "riesgo indeterminado" en sección separada.

No se muestran: clientes excluidos del universo de cálculo (sin productos válidos) ni clientes dados de baja completa.

---

### Estructura del tablero — Tres zonas

**Zona 1 — Resumen ejecutivo (encabezado)**

Indicadores agregados del ciclo actual:
- Total de clientes en la base activa
- Distribución por nivel de riesgo (Alto / Medio / Bajo / Revisión / Indeterminado)
- Distribución por etiqueta (VP / CQ / SP / FL / TA / CS / RB)
- Clientes con "riesgo indeterminado"
- Fecha del último cálculo de segmentación
- Versión de parámetros utilizada (referencia a HU1.7)
- Comparativa con el ciclo anterior (variación en cada segmento)

**Zona 2 — Filtros y controles**

Panel de filtros aplicables a la lista (detallado en la sección de filtros).

**Zona 3 — Lista priorizada de clientes**

Tabla principal con columnas definidas a continuación.

---

### Columnas de la lista priorizada

**Columnas principales (visibles por defecto)**

| Columna | Origen | Tipo | Notas |
|---|---|---|---|
| advertiser_id | Modelo unificado | ID | Identificador del cliente |
| nombre_cliente | Modelo unificado | Texto | |
| etiqueta | HU1.5 | Badge | VP, CQ, SP, FL, TA, CS, RB |
| nivel_riesgo | HU1.5 | Badge con color | Alto (rojo), Medio (amarillo), Bajo (verde), Revisión (azul) |
| score | HU1.5 | Numérico | Score total del cliente |
| valor_contrato | Modelo unificado | Moneda | Suma de productos vigentes |
| antiguedad | Modelo unificado | Texto | Desde fecha_ultima_contratacion |
| accion_asignada | HU1.5 | Texto | Envío campaña / CAC / Ventas / Sin acción |
| estado_contacto | Bitácora HU3.3 | Badge | Pendiente / En progreso / Contactado / Sin respuesta |

**Columnas secundarias (visibles al expandir o configurar)**

| Columna | Origen | Tipo |
|---|---|---|
| nombre_agente | Modelo unificado | Texto |
| nombre_supervisor | Modelo unificado | Texto |
| division | Modelo unificado | Código |
| nombre_division | Modelo unificado | Texto |
| town_name (población) | Modelo unificado | Texto |
| tiene_campana_digital | Modelo unificado | Booleano |
| cantidad_productos_activos | Modelo unificado | Numérico |
| tiene_rezago | Modelo unificado | Booleano |
| cantidad_cases_abiertos | Modelo unificado | Numérico |
| visitas_mes | Modelo unificado | Numérico |
| fecha_ultima_contratacion | Modelo unificado | Fecha |
| esquema_pago | Modelo unificado | Texto |
| offer (oferta 2024 vs 2026) | Modelo unificado | Texto |

---

### Filtros disponibles

**Filtros de segmentación**
- Nivel de riesgo (multi-selección: Alto, Medio, Bajo, Revisión, Riesgo indeterminado)
- Etiqueta (multi-selección: VP, CQ, SP, FL, TA, CS, RB)
- Acción asignada (multi-selección)

**Filtros de valor y score**
- Rango de valor_contrato (slider con mín/máx)
- Rango de score (slider)

**Filtros operativos**
- División (multi-selección)
- Población (búsqueda con autocompletado)
- Agente / Supervisor (búsqueda con autocompletado)
- Tiene campaña digital (Sí/No)
- Esquema de pago (Suscripción / Periodo forzoso / PPA)
- Oferta (2024 / 2026)

**Filtros financieros**
- Tiene rezago (Sí/No)
- Saldo pendiente (rango, si está disponible)
- Estatus crediticio (si está disponible)

**Filtros de antigüedad**
- Antigüedad desde fecha_ultima_contratacion: <6 meses, 6-12 meses, 1-2 años, >2 años

**Filtros de estado de contacto**
- Estado de contacto (Pendiente / En progreso / Contactado / Sin respuesta)
- Último canal utilizado

---

### Ordenamiento

**Orden por defecto:**
1. Nivel de riesgo (Alto > Medio > Revisión > Bajo > Indeterminado)
2. Dentro de cada nivel, por valor_contrato descendente
3. Dentro del mismo valor_contrato, por score descendente

**Cartera accionable por defecto:** la vista inicial excluye clientes RB. RB permanece disponible mediante acción explícita del usuario, pero no forma parte del flujo principal de atención.

**Ordenamientos alternativos disponibles:**
- Por fecha de último contacto (más antiguos primero)
- Por antigüedad del cliente
- Por cantidad de cases abiertos
- Alfabético por nombre del cliente

---

### Vista de detalle del cliente

Al hacer clic sobre un cliente se abre un panel lateral o modal con el detalle completo organizado en 7 secciones:

**Sección 1 — Identificación**
advertiser_id, nombre del cliente, datos de contacto (tel, cel, email), agente, supervisor, división y población.

**Sección 2 — Clasificación actual**
Etiqueta y nivel de riesgo con badge de color. Explicación funcional de la clasificación: *"Este cliente fue clasificado como [etiqueta] porque [condición específica que disparó la etiqueta]"*. Score total y desglose por producto. Acción asignada.

**Sección 3 — Productos**
Listado de productos vigentes con: estatus, monto, vigencia, esquema de pago, indicador de tipo (campaña digital, sitio, listado, etc.) y score individual por producto.

**Sección 4 — Señales de riesgo**
Cases abiertos (tipo, antigüedad en días, levantado por). Rezago (sí/no, monto si aplica). Visitas del mes con comparativa de meses previos si hay histórico disponible. Etiqueta manual de queja si aplica, con fecha de activación y vigencia restante.

**Sección 5 — Histórico de segmentación**
Tabla con los últimos 3 a 6 ciclos: fecha, etiqueta, nivel de riesgo y score. Permite identificar si el cliente se está deteriorando o mejorando.

**Sección 6 — Histórico de contacto**
Últimos intentos de gestión registrados (cuando HU3.3 esté operativa): canal utilizado, estado de cada interacción y resultado obtenido.

**Sección 7 — Acciones disponibles**
- Botón "Marcar como contactado manualmente"
- Botón "Registrar intento de gestión" (invoca HU3.3)
- Botón "Exportar detalle del cliente"

---

### Perfiles de acceso

| Rol | Acceso | Alcance de la vista |
|---|---|---|
| Analista de Retención (AR) | Sí | Todos los clientes |
| Coordinador de Operaciones (OP) | Sí | Todos los clientes |
| Gerente de Estrategia (GE) | Sí | Todos los clientes + panel de métricas consolidadas |
| Ejecutivo / CAC | Sí | Solo clientes asignados |
| Product Owner (PO) | Sí | Todos los clientes (solo lectura) |
| Sistemas (IT) | Sí | Todos los clientes (para diagnóstico) |
| Otros usuarios | No | — |

---

### Actualización de datos en el tablero

- **Datos de segmentación:** actualizados mensualmente al cierre del ciclo (día 04 del mes a las 09:00 hrs)
- **Datos de contacto (bitácora):** actualizados en tiempo casi real cuando HU3.3 esté operativa
- **Datos de clientes (contacto, productos):** actualizados diariamente según periodicidad de HU2.1

El tablero muestra claramente la fecha y hora de última actualización por cada tipo de dato para que el usuario entienda la frescura de lo que consulta.

---

### Requisitos de performance

- Respuesta a filtros y ordenamientos en menos de **3 segundos** para una base de hasta 50,000 clientes
- Vista de detalle del cliente carga en menos de **2 segundos**
- Paginación automática si el resultado filtrado supera 500 registros, con indicador del total

---

### Criterios de aceptación

**CA1 — Consulta de cartera vigente**
DADO QUE existe un resultado vigente publicado
CUANDO el usuario consulta la cartera operativa
ENTONCES visualiza la cartera oficial del ciclo vigente.

**CA2 — Resumen ejecutivo visible**
DADO QUE existe un ciclo de segmentación ejecutado
CUANDO el usuario entra al tablero
ENTONCES ve en el encabezado: total de clientes, distribución por nivel de riesgo y etiqueta, clientes con riesgo indeterminado, fecha del último cálculo, versión de parámetros y comparativa con el ciclo anterior.

**CA3 — Exclusión de RB por defecto**
DADO QUE el usuario consulta la cartera priorizada
CUANDO accede a la vista inicial
ENTONCES visualiza únicamente clientes con clasificación accionable y no ve clientes RB por defecto.

**CA4 — Consulta extendida de RB**
DADO QUE el usuario requiere consultar clientes de baja prioridad
CUANDO realiza una acción explícita de ampliación de cartera
ENTONCES puede incluir clientes RB en la consulta.

**CA5 — Orden principal por prioridad**
DADO QUE el usuario consulta la cartera
CUANDO el sistema presenta los resultados
ENTONCES ordena por nivel de riesgo primero y por valor_contrato descendente dentro de cada grupo.

**CA6 — Contexto mínimo visible**
DADO QUE el usuario consulta clientes priorizados
CUANDO visualiza la cartera
ENTONCES dispone de cliente, clasificación, prioridad, valor comercial, motivo principal y vigencia del resultado.

**CA7 — Vista de detalle del cliente**
DADO QUE el usuario hace clic sobre un cliente en la lista
CUANDO se abre la vista de detalle
ENTONCES visualiza las 7 secciones definidas: identificación, clasificación con explicación funcional, productos, señales de riesgo, histórico de segmentación, histórico de contacto y acciones disponibles.

**CA8 — Explicación funcional de la clasificación**
DADO QUE un cliente está en la vista de detalle
CUANDO se consulta la sección "Clasificación actual"
ENTONCES se muestra un texto explicativo que indica por qué el cliente fue clasificado en su etiqueta (ej: "Clasificado como CQ porque tiene 4 cases abiertos del mes en tipos de case válidos").

**CA9 — Filtrado multidimensional**
DADO QUE el usuario aplica uno o varios filtros
CUANDO combina filtros de nivel de riesgo, valor, segmento y otros
ENTONCES la lista se actualiza mostrando solo los clientes que cumplen todas las condiciones y el resumen recalcula los totales del subconjunto filtrado.

**CA10 — Sección de clientes con riesgo indeterminado**
DADO QUE existen clientes etiquetados como "riesgo indeterminado"
CUANDO el usuario navega a la sección correspondiente
ENTONCES ve el listado con la razón específica del etiquetado y puede tomar acciones de seguimiento.

**CA11 — Histórico de segmentación del cliente**
DADO QUE existen al menos 2 ciclos de segmentación ejecutados
CUANDO se consulta la vista de detalle de un cliente
ENTONCES la sección "Histórico de segmentación" muestra la evolución del cliente en los últimos 3 a 6 ciclos con etiqueta, nivel y score por ciclo.

**CA12 — Performance de la lista**
DADO QUE la base activa tiene hasta 50,000 clientes
CUANDO el usuario aplica filtros u ordenamientos
ENTONCES el resultado se muestra en menos de 3 segundos.

**CA13 — Indicador de frescura de datos**
DADO QUE el usuario abre el tablero
CUANDO consulta cualquier sección
ENTONCES ve claramente las marcas de última actualización de los datos (segmentación, bitácora, datos del cliente).

---

### Supuestos y limitaciones aceptadas

1. Tablero web responsivo: la interfaz funciona en desktop principalmente. Mobile es deseable pero no bloqueante para MVP
2. Datos de bitácora dependen de HU3.3: hasta que esté operativa, las columnas y secciones de estado de contacto se muestran vacías o con placeholder
3. Histórico limitado en arranque: en el primer ciclo (04 de mayo) no hay histórico disponible. La sección se llena progresivamente con cada ciclo mensual
4. Sin edición desde el tablero: el AR no puede modificar datos del cliente desde el tablero
5. Autenticación corporativa: se asume integración con SSO existente de la organización

---

# F3.HU3.2 — Consultar detalle de clasificación y trazabilidad del cliente

**Identificación**
- Feature: F3 — Consumo Operativo del Resultado
- Historia: HU3.2 | Versión: 2.0
- Rol principal: Usuario de negocio (Retención / Operación Comercial)
- Roles consumidores: Retención, Operación Comercial, Supervisión

---

### Necesidad de negocio

Como usuario de retención, necesito consultar el detalle de clasificación de un cliente, para entender por qué fue priorizado, qué evidencia sustenta su resultado y con qué contexto operativo debo abordarlo antes de iniciar una gestión.

---

### Resultado esperado

Una vista de detalle por cliente que permita:
- Entender la clasificación vigente del cliente
- Conocer el motivo principal de su clasificación
- Consultar señales secundarias relevantes que explican el resultado
- Visualizar evidencia funcional del modelo sin complejidad técnica
- Consultar contexto operativo mínimo para decidir la gestión

---

### Reglas de negocio

**1.** La consulta se realiza a nivel cliente sobre el resultado vigente del ciclo publicado. La vista representa la explicación operativa del resultado actual.

**2. Alcance del detalle explicativo:** la vista muestra únicamente la evidencia que explica la clasificación vigente: clasificación final vigente, motivo principal y señales secundarias relevantes. No se muestran señales descartadas, reglas no activadas ni caminos no tomados por el modelo.

**3. Motivo principal:** representa la condición dominante que activó la clasificación final. Debe ser comprensible para negocio y suficiente para justificar la priorización.

**4. Señales secundarias relevantes:** solo se muestran señales con valor explicativo para la gestión. No reemplazan la clasificación principal ni alteran la prioridad del cliente.

**5. Contexto operativo complementario:** además de la explicación del resultado, la vista incluye: saldo pendiente, estatus crediticio, antigüedad del cliente (fecha desde que se factura) y población / municipio del cliente.

---

### Criterios de aceptación

**CA1 — Consulta de detalle vigente**
DADO QUE el usuario selecciona un cliente de la cartera vigente
CUANDO consulta su detalle
ENTONCES visualiza el detalle correspondiente al resultado vigente publicado del cliente.

**CA2 — Clasificación visible**
DADO QUE el usuario consulta el detalle del cliente
CUANDO visualiza el resultado
ENTONCES identifica código, nombre funcional y prioridad de la clasificación vigente.

**CA3 — Motivo principal visible**
DADO QUE el cliente tiene una clasificación asignada
CUANDO el usuario consulta el detalle
ENTONCES visualiza el motivo principal que explica su clasificación de forma comprensible para negocio.

**CA4 — Señales secundarias relevantes**
DADO QUE el cliente presenta señales complementarias relevantes
CUANDO el usuario consulta el detalle
ENTONCES visualiza únicamente señales secundarias con valor explicativo para gestión.

**CA5 — Exclusión de señales no explicativas**
DADO QUE el modelo evaluó señales no activadas o descartadas
CUANDO el usuario consulta el detalle
ENTONCES dichas señales no se muestran en la vista operativa del cliente.

**CA6 — Contexto operativo visible**
DADO QUE el usuario consulta el detalle del cliente
CUANDO revisa su contexto operativo
ENTONCES visualiza saldo pendiente, estatus crediticio, antigüedad y población / municipio.

**CA7 — Consumo operativo inmediato**
DADO QUE el usuario consulta el detalle del cliente
CUANDO revisa la vista explicativa
ENTONCES puede entender por qué fue priorizado y con qué contexto debe gestionarlo sin necesidad de interpretar el modelo.

---

### Exclusiones

Esta historia no: recalcula clasificación, reevalúa señales, muestra reglas descartadas, expone lógica técnica del motor, ejecuta gestión ni modifica prioridad.

---

# F3.HU3.3 — Registrar gestión y seguimiento de retención del cliente

**Identificación**
- Feature: F3 — Consumo Operativo del Resultado
- Historia: HU3.3 | Versión: 2.0
- Rol principal: Usuario de negocio (Retención / Operación Comercial)
- Roles consumidores: Retención, Operación Comercial, Supervisión

---

### Necesidad de negocio

Como usuario de retención, necesito registrar el resultado de cada intento de gestión realizado sobre un cliente priorizado, para dejar trazabilidad operativa de seguimiento, dar continuidad a la atención y conocer el histórico de intentos realizados dentro del ciclo.

---

### Resultado esperado

Una capacidad de registro operativo que permita:
- Registrar el resultado de cada intento de gestión sobre un cliente
- Conservar el histórico de intentos realizados en el ciclo
- Identificar el estado operativo de seguimiento del cliente
- Dar continuidad a la gestión sin perder trazabilidad
- Convertir la clasificación en seguimiento operativo documentado

---

### Reglas de negocio

**1. Unidad funcional de registro:** a nivel cliente e intento. Cada intento de gestión sobre un cliente se registra como un evento independiente. Un cliente puede tener múltiples registros dentro del mismo ciclo.

**2. Resultado de gestión permitido:** cada intento registra únicamente uno de estos tres valores: **contactado / no contactado / reagendar**. No se permiten otros resultados en este alcance.

**3. Regla de registro de intentos:** cada intento se registra de manera independiente. Un nuevo intento no reemplaza ni sobrescribe intentos anteriores. Cada registro representa un evento nuevo de seguimiento.

**4. Histórico de gestión:** el sistema conserva el histórico completo de intentos registrados por cliente dentro del ciclo. El usuario puede consultar la secuencia de intentos realizados.

**5. Continuidad operativa:** el registro de gestión permite continuidad de seguimiento sobre el cliente dentro del mismo ciclo. La operación puede identificar que el cliente ya tuvo intentos previos y continuar su atención con base en ese histórico.

**6. Trazabilidad operativa:** cada intento registrado permite identificar al menos: cliente gestionado, resultado del intento, fecha de registro del intento y secuencia de intentos en el ciclo.

---

### Criterios de aceptación

**CA1 — Registro de intento**
DADO QUE un usuario gestiona un cliente priorizado
CUANDO registra una gestión
ENTONCES el sistema registra un nuevo intento de gestión para ese cliente.

**CA2 — Resultado permitido**
DADO QUE el usuario registra un intento de gestión
CUANDO selecciona el resultado
ENTONCES solo puede registrar uno de estos valores: contactado, no contactado o reagendar.

**CA3 — Múltiples intentos por cliente**
DADO QUE un cliente requiere más de un intento de gestión
CUANDO el usuario registra nuevos intentos
ENTONCES el sistema conserva múltiples registros dentro del mismo ciclo sin sobrescribir intentos previos.

**CA4 — Histórico de gestión**
DADO QUE un cliente tiene intentos registrados
CUANDO el usuario consulta su seguimiento
ENTONCES visualiza el histórico completo de intentos realizados en el ciclo.

**CA5 — Continuidad operativa**
DADO QUE un cliente ya tuvo intentos previos de gestión
CUANDO un usuario retoma su atención
ENTONCES puede continuar el seguimiento con base en el histórico registrado.

**CA6 — Trazabilidad mínima**
DADO QUE existe un intento registrado
CUANDO el usuario consulta la gestión del cliente
ENTONCES puede identificar resultado del intento, fecha de registro y secuencia dentro del ciclo.

---

### Exclusiones

Esta historia no: recalcula clasificación, modifica prioridad, registra canal, registra comentarios libres, registra responsable, reemplaza CRM ni ejecuta automatización de seguimiento.

---

# F3.HU3.4 — Monitorear desempeño operativo de retención

**Identificación**
- Feature: F3 — Consumo Operativo del Resultado
- Historia: HU3.4 | Versión: 2.0
- Rol principal: Analista de Retención / Coordinador de Operaciones
- Roles consumidores: Retención, Operación Comercial, Supervisión

---

### Necesidad de negocio

Como Analista de retención, necesito monitorear el avance operativo del ciclo vigente de retención, para conocer el estado actual de atención de la cartera, identificar pendientes de gestión y dar seguimiento al desempeño operativo de la operación en curso.

---

### Resultado esperado

Una vista de monitoreo operativo del ciclo vigente que permita:
- Conocer el avance actual de gestión de la cartera vigente
- Identificar volumen pendiente y gestionado
- Visualizar resultados de gestión del ciclo
- Monitorear avance segmentado por clasificación
- Dar seguimiento al desempeño operativo de la ejecución vigente

---

### Reglas de negocio

**1.** El monitoreo se realiza sobre la cartera vigente del ciclo publicado. La vista muestra exclusivamente el estado operativo actual del ciclo vigente. El monitoreo es operativo y de ejecución en curso.

**2. Alcance temporal:** la vista muestra únicamente el avance del ciclo vigente. No incluye: comparativos contra ciclos previos, tendencias históricas, benchmarking entre periodos ni análisis intermensual.

**3. Avance general de gestión:** la vista expone al menos:
- Total de clientes en cartera vigente
- Clientes pendientes de gestión
- Clientes gestionados
- Clientes contactados
- Clientes no contactados
- Clientes reagendados

**4. Avance segmentado por clasificación:** por cada clasificación se muestra:
- Total de clientes del grupo
- Clientes pendientes
- Clientes gestionados
- Clientes contactados
- Clientes no contactados
- Clientes reagendados

**5. Regla de segmentación operativa:** el monitoreo segmentado respeta la clasificación vigente del cliente sin recalcular ni reagrupar clientes.

**6.** La vista debe permitir responder a operación y supervisión: cuánto falta por atender, cuánto ya fue trabajado, qué grupos avanzan y qué grupos están rezagados.

---

### Criterios de aceptación

**CA1 — Monitoreo del ciclo vigente**
DADO QUE existe una cartera vigente publicada
CUANDO el usuario consulta el monitoreo operativo
ENTONCES visualiza únicamente el estado de ejecución del ciclo vigente.

**CA2 — Avance general visible**
DADO QUE el usuario consulta el monitoreo del ciclo
CUANDO revisa el avance general
ENTONCES visualiza total de cartera, pendientes, gestionados, contactados, no contactados y reagendados.

**CA3 — Avance segmentado por clasificación**
DADO QUE el usuario consulta el monitoreo operativo
CUANDO revisa el desempeño por clasificación
ENTONCES visualiza avance segmentado por clasificación con pendientes y resultados de gestión por grupo.

**CA4 — Sin comparativo histórico**
DADO QUE el usuario consulta el monitoreo del ciclo
CUANDO visualiza la vista operativa
ENTONCES no observa comparativos contra ciclos previos ni tendencias históricas.

**CA5 — Seguimiento operativo**
DADO QUE el usuario consulta el monitoreo del ciclo
CUANDO revisa el avance operativo
ENTONCES puede identificar cuánto falta por atender, cuánto ya fue trabajado y qué grupos presentan rezago operativo.

---

### Exclusiones

Esta historia no: recalcula clasificación, compara ciclos, muestra tendencias históricas, ejecuta gestión, modifica prioridades ni reemplaza analítica histórica.

---

# F3.HU3.5 — Exportar cartera priorizada de clientes

**Identificación**
- Feature: F3 — Consumo Operativo del Resultado
- Historia: HU3.5 | Versión: 3.0
- Rol principal: Usuario de negocio (Retención / Operación Comercial)
- Roles consumidores: Retención, Operación Comercial, Supervisión

---

### Necesidad de negocio

Como usuario de retención, necesito exportar la cartera priorizada de clientes que estoy consultando, para trabajarla fuera de la herramienta, compartirla por medios externos y dar continuidad operativa sobre la misma vista priorizada que estoy analizando, sin perder consistencia con el resultado vigente.

---

### Resultado esperado

Una capacidad de exportación de cartera que permita:
- Exportar la cartera priorizada visible al usuario
- Conservar filtros, orden y contexto de la vista actual
- Descargar la lista en formato utilizable por negocio
- Trabajar la cartera fuera de la herramienta sin perder consistencia
- Compartir manualmente la lista por medios externos

---

### Formatos de exportación soportados

| Formato | Uso recomendado | Notas |
|---|---|---|
| XLSX (Excel) | Default. Análisis manual, compartir con áreas | Soporta múltiples hojas, formato y filtros propios de Excel |
| CSV (UTF-8 con BOM) | Integraciones técnicas, archivos grandes | Compatible con cualquier herramienta, sin formato. El BOM garantiza compatibilidad con Excel en Windows |

---

### Alcance de la exportación

La exportación respeta el estado actual del tablero al momento de presionar "Exportar":
1. **Filtros aplicados:** solo se exportan los clientes que cumplen los filtros activos
2. **Ordenamiento aplicado:** los registros se exportan en el mismo orden visible en el tablero
3. **Columnas:** el usuario elige entre dos modos:
   - *"Columnas visibles"* (default): solo las columnas que tiene activadas en ese momento
   - *"Todas las columnas disponibles"*: incluye también columnas secundarias del modelo, útil para análisis profundo

---

### Estructura del archivo XLSX

**Hoja 1 — Datos**
Tabla con los clientes filtrados, una fila por `advertiser_id`, columnas según el modo seleccionado.

**Hoja 2 — Metadata del export**

| Campo | Valor |
|---|---|
| Fecha y hora de generación | Timestamp |
| Usuario que exportó | Nombre + rol |
| Filtros aplicados | Listado legible (ej: "Nivel de riesgo = Alto, División = Centro") |
| Columnas incluidas | Listado de columnas exportadas |
| Total de registros | Número |
| Ciclo de segmentación | Fecha del último cálculo |
| Versión de parámetros | Referencia a HU1.7 |
| Indicador de frescura | Última actualización de cada fuente |
| Aviso de privacidad | Texto recordando el manejo confidencial conforme a LFPDPPP |

---

### Estructura mínima del archivo exportado

El archivo incluye como mínimo las siguientes columnas:
- Cliente (advertiser_id y nombre)
- Clasificación asignada
- Prioridad operativa
- Valor comercial
- Motivo principal de clasificación
- Vigencia / fecha de actualización del resultado

---

### Nomenclatura del archivo

Patrón automático: `retencion_lista_[YYYYMMDD]_[HHMM]_[usuario]_[total_registros].xlsx`

Ejemplo: `retencion_lista_20260504_0930_jvalencia_2847.xlsx`

---

### Límites operativos

| Concepto | Límite |
|---|---|
| Cantidad máxima de registros por export | 100,000 |
| Tamaño máximo del archivo generado | 50 MB |
| Tiempo máximo de generación | 60 segundos |

Si el usuario intenta exportar más de 100,000 registros, el sistema bloquea la exportación y le pide refinar filtros antes de continuar, indicando el total actual. Si el archivo supera 50 MB, se sugiere usar CSV o aplicar filtros adicionales.

---

### Trazabilidad de exportaciones — Bitácora de auditoría

Cada exportación genera un registro de auditoría con:
- ID del export (UUID único)
- Fecha y hora (timestamp)
- Usuario (nombre + rol + correo)
- Filtros aplicados al momento del export
- Cantidad de registros exportados
- Formato (XLSX o CSV)
- Modo de columnas (visibles / todas)

**Consulta de la bitácora por rol:**

| Rol | Alcance de consulta |
|---|---|
| AR / OP / CAC | Solo sus propios exports |
| PO / GE / IT | Todos los exports de todos los usuarios |

---

### Consideraciones de privacidad

1. **Aviso visible al exportar:** antes de generar el archivo, el sistema muestra un mensaje recordando que el archivo contiene datos personales y debe manejarse conforme a las políticas de la organización y a la LFPDPPP
2. **Aviso embebido en el archivo:** la hoja de metadata del XLSX incluye el aviso de privacidad como recordatorio permanente
3. **Exportar sin datos de contacto:** el usuario puede marcar una opción para omitir teléfono, celular y email del archivo (útil para reportes ejecutivos)

> Ningún archivo exportable debe combinar datos de contacto del cliente (teléfono y correo) con PII adicional. La única combinación válida es: identificadores de cliente (advertiser_id) con datos de contacto, sin información personal extra.

---

### Permisos de exportación por rol

| Rol | Puede exportar | Datos de contacto | Alcance |
|---|---|---|---|
| Analista de Retención (AR) | Sí | Sí | Todos los clientes |
| Coordinador de Operaciones (OP) | Sí | Sí | Todos los clientes |
| Gerente de Estrategia (GE) | Sí | Opcional (default sin) | Todos los clientes |
| Ejecutivo / CAC | No | — | No aplica en este alcance |
| Product Owner (PO) | Sí | No (solo para gobernanza) | Todos los clientes |
| Sistemas (IT) | Sí | Sí (para diagnóstico) | Todos los clientes |
| Otros usuarios | No | — | — |

---

### Criterios de aceptación

**CA1 — Exportación de vista activa**
DADO QUE el usuario consulta una cartera priorizada
CUANDO exporta la información
ENTONCES descarga exactamente la cartera visible en su vista actual.

**CA2 — Respeto de filtros**
DADO QUE el usuario tiene filtros aplicados en la cartera
CUANDO exporta la información
ENTONCES el archivo respeta exactamente los filtros activos de la consulta.

**CA3 — Respeto de orden**
DADO QUE el usuario tiene un orden activo en la vista
CUANDO exporta la cartera
ENTONCES el archivo conserva el mismo orden visible en la consulta.

**CA4 — Selección de formato**
DADO QUE el usuario presiona "Exportar"
CUANDO se abre el diálogo de exportación
ENTONCES puede elegir entre formato XLSX (default) o CSV.

**CA5 — Selección de modo de columnas**
DADO QUE el usuario está en el diálogo de exportación
CUANDO elige el modo de columnas
ENTONCES puede seleccionar entre "Columnas visibles" (default) o "Todas las columnas disponibles".

**CA6 — Estructura mínima exportable**
DADO QUE el usuario exporta la cartera
CUANDO revisa el archivo descargado
ENTONCES visualiza al menos cliente, clasificación, prioridad, valor comercial, motivo principal y vigencia.

**CA7 — Hoja de metadata en XLSX**
DADO QUE el usuario exportó en formato XLSX
CUANDO abre el archivo descargado
ENTONCES encuentra dos hojas: la primera con los datos del listado y la segunda con la metadata del export incluyendo el aviso de privacidad.

**CA8 — Nomenclatura automática del archivo**
DADO QUE el usuario descarga un archivo
CUANDO se genera el nombre
ENTONCES sigue el patrón `retencion_lista_[YYYYMMDD]_[HHMM]_[usuario]_[total_registros]` con la extensión correspondiente.

**CA9 — Límite de registros**
DADO QUE los filtros aplicados producen más de 100,000 registros
CUANDO el usuario presiona "Exportar"
ENTONCES el sistema bloquea la exportación, muestra el total actual y pide refinar los filtros antes de continuar.

**CA10 — Aviso de privacidad**
DADO QUE el usuario va a exportar un archivo
CUANDO confirma la exportación
ENTONCES se muestra un aviso recordando que el archivo contiene datos personales y debe manejarse conforme a las políticas de la organización y a la LFPDPPP.

**CA11 — Registro de auditoría del export**
DADO QUE un usuario completa una exportación
CUANDO el archivo se genera correctamente
ENTONCES el sistema registra en la bitácora de auditoría: ID del export, fecha/hora, usuario, rol, filtros aplicados, cantidad de registros, formato y modo de columnas.

**CA12 — Consulta de auditoría por roles de gobernanza**
DADO QUE un usuario PO, GE o IT consulta el historial de exportaciones
CUANDO accede a la bitácora
ENTONCES ve todos los exports realizados por todos los usuarios con sus detalles registrados.

**CA13 — Generación dentro del tiempo límite**
DADO QUE la exportación contiene hasta 100,000 registros
CUANDO el usuario presiona "Exportar"
ENTONCES el archivo se genera y descarga en menos de 60 segundos.

**CA14 — Encoding correcto del CSV**
DADO QUE el usuario exporta en formato CSV
CUANDO abre el archivo en Excel en Windows
ENTONCES los caracteres especiales (acentos, ñ) se muestran correctamente porque el archivo está en UTF-8 con BOM.

---

### Supuestos y limitaciones aceptadas

1. Solo XLSX y CSV en MVP: otros formatos (PDF, Google Sheets) se evalúan en iteraciones posteriores
2. Sin envío automático por correo: el archivo se descarga al navegador. No se implementa envío automático a destinatarios
3. Sin programación de exports recurrentes: el usuario ejecuta el export manualmente cada vez
4. Sin contraseña ni watermark en el archivo: la trazabilidad se basa en la metadata embebida y la bitácora de auditoría
5. Almacenamiento temporal: los archivos generados se eliminan inmediatamente tras la descarga. No se mantiene repositorio de exports históricos descargables

---

### Brechas pendientes

1. Restricción de exportación para CAC: en este alcance, el CAC no tiene acceso a la exportación
2. No existe restricción de horario para exportaciones
3. No se requiere notificación de exports masivos en este alcance

---

# F4 — MEDICIÓN Y DESEMPEÑO DEL MODELO

---

# F4.HU4.1 — Monitorear desempeño del modelo de retención

**Identificación**
- Feature: F4 — Medición y Desempeño del Modelo
- Historia: HU4.1 | Versión: 2.0
- Rol principal: Usuario de negocio (Retención / Supervisión / Estrategia Comercial)
- Roles consumidores: Retención, Supervisión, Estrategia Comercial

---

### Necesidad de negocio

Como usuario de negocio, necesito monitorear el desempeño del modelo de retención, para entender cómo está distribuyendo la cartera, identificar qué clasificaciones concentra el modelo y detectar cambios relevantes en su comportamiento entre ciclos.

---

### Resultado esperado

Una vista de desempeño del modelo que permita:
- Conocer la distribución de clientes por clasificación
- Identificar volumen generado por cada segmento del modelo
- Visualizar cómo se distribuye la cartera clasificada
- Comparar la distribución del ciclo vigente contra el ciclo anterior
- Detectar cambios básicos en el comportamiento del modelo entre ciclos

---

### Reglas de negocio

**1.** El monitoreo se realiza a nivel ciclo y clasificación. La unidad de lectura funcional es la distribución del resultado clasificado.

**2. Alcance del monitoreo:** la vista mide únicamente el comportamiento de clasificación del modelo. No incluye métricas de gestión operativa ni ejecución.

**3. Distribución de cartera:** la vista expone por clasificación: volumen de clientes, participación relativa dentro de la cartera y peso del segmento en el ciclo.

**4. Volumen por clasificación:** la vista muestra el volumen de clientes asignados a cada clasificación del modelo: INDETERMINADO, VP, CQ, SP, FL, TA, CS y RB. Cada clasificación debe ser visible como parte del comportamiento del modelo.

**5. Participación relativa:** se muestra el peso relativo de cada clasificación dentro del total de clientes evaluados del ciclo.

**6. Comparativo entre ciclos:** la vista incluye comparativo básico entre el ciclo vigente y el ciclo anterior inmediato.

**7. Variación de comportamiento:** la vista permite identificar: crecimiento de una clasificación, reducción de una clasificación y cambio en participación relativa de un segmento.

**8.** La vista permite a negocio responder: cómo está distribuyendo el modelo la cartera, qué segmentos concentra, qué segmentos crecieron o disminuyeron y qué cambios básicos presenta el modelo entre ciclos.

---

### Criterios de aceptación

**CA1 — Distribución del ciclo vigente**
DADO QUE existe un resultado vigente publicado
CUANDO el usuario consulta el desempeño del modelo
ENTONCES visualiza la distribución de clientes por clasificación del ciclo vigente.

**CA2 — Volumen por clasificación**
DADO QUE el usuario consulta el desempeño del modelo
CUANDO revisa la distribución del ciclo
ENTONCES visualiza el volumen de clientes correspondiente a cada clasificación del modelo.

**CA3 — Participación relativa**
DADO QUE el usuario consulta el desempeño del modelo
CUANDO revisa la composición del ciclo
ENTONCES visualiza la participación relativa de cada clasificación dentro del total evaluado.

**CA4 — Comparativo entre ciclos**
DADO QUE existe información del ciclo anterior
CUANDO el usuario consulta el desempeño del modelo
ENTONCES visualiza un comparativo básico entre la distribución del ciclo vigente y la del ciclo anterior.

**CA5 — Variación de comportamiento**
DADO QUE el usuario compara ambos ciclos
CUANDO revisa la distribución por clasificación
ENTONCES puede identificar variaciones básicas de crecimiento, reducción o cambio relativo entre segmentos.

**CA6 — Sin métricas operativas**
DADO QUE el usuario consulta el desempeño del modelo
CUANDO visualiza la vista de monitoreo
ENTONCES no observa métricas de gestión operativa ni ejecución de atención.

---

### Exclusiones

Esta historia no: mide gestión operativa, mide efectividad de atención, explica causas del comportamiento, recalcula clasificación ni reemplaza analítica de desempeño avanzada.

---

# F4.HU4.2 — Medir efectividad de clasificación y gestión de retención

**Identificación**
- Feature: F4 — Medición y Desempeño del Modelo
- Historia: HU4.2 | Versión: 2.0
- Rol principal: Usuario de negocio (Retención / Supervisión / Estrategia Comercial)
- Roles consumidores: Retención, Supervisión, Estrategia Comercial

---

### Necesidad de negocio

Como usuario de negocio, necesito medir la efectividad operativa de la clasificación del modelo de retención, para entender qué tan gestionables son los segmentos priorizados y qué tan bien la operación está ejecutando sobre la cartera que el modelo recomienda atender.

---

### Resultado esperado

Una vista de efectividad operativa por clasificación que permita:
- Medir qué volumen clasificado fue gestionado
- Identificar qué volumen sigue sin gestión
- Conocer conversión operativa por clasificación
- Visualizar resultados de contacto por segmento
- Entender qué tan operable está siendo la priorización del modelo

---

### Reglas de negocio

**1.** La medición se realiza a nivel ciclo y clasificación. La unidad funcional es la conversión operativa de gestión por clasificación.

**2. Alcance de efectividad:** se mide únicamente como conversión operativa: volumen gestionado, no gestionado, contactado, no contactado y reagendado. No incluye resultados comerciales ni outcomes posteriores.

**3. Volumen gestionado por clasificación:** se muestra el volumen de clientes que ya recibieron al menos un intento de gestión en el ciclo, permitiendo medir qué proporción de cada segmento fue efectivamente trabajada.

**4. Volumen no gestionado por clasificación:** se muestra el volumen de clientes que aún no registran gestión en el ciclo, permitiendo identificar segmentos sin atención operativa.

**5. Conversión operativa por clasificación:** la vista muestra la proporción gestionado vs. pendiente de gestión por segmento.

**6. Resultado de gestión por clasificación:** por clasificación se muestra la distribución de resultados: contactados, no contactados y reagendados.

**7. Comparativo entre clasificaciones:** el usuario puede identificar qué segmentos convierten más gestión, cuáles concentran más pendientes y cuáles convierten mejor en contacto. La comparación se enfoca en operabilidad del modelo.

**8.** La vista permite a negocio responder: qué tan gestionable es cada clasificación, qué segmentos convierten mejor, qué segmentos presentan más rezago operativo y qué tan accionable está siendo la priorización del modelo.

---

### Criterios de aceptación

**CA1 — Volumen gestionado por clasificación**
DADO QUE existe cartera clasificada y gestión registrada
CUANDO el usuario consulta efectividad operativa
ENTONCES visualiza por clasificación el volumen de clientes gestionados en el ciclo.

**CA2 — Volumen no gestionado por clasificación**
DADO QUE existe cartera clasificada vigente
CUANDO el usuario consulta efectividad operativa
ENTONCES visualiza por clasificación el volumen de clientes que aún no registran gestión.

**CA3 — Conversión operativa**
DADO QUE el usuario consulta efectividad de clasificación
CUANDO revisa la vista de desempeño
ENTONCES visualiza la proporción gestionado vs. pendiente por clasificación.

**CA4 — Resultado de gestión por clasificación**
DADO QUE existen gestiones registradas en el ciclo
CUANDO el usuario consulta efectividad operativa
ENTONCES visualiza por clasificación el volumen de contactados, no contactados y reagendados.

**CA5 — Comparativo entre segmentos**
DADO QUE el usuario consulta efectividad del modelo
CUANDO compara clasificaciones
ENTONCES puede identificar qué segmentos son más gestionables, cuáles concentran más pendientes y cuáles convierten mejor en contacto.

**CA6 — Sin resultado comercial**
DADO QUE el usuario consulta efectividad del modelo
CUANDO visualiza la medición
ENTONCES no observa métricas de retención final, conversión comercial ni resultado de negocio posterior.

---

### Exclusiones

Esta historia no: mide retenido / no retenido, mide conversión comercial, mide efectividad final de retención, recalcula clasificación ni reemplaza analítica de negocio.

---

# F4.HU4.3 — Auditar trazabilidad y consistencia del modelo de retención

**Identificación**
- Feature: F4 — Medición y Desempeño del Modelo
- Historia: HU4.3 | Versión: 2.0
- Rol principal: Usuario de negocio (Retención / Supervisión / Estrategia Comercial)
- Roles consumidores: Retención, Supervisión, Estrategia Comercial

---

### Necesidad de negocio

Como usuario de negocio, necesito auditar la trazabilidad y consistencia del resultado publicado del modelo de retención, para asegurar que toda clasificación visible tenga sustento funcional, evidencia asociada y trazabilidad suficiente para ser explicada y validada por negocio.

---

### Resultado esperado

Una vista de auditoría funcional del resultado publicado que permita:
- Validar que toda clasificación publicada tenga sustento funcional
- Verificar que toda clasificación visible tenga evidencia asociada
- Auditar que el resultado sea explicable y trazable
- Identificar resultados inconsistentes o sin soporte funcional
- Asegurar integridad funcional del resultado publicado

---

### Reglas de negocio

**1.** La auditoría se realiza sobre el resultado publicado del ciclo. La unidad funcional de auditoría es el resultado clasificado publicado. No incluye auditoría del proceso upstream ni del mecanismo de publicación.

**2. Consistencia funcional:** toda clasificación visible en el resultado publicado debe ser funcionalmente consistente: tiene clasificación válida, tiene sustento funcional identificable, puede ser explicada y puede ser auditada por negocio. No deben existir resultados visibles sin sustento funcional.

**3. Evidencia asociada:** toda clasificación publicada debe tener evidencia funcional asociada que permita explicar por qué el cliente fue clasificado en esa categoría. Una clasificación sin evidencia asociada se considera inconsistente.

**4. Trazabilidad funcional mínima:** toda clasificación publicada debe conservar al menos: clasificación publicada, motivo principal de clasificación, evidencia funcional asociada y fecha de actualización del resultado.

**5. Resultado inconsistente:** un resultado se considera inconsistente cuando: no tiene clasificación válida, no tiene evidencia asociada, no tiene motivo funcional identificable o no puede explicarse funcionalmente. Los resultados inconsistentes deben quedar identificables para auditoría.

**6.** La vista permite a negocio responder: si toda clasificación publicada tiene sustento, si el resultado puede explicarse, si el resultado es trazable y si existen clasificaciones inconsistentes o sin soporte.

---

### Criterios de aceptación

**CA1 — Validación de clasificación visible**
DADO QUE existe un resultado publicado vigente
CUANDO el usuario consulta la auditoría funcional
ENTONCES puede validar que toda clasificación visible corresponda a un resultado funcionalmente consistente.

**CA2 — Validación de evidencia asociada**
DADO QUE existe una clasificación publicada
CUANDO el usuario audita el resultado
ENTONCES puede verificar que la clasificación tenga evidencia funcional asociada.

**CA3 — Validación de trazabilidad mínima**
DADO QUE existe una clasificación visible en el resultado
CUANDO el usuario consulta su auditoría
ENTONCES puede identificar clasificación, motivo principal, evidencia funcional y fecha de actualización.

**CA4 — Identificación de inconsistencias**
DADO QUE existen resultados sin sustento funcional suficiente
CUANDO el usuario consulta la auditoría
ENTONCES puede identificar las clasificaciones inconsistentes o sin soporte funcional.

**CA5 — Sin auditoría upstream**
DADO QUE el usuario consulta la auditoría funcional
CUANDO revisa la consistencia del modelo
ENTONCES no observa validaciones del proceso upstream ni del mecanismo de publicación.

---

### Exclusiones

Esta historia no: audita señales upstream, valida construcción del modelo, valida publicación, audita versionado, recalcula clasificación ni reemplaza auditoría técnica del pipeline.

---

---

# RESUMEN EJECUTIVO DEL DOCUMENTO v3.0

| Feature | Historia | Título | Versión | Estado |
|---|---|---|---|---|
| F1 | HU1.1 | Construir universo comercial base del ciclo | 3.0 | Sin cambio |
| F1 | HU1.2 | Identificar señales de queja, atención y silencio | 3.0 | Sin cambio |
| F1 | HU1.3 | Incorporar señales de interacción digital | 2.0 | Sin cambio |
| F1 | HU1.4 | Consolidar señales del cliente | 2.0 | Sin cambio |
| F1 | HU1.5 | Evaluar cliente y asignar clasificación de retención | 3.0 | **Enriquecida** |
| F1 | HU1.6 | Publicar resultado vigente del ciclo | 2.0 | Sin cambio |
| F1 | HU1.7 | Administrar parámetros configurables del modelo | 2.0 | **Nueva** |
| F2 | HU2.1 | Ingesta y mapeo de fuentes (ETL) | 2.0 | **Nueva** |
| F2 | HU2.2 | Calidad de datos | 2.0 | **Nueva** |
| F3 | HU3.1 | Consultar cartera priorizada de clientes en riesgo | 3.0 | **Enriquecida** |
| F3 | HU3.2 | Consultar detalle de clasificación y trazabilidad | 2.0 | Sin cambio |
| F3 | HU3.3 | Registrar gestión y seguimiento de retención | 2.0 | Sin cambio |
| F3 | HU3.4 | Monitorear desempeño operativo de retención | 2.0 | Sin cambio |
| F3 | HU3.5 | Exportar cartera priorizada de clientes | 3.0 | **Enriquecida** |
| F4 | HU4.1 | Monitorear desempeño del modelo de retención | 2.0 | Sin cambio |
| F4 | HU4.2 | Medir efectividad de clasificación y gestión | 2.0 | Sin cambio |
| F4 | HU4.3 | Auditar trazabilidad y consistencia del modelo | 2.0 | Sin cambio |

**Total: 17 historias de usuario — 4 features**

---

*Documento v3.0 — Modelo de Retención*
*Generado: Mayo 2026 | Confidencial — Uso interno*
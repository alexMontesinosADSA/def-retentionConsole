# Especificación Funcional y Técnica
## Integración Consola de Retención ↔ Infobip (Cuenta Empresarial People)

**Versión:** 1.0
**Estado:** Especificación consolidada para revisión de equipo de desarrollo.
**Fase:** Sprint 1 / MVP — Integración ligera manual (la automatización de disparo vive en Sprint 2)
**Fuentes consolidadas:** `OVERVIEW_proyecto.txt`, `descripcion_consola_retencion.md`, `arq_mvp_retencion_consolidada_v1`, `reglas_de_segmentación_optimized.md`, `integracion_infobip_v1.md`, documentación oficial de Infobip (People, Blocklist, E.164, rate limits)

---

## 1. Propósito y alcance de este documento

Este documento especifica **cómo se integra la Consola de Retención con la cuenta empresarial de Infobip** para preparar y sincronizar audiencias de retención, dentro del alcance del Sprint 1 / MVP del programa de retención.

Consolida cinco documentos de insumo previos, los concilia entre sí, los valida contra la documentación pública de Infobip (People API), y resuelve los puntos de conflicto detectados durante el análisis. Donde persisten preguntas que solo puede responder el equipo interno (OnBoarding, Sistemas, Infobip Account Manager), se documentan explícitamente como **pendientes** con dueño sugerido, en vez de asumirse.

No es un documento de arquitectura de todo el programa de retención (eso ya existe en `arq_mvp_retencion_consolidada_v1.docx`); es la especificación del componente de integración con Infobip, que vive dentro de esa arquitectura.

---

## 2. Contexto y relación entre componentes

El programa de retención tiene tres capas con responsabilidades no intercambiables:

```
Fuentes origen (IAM, SAP_USER, Panel Marketing, Pinbox, catálogos)
        ↓
Pipeline / Motor de Retención  (Oracle 11g, report_work@unorep, PL/SQL)
        →  decide: consolida señales, calcula score, asigna etiqueta,
           nivel de riesgo y acción sugerida, publica resultado oficial del ciclo
        ↓
Consola de Retención  (API .NET + Micro Frontend + BD transaccional de aplicación)
        →  opera: consulta, filtra, prioriza, registra gestión manual,
           prepara y sincroniza audiencias
        ↓
Infobip (People)
        →  activa: mantiene perfiles de contacto, atributos, tags;
           Mercadotecnia diseña y ejecuta campañas por Email y WhatsApp
           dentro de las herramientas nativas de Infobip
```

Regla arquitectónica que gobierna todo el diseño (heredada de `arq_mvp_retencion_consolidada_v1.docx`, sección 2.5–2.6):

> **UNOREP decide y publica. La BD transaccional de aplicación registra la operación humana.** Ningún componente downstream reinterpreta lógica upstream; el micro frontend no consulta fuentes origen ni tablas internas del motor.

Aplicado a esta integración: la Consola **no recalcula** score, etiqueta ni nivel de riesgo — los consume tal cual del resultado oficial vigente publicado en Serving (UNOREP). La preparación de audiencias **no toma el contacto final desde el snapshot publicado del ciclo**; resuelve celular y email vigentes desde un read model en `APP_USER@UNOAPP`. Las entidades de audiencia y sincronización (sección 7) viven en la **BD transaccional de aplicación** (Oracle, ambientes DEV/QA/PROD), no en UNOREP.

### 2.2 Decisión de fuente de contacto operativo

Se adopta como decisión de diseño la creación de un **read model de contacto resuelto en `APP_USER@UNOAPP`** para todos los casos de uso de preparación de audiencias y activación con Infobip.

Reglas de resolución:

- **Nivel 1:** contacto vigente desde Pinbox (`mob_user@UNOAPP`), por ser la fuente operativa más confiable y actualizada.
- **Nivel 2:** contacto desde IAM, usado como respaldo cuando Pinbox no tenga dato válido.
- El resultado oficial del ciclo (label, risk, action, universo) sigue viniendo exclusivamente de UNOREP.
- La API .NET compone ambos planos: **decisión desde UNOREP + contacto resuelto desde UNOAPP**.
- Una vez confirmada la audiencia, el contacto resuelto se **congela** en `RETENTION_AUDIENCE_CONTACT` para trazabilidad, idempotencia y reintentos.

### 2.1 Decisión de alcance confirmada para esta especificación

| Decisión | Resolución |
|---|---|
| ¿En qué fase vive la integración ligera (manual, disparada por el usuario)? | **Sprint 1 / MVP.** La automatización total del disparo (job programado sin intervención humana) queda para Sprint 2, conforme a `arq_mvp_retencion_consolidada_v1.docx` §16.1. |
| ¿Qué canales? | **Email y WhatsApp**, simultáneos por etiqueta. No se contempla SMS en esta fase — no aparece en la tabla de reglas de envío del negocio. |
| ¿El usuario elige un canal por audiencia? | **No.** Cada etiqueta ya tiene definidas sus plantillas para ambos canales (ver §6.3). La integración no es mono-canal por audiencia; una audiencia sincronizada queda lista para activarse en ambos canales dentro de Infobip. |
| Límite de tamaño de lote en People API | **1000 personas por solicitud**, confirmado con el equipo/cuenta de Infobip. Se documenta como dato firme (§13). |

---

## 3. Objetivo funcional de la integración

Permitir que la Consola de Retención convierta el resultado oficial del ciclo de retención en **audiencias preparadas y sincronizadas en Infobip People**, sin que la consola:

- Diseñe templates.
- Envíe mensajes directamente (no usa Channels API en esta fase).
- Administre campañas o journeys.
- Reemplace ninguna funcionalidad nativa de Infobip.

Y sin que Infobip:

- Decida clasificación de riesgo (eso es exclusivo del motor).
- Reciba más PII o datos sensibles de los estrictamente necesarios para segmentar y contactar.

---

## 4. Problema de identidad: advertiser_id vs. celular

Este es el punto de diseño más crítico de toda la integración.

- El motor de retención trabaja y clasifica **1 `advertiser_id` × 1 `cycle_id`**.
- Infobip identifica perfiles por **`external_id` = celular del cliente**, convención ya en uso desde el proceso de OnBoarding (~40% de la cartera podría ya tener perfil creado).
- Existe duplicidad interna conocida y no resuelta por otro proyecto: un mismo cliente real puede tener varios `advertiser_id`.
- Por lo tanto, **varios `advertiser_id` pueden compartir un mismo celular**, y para Infobip eso es un solo perfil.

**Regla de diseño (no negociable para esta fase):** no se crean perfiles en Infobip por `advertiser_id`. Se respeta `external_id = celular normalizado`. El `advertiser_id` viaja como dato de trazabilidad (atributo), nunca como identidad.

### 4.1 Flujo de resolución de identidad

```
Resultado de retención por advertiser_id desde UNOREP (N registros)
  + contacto operativo vigente resuelto en APP_USER@UNOAPP
   → Validación de elegibilidad y contactabilidad
   → Normalización de celular / email
   → Agrupación por celular normalizado
   → Selección de etiqueta y nivel de riesgo operativos (si hay múltiples advertiser_id)
   → 1 contacto de audiencia = 1 perfil People objetivo
   → Partial upsert en Infobip People (external_id = celular)
   → Asignación de tag de audiencia
```

### 4.2 Regla de selección cuando un celular agrupa varios `advertiser_id`

Cuando el mismo celular normalizado corresponde a varios `advertiser_id` con etiquetas distintas, se necesita **una sola** etiqueta operativa para representar al contacto frente a Infobip. Esta prioridad **no sustituye** la jerarquía oficial del motor (§7 de `OVERVIEW_proyecto.txt`); solo resuelve el caso de agrupación por contacto para fines de activación:

| Prioridad | Etiqueta | ¿Elegible para campaña automática? |
|---:|---|---|
| 1 | SP | Sí |
| 2 | FL | Sí |
| 3 | TA | Sí |
| 4 | CS | Sí |
| 5 | CQ | Solo si negocio autoriza campaña especial (requiere gestión humana por CAC) |
| 6 | VP | Normalmente excluido (requiere gestión manual con ventas) |
| 7 | RB | Normalmente excluido (sin acción en esta fase) |
| 8 | INDETERMINADO | Excluido (requiere revisión, no activación automática) |

Validado contra `reglas_de_segmentación_optimized.md`: esta prioridad **coincide** con el orden de riesgo de negocio (VP=Revisión, CQ=Alto, SP=Alto, FL=Alto, TA=Alto, CS=Medio, RB=Bajo), salvo por la exclusión explícita de VP y CQ del envío automatizado, que es una decisión de canal de atención (ventas/CAC), no de riesgo.

El nivel de riesgo (`selected_risk_level`) **no se recalcula en la capa de integración**: se toma directamente del nivel de riesgo ya publicado por el motor para el `advertiser_id` seleccionado. Esto es relevante porque, según `reglas_de_segmentación_optimized.md`, el riesgo de un mismo etiqueta puede variar según score — por ejemplo, CS con más de 21 visitas es riesgo Medio y CS con menos de 21 visitas es riesgo Bajo. Esa lógica ya es responsabilidad del motor (capacidad 5.5, "Asignar nivel de riesgo"); la integración solo hereda el valor.

Campos a conservar por contacto agrupado:

- `external_id` (celular normalizado)
- `primary_advertiser_id`
- `advertiser_ids` (lista completa)
- `advertiser_count`
- `multi_advertiser_flag`
- `source_labels` (todas las etiquetas encontradas)
- `selected_label`, `selected_risk_level`, `selected_action`
- `selection_reason`

---

## 5. Reglas de negocio aplicadas a la integración

### 5.1 Etiquetas y su tratamiento operativo

| Etiqueta | Significado | Riesgo | Tratamiento |
|---|---|---|---|
| VP | Cliente de alto valor (contrato >120K o score de producto entre 15 y 100) | Revisión | Manual — ventas/supervisor. Excluido de campaña automática. |
| CQ | Queja explícita (llamada, NPS, ventas o finanzas notificó al CAC) | Alto | Manual — CAC. Solo campaña especial autorizada. |
| SP | Sin pago / mora de una mensualidad | Alto | Campaña automatizable. |
| FL | Falta de leads (score de producto + umbral de visitas: >21 con ≥60 visitas, o <21 con ≥20 visitas, con ≥30 días publicado) | Alto | Campaña automatizable. |
| TA | Casos abiertos (tickets) | Alto | Campaña automatizable. |
| CS | Cliente silencioso (al corriente, sin cases, contratación 2025 o anterior). Riesgo Medio si >21 visitas, Bajo si <21. Un cliente que califica para CS y FL a la vez **no** se clasifica como CS. | Medio / Bajo | Campaña automatizable. |
| RB | Resto de la base — no activa señales prioritarias | Bajo | Sin acción en esta fase. Excluido. |
| INDETERMINADO | No evaluable por calidad de datos | — | Excluido — requiere revisión. |

### 5.2 Score de producto (contexto, no parte de esta integración)

El catálogo `report_work.rw_product_score` (scores 0/1/100 por `PD_PRODUCT_CODE`) alimenta el cálculo de VP y FL dentro del **motor PL/SQL**, no dentro de la integración con Infobip. Se documenta aquí solo como referencia de trazabilidad — la Consola/API no debe reinterpretar ni recalcular estos scores; los consume ya resueltos desde Serving.

### 5.3 Canales y plantillas por etiqueta

Confirmado: **Email y WhatsApp simultáneos**, sin SMS.

| Etiqueta | Riesgo | Plantilla Email | Plantilla WhatsApp |
|---|---|---|---|
| VP | Revisión | — (manual) | — (manual) |
| CQ | Alto | — (manual) | — (manual) |
| SP | Alto | Cliente moroso — protección | Cliente moroso — oportunidad |
| FL | Alto | Falta/caída de leads — recuperación (Prueba A/B) | Falta de leads |
| CS (>21 visitas) | Medio | Cliente silencioso — performance (Prueba A/B) | Falta de leads (reutilizada) |
| CS (<21 visitas) | Bajo | Cliente silencioso — tiempo | — |
| TA | Alto | Cases abiertos | Casos abiertos |
| RB | Bajo | — | — |

**Implicación de diseño:** dado que ambos canales se activan por etiqueta (no por elección del usuario), el **tag de Infobip no debe llevar sufijo de canal**. Esto corrige al borrador original (`integracion_infobip_v1.md` §20, que proponía `RET_2026_05_FL_ALTO_WA`). El formato de tag recomendado es:

```
RET_{cycle_id}_{label}_{risk_level}
```

Ejemplos: `RET_2026_05_SP_ALTO`, `RET_2026_05_CS_MEDIO`.

Marketing usa el mismo tag para construir, dentro de Infobip, las dos campañas (Email y WhatsApp) correspondientes a esa etiqueta/ciclo, cada una con su plantilla ya definida en la tabla anterior.

**Corolario sobre elegibilidad de contacto:** como una etiqueta puede requerir Email y WhatsApp a la vez, la validación de contactabilidad debe evaluarse **por canal**, no como una sola bandera:

- `contactable_whatsapp_flag` (requiere celular válido)
- `contactable_email_flag` (requiere email válido)

Un contacto con celular válido pero sin email no debe excluirse por completo: sigue siendo válido para la campaña de WhatsApp, aunque quede fuera de la de Email (y viceversa). El motivo de exclusión debe registrarse por canal cuando aplique parcialmente.

---

## 6. Capacidades de Infobip a utilizar (validadas)

| Capacidad | Uso en la integración | Estado de validación |
|---|---|---|
| **Batch partial people upsert** (Partial Update / Batch people update) | Crear o actualizar perfiles por lote sin borrar campos ajenos a retención | Confirmado en documentación oficial: existe Update Person (reemplaza) vs Partial Update (solo el campo indicado); la integración usa la segunda. |
| **Custom attributes tipo Lista** para `retention_advertiser_ids` | Guardar los `advertiser_id` asociados a un contacto | Confirmado: hasta 128 elementos por perfil. **Corrección importante:** por defecto los valores se *agregan* a la lista; la integración debe forzar `overwrite` en cada sincronización para reflejar solo el ciclo vigente, o el atributo acumulará histórico de ciclos pasados. |
| **Tags** (crear / consultar / asignar en batch) | Agrupar operativamente la audiencia por ciclo/etiqueta/riesgo para que Marketing la use en Infobip | Confirmado como mecanismo estándar de segmentación en People. |
| **Do Not Contact / Blocklist** | Excluir clientes con opt-out antes de sincronizar | Confirmado: lista y Blocklist API existen; el opt-out puede originarse automáticamente (STOP en SMS/MMS, enlace URL_OPTOUT, evento de Flow) o manualmente. |
| **Match profiles** | Diagnóstico/reconciliación inicial (no en la ruta normal de sincronización) | Recomendado por el borrador para la Fase 0 de diagnóstico (§13). |

### 6.1 Capacidades explícitamente fuera de alcance en esta fase

- Channels API (envío directo WhatsApp/SMS/Email).
- Moments (journeys/automatización avanzada).
- Conversations / Answers / Knowledge Base.
- Full people upsert / creación directa de perfil (riesgo de duplicar o de generar perfiles vacíos si no se maneja bien el matching).

### 6.2 Restricciones técnicas a respetar

- Nombres de atributos personalizados: solo letras, números y guion bajo; no pueden iniciar con número, no admiten espacios ni guiones.
- Formato de celular: Infobip recomienda fuertemente E.164 (máximo 15 dígitos, el signo `+` es opcional). **Pendiente confirmar** cuál es el formato exacto que usa hoy OnBoarding como `external_id` (ver §11).
- Rate limiting basado en tokens (token bucket); un 429 implica backoff exponencial con incremento progresivo de espera.
- Errores 5xx pueden ser temporales — se recomienda reintentar, pero con límite de reintentos definido.

---

## 7. Modelo de datos (BD transaccional de aplicación)

Conforme a la regla "UNOREP decide y publica; la BD transaccional registra la operación humana", estas entidades **no** viven en UNOREP — viven en la Oracle transaccional de la aplicación (DEV/QA/PROD).

### 7.1 `RETENTION_AUDIENCE`

| Campo | Descripción |
|---|---|
| `audience_id` | PK local |
| `audience_name`, `audience_description` | Identificación funcional |
| `cycle_id` | Ciclo del resultado oficial usado como fuente |
| `source_result_version` | Versión/corrida del resultado (soporta re-cálculo sin sobrescritura, ver arquitectura §Flujo E2E 8) |
| `created_by`, `created_at` | Auditoría de creación |
| `selected_labels`, `selected_risk_levels`, `filters_json` | Criterios de selección aplicados |
| `total_source_advertisers`, `total_unique_contacts`, `total_valid_contacts`, `total_excluded_contacts`, `total_synced_contacts`, `total_failed_contacts` | Métricas de la audiencia |
| `infobip_tag` | Tag generado (formato §5.3) |
| `sync_status` | Ver estados abajo |
| `sync_started_at`, `sync_finished_at` | Auditoría de ejecución |
| `expiration_date` | Vigencia opcional del tag/audiencia |
| `notes` | Observaciones |

Estados de `sync_status`: `DRAFT` → `READY_TO_SYNC` → `SYNC_IN_PROGRESS` → `SYNCED` / `PARTIALLY_SYNCED` / `FAILED` / `CANCELLED` / `EXPIRED`.

### 7.2 `RETENTION_AUDIENCE_CONTACT`

| Campo | Descripción |
|---|---|
| `audience_contact_id`, `audience_id`, `cycle_id` | Identificación |
| `normalized_mobile`, `normalized_email` | Contacto normalizado |
| `contact_source_level`, `contact_source_system`, `contact_resolved_at` | Trazabilidad del read model de contacto resuelto |
| `infobip_external_id` | Igual a `normalized_mobile` en el diseño actual |
| `primary_advertiser_id`, `advertiser_ids`, `advertiser_count`, `multi_advertiser_flag` | Trazabilidad de agrupación (§4.2) |
| `source_labels`, `selected_label`, `selected_risk_level`, `selected_action`, `selection_reason` | Resolución operativa |
| `contactable_whatsapp_flag`, `contactable_email_flag` | Elegibilidad por canal (§5.3) |
| `exclusion_flag`, `exclusion_reason` | Motivo si aplica (catálogo §8.2) |
| `infobip_sync_status`, `infobip_profile_id`, `infobip_response_code`, `infobip_response_message` | Resultado de sincronización |
| `last_sync_attempt_at`, `retry_count` | Control de reintentos |

Estados por contacto: `PENDING`, `SKIPPED`, `SYNCED`, `FAILED`, `RETRY_PENDING`, `AMBIGUOUS`, `NOT_CONTACTABLE`.

Restricción de unicidad: `audience_id` + `normalized_mobile` debe ser única dentro de la audiencia.

### 7.3 `RETENTION_AUDIENCE_BATCH`

Dado el límite confirmado de 1000 personas por solicitud (§2.1), toda audiencia mayor a 1000 contactos se particiona.

| Campo | Descripción |
|---|---|
| `batch_id`, `audience_id`, `batch_number`, `batch_size` | Identificación y tamaño (máx. 1000) |
| `started_at`, `finished_at`, `status` | Ciclo de vida del lote |
| `total_sent`, `total_created`, `total_updated`, `total_not_modified`, `total_failed` | Resultado agregado |
| `request_reference`, `response_summary`, `error_message` | Trazabilidad técnica |

Estados: `PENDING`, `IN_PROGRESS`, `COMPLETED`, `COMPLETED_WITH_ERRORS`, `FAILED`, `RETRY_PENDING`.

El estado general de la audiencia se deriva de sus lotes: todos exitosos → `SYNCED`; mezcla → `PARTIALLY_SYNCED`; todos fallidos → `FAILED`.

**Ejemplo de partición** (volumen referencial de la arquitectura: ~27,000 clientes activos, caso extremo de una sola audiencia grande):

```
Audiencia de 8,420 contactos → 9 lotes (8 de 1000 + 1 de 420)
```

---

## 8. Reglas de elegibilidad y exclusión

### 8.1 Reglas mínimas antes de sincronizar

1. El cliente debe pertenecer al ciclo vigente publicado (no a una corrida histórica).
2. La etiqueta debe ser elegible para campaña automática (§4.2).
3. Debe existir contacto válido para al menos un canal (celular para WhatsApp, email para Email).
4. No debe existir opt-out o bloqueo de comunicación (Do Not Contact list).
5. El contacto debe pasar normalización (§9).
6. No debe duplicarse dentro de la misma audiencia.
7. Debe excluirse INDETERMINADO salvo autorización explícita de negocio.
8. Debe excluirse VP/CQ salvo campaña especial autorizada.
9. Todo motivo de exclusión debe registrarse (no silenciarse).

### 8.2 Catálogo de motivos de exclusión

`CONTACTO_INVALIDO` · `SIN_CELULAR` · `SIN_EMAIL` · `OPTOUT` · `CANAL_NO_PERMITIDO` · `ETIQUETA_NO_ELEGIBLE` · `RIESGO_INDETERMINADO` · `REQUIERE_GESTION_MANUAL` · `CONTACTO_DUPLICADO` · `MULTI_ADVERTISER_EXCEDE_UMBRAL` · `ERROR_NORMALIZACION_CONTACTO` · `DATOS_INSUFICIENTES` · `PERFIL_INFOBIP_AMBIGUO` · `ERROR_VALIDACION_PRIVACIDAD`

Nota: `SIN_CELULAR` o `SIN_EMAIL` deben tratarse como exclusión **parcial de canal**, no total (ver §5.3), salvo que el contacto carezca de ambos.

---

## 9. Normalización de contacto

La fuente operativa para preparar audiencias no es el snapshot del ciclo publicado en UNOREP. La API toma el universo y la clasificación desde UNOREP, pero resuelve el celular y el email vigentes desde el read model de contacto resuelto en `APP_USER@UNOAPP`, con precedencia **Pinbox → IAM**.

### 9.1 Celular

- Eliminar espacios, guiones, paréntesis y caracteres no numéricos.
- Validar longitud (E.164 permite máximo 15 dígitos).
- Validar lada país.
- Convertir al formato **exactamente igual** al que usa OnBoarding hoy como `external_id` — **este es el punto crítico pendiente** (§11, pregunta 1). Sincronizar con un formato distinto generaría perfiles duplicados en vez de actualizar los existentes.
- No sincronizar si el formato no es confiable (marcar `ERROR_NORMALIZACION_CONTACTO`).

### 9.2 Email

- Validar formato.
- Normalizar espacios y aplicar minúsculas.
- Solo se sincroniza si el canal Email está habilitado (confirmado: sí, ver §2.1).

---

## 10. Atributos de retención en Infobip People

### 10.1 Atributos personalizados propuestos

`retention_cycle_id` · `retention_label` · `retention_risk_level` · `retention_action` · `retention_primary_advertiser_id` · `retention_advertiser_ids` (**tipo Lista, con `overwrite=true` en cada sync** — ver §6) · `retention_advertiser_count` · `retention_multi_advertiser_flag` · `retention_audience_id` · `retention_source` · `retention_last_sync_at` · `retention_contact_eligibility_status` · `retention_campaign_group`

Regla de minimización de datos (principio, no negociable):

> Si el dato no cambia el canal, la audiencia, el contenido o la elegibilidad de la campaña, no debe enviarse a Infobip.

**No se envía:** monto de contrato, detalle de rezago, detalle de cases, historial de quejas, información financiera sensible, comentarios internos, bitácora de gestión, score exacto, datos de calidad interna.

### 10.2 Tags

Formato: `RET_{cycle_id}_{label}_{risk_level}` (sin sufijo de canal — ver corrección en §5.3).

Se debe definir una política de vigencia/limpieza de tags históricos para evitar acumulación indefinida (pendiente, §11).

---

## 11. Preguntas abiertas restantes (Grupo B — requieren respuesta interna)

Estas no las resuelve la documentación pública de Infobip ni los documentos de insumo; requieren al equipo de OnBoarding, Sistemas o al Account Manager de Infobip.

| # | Pregunta | Dueño sugerido | Bloquea |
|---|---|---|---|
| 1 | Formato exacto del celular usado hoy como `external_id` por OnBoarding (¿lada, `+`, E.164?) | Sistemas / OnBoarding | Normalización (§9), evita duplicados |
| 2 | Endpoint y payload exacto que usa OnBoarding hoy para crear perfiles | Sistemas / OnBoarding | Diseño de matching |
| 3 | Atributos y tags personalizados que ya existen en la cuenta | Sistemas / OnBoarding | Evitar colisión de nombres |
| 4 | Fuente oficial de consentimiento/contactabilidad | Seguridad / Legal | Regla de elegibilidad (§8) |
| 5 | Ambientes disponibles en Infobip (sandbox, DEV/QA/PROD) | Sistemas / Infobip AM | Estrategia de pruebas |
| 6 | Volumen máximo esperado por ciclo y frecuencia de sincronizaciones | Negocio / PO | Dimensionamiento de lotes y jobs |
| 7 | Política de limpieza/expiración de tags históricos | Negocio / PO | Higiene de la cuenta Infobip |
| 8 | Si se requiere traer de vuelta métricas de campaña a la consola | Negocio / PO | Alcance de Sprint 2+ |
| 9 | Comportamiento exacto de partial upsert cuando el `external_id` ya existe con datos de OnBoarding (¿confirma no-sobrescritura?) | Sistemas / Infobip AM | Riesgo de romper datos de OnBoarding |
| 10 | Permisos por rol definitivos (¿quién puede sincronizar vs. solo consultar?) | Negocio / Seguridad | Modelo de autorización (§12) |

---

## 12. Roles y permisos

| Rol | Puede |
|---|---|
| Analista de Retención | Consultar cartera, consultar estado de sincronización. Preparar audiencia solo si se autoriza explícitamente. |
| Mercadotecnia / PO | Crear audiencias, sincronizar con Infobip, consultar auditoría, definir filtros de negocio, usar Infobip para ejecutar campañas. |
| Dirección | Solo vistas ejecutivas agregadas. Sin acceso a PII ni a sincronización. |
| Sistemas / Soporte | Consultar logs técnicos, reintentar lotes fallidos. No necesariamente crea campañas. |
| Seguridad / Auditoría | Consultar auditoría, revisar accesos y exportaciones. |

Modelo de doble capa (heredado de la arquitectura general): autorización funcional en .NET (menús, botones, acciones) + autorización técnica en Oracle (usuario restringido, solo vistas/procedimientos publicados).

---

## 13. Flujo funcional end-to-end

1. Usuario entra a la Consola de Retención (autenticado vía Entra ID a través del App Shell).
2. Consulta la cartera priorizada del ciclo vigente.
3. Aplica filtros (etiqueta, riesgo, región, producto, responsable).
4. Selecciona "Preparar audiencia".
5. La API consulta el resultado oficial vigente en UNOREP.
6. La API consulta en `APP_USER@UNOAPP` el read model de contacto resuelto para esos `advertiser_id`.
7. La API aplica reglas de elegibilidad (§8) y normaliza contactos (§9).
8. La API agrupa por celular normalizado y resuelve etiqueta/riesgo operativos (§4.2).
9. La API calcula el resumen preliminar (**modo dry-run**, no toca Infobip todavía):
  - advertisers origen, contactos únicos, contactos válidos por canal, excluidos por motivo, tag propuesto, volumen estimado de lotes.
10. La consola muestra el resumen; el usuario confirma.
11. La API crea el registro local de audiencia (`RETENTION_AUDIENCE`) y sus contactos (`RETENTION_AUDIENCE_CONTACT`), congelando el contacto resuelto usado para esa preparación.
12. La API crea o valida el tag en Infobip.
13. La API particiona en lotes de máximo 1000 (§7.3) y ejecuta *batch partial people upsert* con `overwrite=true` en atributos tipo lista.
14. La API asigna el tag a los perfiles sincronizados.
15. La API registra resultado por lote y por contacto (especialmente fallidos).
16. La API actualiza el estado general de la audiencia.
17. La consola muestra el resultado final (sincronizados / omitidos / fallidos / tag generado / fecha).
18. Mercadotecnia entra a Infobip y usa el tag para construir las campañas de Email y WhatsApp con las plantillas correspondientes a la etiqueta (§5.3).

### 13.1 Fase de reconciliación previa a producción (recomendada antes de sincronizar en real)

1. Seleccionar muestra representativa de clientes.
2. Normalizar celulares con las reglas propuestas.
3. Consultar/matchear contra perfiles existentes en Infobip.
4. Clasificar resultados: `MATCH_BY_EXTERNAL_ID`, `MATCH_BY_PHONE`, `NO_MATCH`, `MULTIPLE_MATCH`, `INVALID_CONTACT`.
5. Ajustar la regla de normalización si aparecen inconsistencias.
6. Documentar hallazgos y autorizar sincronización productiva.

Esta fase existe porque el `advertiser_id` no existe hoy en Infobip, y el celular es la única identidad compartida — cualquier discrepancia de formato se debe descubrir aquí, no en producción.

---

## 14. Manejo de errores, reintentos e idempotencia

### 14.1 Estados de error

`TEMPORARY_API_ERROR` · `RATE_LIMIT` · `AUTHENTICATION_ERROR` · `VALIDATION_ERROR` · `INVALID_PAYLOAD` · `PROFILE_CONFLICT` · `NETWORK_ERROR` · `UNKNOWN_ERROR`

### 14.2 Política de reintentos

- 429 → backoff exponencial (esperar, incrementar progresivamente, con tope de reintentos).
- 5xx → puede ser temporal; reintentar con límite definido.
- 4xx de validación → no reintentar automáticamente; requiere corrección de datos.
- Un lote fallido completo queda `RETRY_PENDING`; no se reprocesan contactos ya sincronizados exitosamente.
- Todo reintento se asocia al mismo `audience_id` — no se crea una audiencia nueva por reintento.

### 14.3 Idempotencia

- `audience_id` local único por preparación.
- El tag se deriva determinísticamente de ciclo + etiqueta + riesgo (§10.2) — reintentar no genera tags duplicados.
- La sincronización siempre usa upsert parcial por `external_id` — reintentar no duplica perfiles.
- Unicidad `audience_id` + `normalized_mobile` dentro de la audiencia local.

---

## 15. Seguridad y privacidad

1. El frontend nunca recibe PII completa salvo necesidad explícita de pantalla (y ahí, enmascarada por defecto).
2. Toda sincronización con Infobip ocurre backend-to-backend; nunca desde el navegador.
3. Las credenciales de Infobip (API key) no se exponen al frontend; viven en configuración segura del backend .NET, con rotación definida (pendiente confirmar mecanismo — §11).
4. Exportaciones analíticas excluyen PII por defecto (ver también `descripcion_consola_retencion.md` §26).
5. Toda preparación y sincronización de audiencia se audita (§16), incluso si no llega a sincronizarse.
6. Permisos por rol obligatorios (§12).
7. Se respetan opt-outs y bloqueos de comunicación antes de sincronizar (§8).
8. Logs no deben exponer PII completa — enmascarar celular/email en logs técnicos.

---

## 16. Auditoría mínima obligatoria

Por cada preparación/sincronización debe registrarse: usuario solicitante, fecha/hora, ciclo, filtros aplicados, etiquetas y riesgos incluidos, total de registros fuente, total de contactos únicos, total excluidos con motivo, total enviado a Infobip, tag generado, resultado general y por lote, errores relevantes, identificador de operación devuelto por Infobip (si aplica), y versión del resultado de retención utilizado.

---

## 17. Observabilidad

**Métricas:** audiencias creadas/sincronizadas/fallidas por día, contactos sincronizados/excluidos/fallidos, errores por tipo, tiempo promedio de sincronización y por lote, tasa de perfiles creados vs. actualizados vs. sin cambio, tasa de contactos inválidos, tasa de multi-advertiser.

**Logs:** inicio/fin de sincronización, metadata de request/response (sin PII completa), errores técnicos, identificadores de lote, correlation ID.

---

## 18. Parámetros configurables

Etiquetas elegibles para campaña · prioridad de selección por contacto · canales habilitados · máximo de `advertiser_id` por celular antes de exclusión · formato de tag · vigencia de audiencia · límite máximo de contactos por audiencia · límite de reintentos · tamaño de lote (referencial: 1000, confirmado con Infobip) · reglas de exclusión · campos enviados a Infobip · modo de ejecución (preview / dry-run / sync real).

---

## 19. Endpoints internos candidatos de la API de Retención

Conceptuales — a diseñar conforme a estándares de la organización:

```
Consulta y preparación
  GET  /api/retention/audiences/preview
  POST /api/retention/audiences

Detalle
  GET  /api/retention/audiences/{audienceId}
  GET  /api/retention/audiences/{audienceId}/contacts
  GET  /api/retention/audiences/{audienceId}/exclusions

Sincronización
  POST /api/retention/audiences/{audienceId}/sync/infobip
  GET  /api/retention/audiences/{audienceId}/sync/status
  POST /api/retention/audiences/{audienceId}/sync/retry

Auditoría
  GET  /api/retention/audiences/{audienceId}/audit
  GET  /api/retention/audiences/{audienceId}/batches

Catálogos
  GET  /api/retention/audience-eligibility-rules
  GET  /api/retention/infobip/tags/suggest
```

---

## 20. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Crear perfiles duplicados en Infobip | `external_id` = celular normalizado + upsert parcial exclusivamente. Fase de reconciliación previa (§13.1). |
| Romper datos de OnBoarding | Nunca usar full upsert; enviar solo atributos `retention_*`. |
| Enviar PII innecesaria | Minimización de datos (§10.1); sincronización backend-to-backend. |
| Contactar clientes no elegibles | Reglas de elegibilidad, opt-out y exclusiones (§8). |
| Agrupar varios clientes reales bajo un celular | `multi_advertiser_flag`, `advertiser_count`, regla de prioridad documentada (§4.2). |
| `retention_advertiser_ids` acumula histórico entre ciclos | Forzar `overwrite=true` en cada sincronización (§6). |
| Marketing no encuentra la audiencia en Infobip | Convención de tag clara y consistente (§10.2), sin sufijo de canal. |
| Fallas parciales en batch | Trazabilidad por lote y reintentos controlados (§14). |
| Ambigüedad entre ciclo y audiencia | Incluir `cycle_id` y `audience_id` en atributos/tags. |
| Exceso de tags históricos | Política de vigencia y limpieza (pendiente, §11). |
| Cambios futuros en identidad interna (resolución de duplicidad de `advertiser_id`) | Encapsular lógica de resolución de identidad en la API, no en el frontend. |

---

## 21. Fases de implementación recomendadas

**Fase 0 — Diagnóstico.** Revisar configuración actual de Infobip, flujo de OnBoarding, confirmar `external_id`, validar comportamiento del upsert parcial, probar con muestra controlada.

**Fase 1 — Audiencia local y dry-run.** Crear audiencia local, aplicar filtros, validar contactos, agrupar por celular, calcular resumen. No sincroniza todavía.

**Fase 2 — Sincronización People.** Crear/validar tag, ejecutar partial upsert por lotes, asignar tags, registrar auditoría, mostrar resultado. *(Este es el alcance de Sprint 1 / MVP, según §2.1.)*

**Fase 3 — Reintentos y soporte.** Reintentar lotes fallidos, mejorar observabilidad, agregar consulta de detalle técnico, ajustar reglas de exclusión.

**Fase 4 — Evolución (Sprint 2+).** Automatizar el disparo sin intervención humana, crear segmentos automáticamente, leer métricas básicas de campaña de vuelta a la consola, evaluar integración con Moments/Channels solo si negocio lo justifica formalmente.

---

## 22. Criterios de éxito

La integración se considera exitosa si:

- Sincroniza audiencias de retención con Infobip sin requerir descarga local de PII.
- No duplica perfiles ya existentes por OnBoarding.
- Respeta el `external_id` basado en celular.
- Agrupa correctamente múltiples `advertiser_id` por contacto y conserva trazabilidad.
- Registra auditoría suficiente para reconstruir qué se envió, cuándo y por quién.
- Permite a Mercadotecnia operar campañas de Email y WhatsApp dentro de Infobip usando el tag generado.
- No duplica funcionalidades nativas del SaaS.
- Maneja errores parciales y permite reintentos controlados sin duplicar trabajo.
- Mantiene bajo acoplamiento: la consola nunca invoca Infobip directamente desde el frontend, ni Infobip decide clasificación de riesgo.

---

## 23. Conclusión

La integración ligera entre la Consola de Retención e Infobip, en el alcance de Sprint 1/MVP, se limita a preparar y sincronizar audiencias vía People — nunca a enviar mensajes directamente. La decisión de identidad más importante (`external_id = celular normalizado`, upsert parcial, sin creación de perfiles por `advertiser_id`) está validada contra la documentación oficial de Infobip y no debe modificarse sin un proyecto formal de migración de identidad.

Quedan diez preguntas internas pendientes (§11) que no bloquean el diseño funcional y técnico documentado aquí, pero sí bloquean el paso a construcción — en particular, el formato exacto del `external_id` actual (pregunta 1) debe resolverse antes de escribir una sola línea de código de normalización, o se corre el riesgo de crear duplicados en vez de actualizar los perfiles existentes de OnBoarding.
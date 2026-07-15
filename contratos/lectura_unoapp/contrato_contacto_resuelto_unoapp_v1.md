# Contrato de Lectura — Contacto Resuelto en APP_USER@UNOAPP

**Versión:** 1.0  
**Estado:** Aprobado como decisión de diseño para MVP de integración con audiencias e Infobip.  
**Plano:** `APP_USER@UNOAPP`  
**Consumidor:** API .NET del módulo de Retención  
**Propósito:** Resolver el contacto operativo vigente por `advertiser_id` para preparación de audiencias, activación y sincronización con Infobip, sin mover la decisión analítica fuera de UNOREP.

---

## 1. Decisión

La preparación de audiencias **no** tomará celular y email del snapshot publicado del ciclo en UNOREP.  
La API consumirá un **read model de contacto resuelto** en `APP_USER@UNOAPP`, construido con la siguiente prioridad:

1. **Nivel 1 — Pinbox (`mob_user@UNOAPP`)**: fuente operativa más confiable y actualizada.
2. **Nivel 2 — IAM**: respaldo cuando Pinbox no tenga dato válido o utilizable.

UNOREP sigue siendo la única fuente oficial para:

- universo del ciclo
- score
- etiqueta
- nivel de riesgo
- acción sugerida
- versión publicada del resultado

---

## 2. Patrón de composición

La API compone dos planos sin mezclar sus responsabilidades:

- **UNOREP**: decide y publica el resultado oficial del ciclo.
- **UNOAPP**: resuelve el contacto operativo vigente y registra la operación humana.

El resultado de esta composición se congela al crear la audiencia en `RETENTION_AUDIENCE_CONTACT`.

---

## 3. Objeto lógico requerido

Se define como objeto lógico mínimo un read model consumible por la API, con nombre recomendado:

`vw_ret_contact_resolved`

La implementación física puede ser:

- vista
- tabla mantenida por proceso batch
- tabla refrescada por procedimiento

La decisión entre estas variantes queda a Sistemas, siempre que el contrato funcional y de datos se respete.

---

## 4. Clave y granularidad

- **Clave principal funcional:** `advertiser_id`
- **Grano:** 1 registro vigente por `advertiser_id`

Si existe más de un posible contacto vigente para el mismo `advertiser_id`, el read model debe resolverlo antes de exponerlo a la API.

---

## 5. Campos mínimos del contrato

| Campo | Descripción |
|---|---|
| `advertiser_id` | Identificador del cliente |
| `resolved_mobile_raw` | Celular resuelto antes de normalización final |
| `resolved_email_raw` | Email resuelto antes de normalización final |
| `resolved_mobile_normalized` | Celular ya homologado al formato operativo definido por Sistemas, cuando aplique |
| `resolved_email_normalized` | Email normalizado en minúsculas y sin espacios laterales |
| `mobile_source_level` | `1` para Pinbox, `2` para IAM |
| `email_source_level` | `1` para Pinbox, `2` para IAM |
| `mobile_source_system` | `PINBOX` o `IAM` |
| `email_source_system` | `PINBOX` o `IAM` |
| `mobile_source_updated_at` | Última fecha conocida del dato de celular en la fuente elegida |
| `email_source_updated_at` | Última fecha conocida del dato de email en la fuente elegida |
| `mobile_valid_flag` | Indicador de validez operativa del celular |
| `email_valid_flag` | Indicador de validez operativa del email |
| `contact_resolution_reason` | Explicación breve de la regla que eligió la fuente final |
| `resolved_at` | Fecha/hora en que el read model produjo el contacto vigente |

Campos opcionales recomendados:

- `contact_name`
- `whatsapp_contactable_flag`
- `email_contactable_flag`
- `consent_status`
- `consent_source_system`
- `consent_updated_at`

---

## 6. Reglas de resolución

### 6.1 Precedencia de fuentes

- Si Pinbox tiene celular válido, se usa Pinbox para celular.
- Si Pinbox no tiene celular válido, se usa IAM como fallback.
- Si Pinbox tiene email válido, se usa Pinbox para email.
- Si Pinbox no tiene email válido, se usa IAM como fallback.

La precedencia se resuelve **por atributo**, no por registro completo.  
Ejemplo: celular desde Pinbox y email desde IAM es válido.

### 6.2 Regla de no mezcla analítica

El read model no asigna score, etiqueta, riesgo ni acción.  
Solo resuelve contacto operativo vigente.

### 6.3 Regla de congelamiento

Cuando el usuario confirma la preparación de audiencia:

- la API lee este read model
- normaliza el contacto para Infobip
- persiste el resultado usado en `RETENTION_AUDIENCE_CONTACT`

Los reintentos posteriores de esa misma audiencia usan el snapshot congelado, no una relectura del read model.

---

## 7. Casos de uso consumidores

Este contrato aplica a:

- preview de audiencia
- creación de audiencia
- sincronización con Infobip
- diagnósticos de contactabilidad previos a sync

No reemplaza:

- vistas analíticas publicadas en UNOREP
- exportaciones históricas del ciclo
- bitácora operativa de gestión manual

---

## 8. Consideraciones de seguridad

- La API accede al read model con usuario técnico restringido.
- El frontend no consulta directamente `APP_USER@UNOAPP`.
- Los logs técnicos deben enmascarar celular y email.
- Si existe dato de consentimiento, debe venir de la fuente oficial aprobada por Seguridad/Legal.

---

## 9. Pendientes técnicos para aterrizaje físico

1. Nombre físico definitivo del objeto (`view` o `table`).
2. Nombres exactos de tablas fuente en `mob_user@UNOAPP` e IAM.
3. Estrategia de refresco del read model.
4. Usuario técnico y grants exactos para la API.
5. Regla oficial de normalización al formato usado por OnBoarding como `external_id`.

---

## 10. Relación con otros contratos

- La decisión analítica sigue en [contratos/lectura_unorep/contratos_lectura_unorep_v1.sql](c:/proyectosNet/consolaRetencion/contratos/lectura_unorep/contratos_lectura_unorep_v1.sql).
- La especificación funcional de integración con Infobip consume este contrato junto con el resultado oficial del ciclo en [Integracion/integracion_consola_infobip.md](c:/proyectosNet/consolaRetencion/Integracion/integracion_consola_infobip.md).
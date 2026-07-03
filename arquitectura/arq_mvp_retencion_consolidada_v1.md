# Arquitectura de solución
## MVP — Modelo de Riesgo de Baja y Retención Proactiva

**Documento unificado | Versión 1.0 | Abril 2026**  
**Estado:** Propuesta para socialización con IT, Arquitectura y Negocio

## Fuente de verdad y criterio de priorización

- El documento consolida las propuestas del Data Manager y del Arquitecto de Aplicaciones.
- En conflictos, prevalece el criterio del Data Manager.
- Las buenas prácticas de modularidad y escalabilidad del Arquitecto se integran en la solución.

## Propósito

Definir la arquitectura de solución del MVP para el programa de riesgo de baja y retención proactiva.

### Objetivos funcionales

- Consolidar datos de múltiples fuentes en un plano de decisión único.
- Calcular periódicamente score, etiqueta y nivel de riesgo por cliente.
- Exponer un tablero operativo para análisis y priorización de acciones.
- Administrar parámetros del modelo sin despliegues de código.
- Gestionar bitácora operativa, exportaciones y marcados manuales.
- Proveer trazabilidad completa de cada ciclo de cálculo.
- Preparar la evolución hacia activación automática de campañas con Infobip.

## Principios rectores

### Valor primero

- Priorizar time-to-value sobre optimización teórica.
- Reutilizar Oracle 11g, DBMS_SCHEDULER, DB links y el ETL Python corporativo.
- Evitar sobreingeniería que retrase la entrega.

### Separación de planos

| Plano | Tecnología | Responsabilidad |
|---|---|---|
| Analítico-decisional | Oracle 11g, esquema `report_work@unorep` | Decide y publica. |
| Transaccional-operativo | Oracle de la aplicación, ambientes DEV/QA/PROD | Registra la operación humana. |

### Oracle gobierna, Python abastece

- La lógica del motor vive en PL/SQL dentro de Oracle.
- El ETL Python solo resuelve integraciones no accesibles desde Oracle, principalmente Panel Marketing en SQL Server.
- Python no implementa lógica de negocio del modelo.

### Batch-first, event-ready

- El MVP usa ingestas diarias y cálculo mensual.
- La arquitectura queda preparada para evolucionar a activación e integraciones más cercanas a tiempo real sin rediseño.

### Serving estable para consumidores

- Ningún consumidor consulta directamente las fuentes origen.
- El tablero y cualquier componente futuro consumen solo datasets publicados desde la capa Serving en UNOREP.

### Trazabilidad total del cálculo

Cada ciclo de cálculo debe quedar ligado a:

- Versión de parámetros utilizada.
- Datos fuente utilizados.
- Resultado por cliente.
- Condición que disparó la etiqueta.
- Fecha de ejecución.
- Corrida o versión del ciclo.

### Modularidad y bajo acoplamiento

- Cada componente tiene responsabilidades claras y límites definidos.
- La API .NET actúa como barrera entre el plano analítico y el frontend.
- El motor PL/SQL se encapsula en paquetes.
- El diseño modular facilita evolución progresiva sin rediseño futuro.

## Alcance del MVP

### Incluye

- Ingesta y normalización de datos desde IAM, SAP, Pinbox y Panel Marketing.
- Motor de segmentación en PL/SQL: score, etiqueta y nivel de riesgo por cliente.
- Configuración de reglas del modelo (HU1.2) sin despliegue de código.
- Calidad de datos y manejo de riesgo indeterminado.
- Tablero operativo en aplicación .NET con micro frontend integrable al App Shell.
- Bitácora de gestión manual con comentarios y seguimiento.
- Exportaciones controladas con auditoría.
- Marcado operativo ligero por cliente.
- Re-cálculo de ciclos sin sobrescribir resultados históricos.
- Trazabilidad completa por ciclo.
- Visualización de calidad de datos y riesgo indeterminado.

### Fuera de alcance

- Disparo automático de campañas e integración activa con Infobip.
- NPS y win-back automatizado.
- Modelo ML predictivo.
- Near real-time o tiempo real.
- Arquitectura distribuida, lakehouse o streaming.
- Dashboards al cliente final.
- Webinars y quick wins automatizados.

## Decisiones técnicas justificadas

### Oracle 11g `report_work@unorep` como plano analítico-decisional

**Decisión:** Usar `report_work@unorep` como base de la capa de datos del sistema.

**Justificación:**

- Ya alcanza casi todas las fuentes de datos necesarias mediante DB links.
- Oracle 19c está desacoplada física y lógicamente; no existen ETLs activos hacia ella.
- Permite entregar el MVP rápidamente con bajo costo de integración.
- La arquitectura por capas lógicas Landing, Integration y Serving mitiga la dependencia de la versión.

### PL/SQL como motor de segmentación

**Decisión:** Toda la lógica de score, segmentación, trazabilidad y parametrización vive en Oracle, encapsulada en paquetes PL/SQL.

**Justificación:**

- Minimiza latencia y acoplamiento entre motor y datos.
- Facilita ejecución batch mensual y recálculo versionado.
- Simplifica la trazabilidad entre parámetros, datasets y resultados.
- Reduce la complejidad en la API .NET.
- El encapsulamiento en paquetes facilita mantenimiento y evolución futura.

### DBMS_SCHEDULER como orquestador batch

**Decisión:** Implementar la ejecución de procesos mediante jobs de Oracle DBMS_SCHEDULER.

**Justificación:**

- Es el mecanismo habitual en la organización.
- Hay permiso para crear nuevos jobs.
- No hay restricción horaria para cargas nocturnas.
- Evita introducir una plataforma nueva de orquestación para el MVP.
- La bitácora de ejecución integrada facilita soporte y observabilidad.

### ETL Python como adaptador de integración

**Decisión:** Usar el ETL Python corporativo solo para fuentes no accesibles desde Oracle.

**Justificación:**

- Panel Marketing reside en SQL Server aislado, sin API ni acceso Oracle directo.
- El ETL puede conectarse a todas las bases y escribir en `report_work@unorep`.
- Resuelve el mayor gap de integración sin introducir tecnología nueva.
- Python no implementa lógica de negocio; solo abastece datos al plano Oracle.

### Aplicación web .NET como consola operativa

**Decisión:** Construir el tablero como módulo nuevo en .NET, no como dashboard en Tableau.

**Justificación:**

- El caso de uso requiere operación transaccional: bitácora, parámetros, exportaciones y activación.
- Tableau es útil para visualización, pero limitado para workflows y acciones operativas.
- Alinea con la estrategia tecnológica objetivo de la organización.

### Micro frontend integrado al App Shell

**Decisión:** Diseñar el módulo de retención como micro frontend integrable al App Shell corporativo, con operación relativamente autónoma mientras la integración madura.

**Justificación:**

- El App Shell es el punto de entrada estratégico con autenticación centralizada en Entra ID.
- Reduce dispersión de experiencia de usuario.
- Prepara integración con otros módulos.
- La autonomía relativa protege el calendario del MVP ante retrasos del App Shell.

### API .NET ligera dedicada al módulo

**Decisión:** Construir un backend/API propio, pequeño y orientado a los casos de uso del módulo.

**Justificación:**

- Encapsula acceso a Oracle y actúa como barrera de abstracción.
- Permite composición entre el plano analítico y el transaccional.
- Evita acoplamiento directo del frontend a la base de datos.
- Facilita evolución hacia acciones operativas futuras, como activación e Infobip.

### Separación entre BD analítica y BD transaccional

**Decisión:** Mantener dos planos persistentes distintos con responsabilidades no intercambiables.

**Justificación:**

- Evita contaminar el plano analítico con lógica operativa de UI.
- La BD transaccional de aplicación tiene ambientes propios DEV/QA/PROD.
- Simplifica la gobernanza de datos y las responsabilidades entre equipos.

**Regla maestra:** UNOREP decide y publica. La BD transaccional registra la operación humana. Esta separación se mantiene en toda la evolución del sistema.

## Arquitectura objetivo del MVP

| Dominio | Tecnología | Responsabilidad principal |
|---|---|---|
| Datos y decisión | Oracle 11g (`report_work@unorep`) | Ingesta, motor, serving, calidad, parámetros e histórico |
| Aplicación | API .NET + micro frontend | Tablero, bitácora, exportaciones y seguridad funcional |
| Transaccional-operativo | Oracle de aplicación (DEV/QA/PROD) | Bitácora, marcados y auditoría de exportaciones |
| Integración externa | ETL Python / conectores futuros | Panel Marketing hoy |

## Componentes de la solución

### Fuentes origen

| Fuente | Detalle |
|---|---|
| IAM (`rep_*@unorep`) | DB links a esquemas réplica. Clientes, productos, estatus, cases, etiquetas, valor contrato, datos comerciales y de contacto. |
| `SAP_USER@UNOREP` | Mismo motor Oracle, distinto esquema. Rezago y morosidad. |
| Pinbox (`mob_user@UNOAPP`) | Oracle remoto con accesos gestionados por DBS. Retroalimentación FDV y campaña en oportunidades. |
| Panel Marketing (SQL Server) | Sin DB link ni API. Extracción vía ETL Python. Visitas por sitio, antigüedad y publicación del sitio. |
| Catálogos de referencia | Catálogo score por producto y catálogo de tipos de case. Mantenidos en UNOREP. |

### Plano analítico-decisional: Oracle 11g UNOREP

#### Landing

Responsabilidad: aterrizaje de datos extraídos desde fuentes, sin reglas de negocio.

- Tablas de recepción por fuente y fecha/hora.
- Metadatos de carga y estado de recepción del ETL.
- Punto de entrada certificado para el ETL Python.

#### Integration

Responsabilidad: homologación, limpieza, consolidación y canonización de datos.

- Modelo integrado por `advertiser_id`.
- Flags operativos: `tiene_monto`, `queja_activa`, `antigüedad_case`, validez de contacto y vigencia de contrato.
- Preagregados mensuales.
- Normalización de productos, cases, visitas y rezago.

#### Serving

Responsabilidad: publicar datasets listos para motor, API y tablero. Ningún consumidor accede a capas internas.

- Resultados del score por ciclo y trazabilidad por cliente.
- Vistas operativas y ejecutivas.
- Universos de campaña exportables.
- Dataset de riesgo indeterminado.

#### Control & Config

Responsabilidad: gobernar ejecución, calidad, configuración y observabilidad.

- Parámetros vigentes y programados, con historial de versiones.
- Control de jobs y reconciliación.
- Eventos de calidad y catálogos.

### Motor de segmentación (PL/SQL)

Núcleo decisional del sistema, encapsulado en paquetes PL/SQL.

| Aspecto | Detalle |
|---|---|
| Entradas | Datos consolidados en Serving/Integration, parámetros efectivos vigentes, catálogos y referencias. |
| Proceso | Calcula score por producto y por cliente, asigna etiqueta según jerarquía de prioridad, determina nivel de riesgo y acción sugerida, registra condición disparadora, gestiona riesgo indeterminado. |
| Salidas | Resultado por cliente/ciclo, detalle por producto, etiqueta/nivel/acción sugerida, resumen de ciclo, universos exportables. |
| Capacidades | Re-cálculo versionado sin sobrescritura, relación ciclo-versión de parámetros. |

### Orquestación batch (DBMS_SCHEDULER)

Gestiona la ejecución automática de todos los jobs del sistema:

- Extracción diaria: IAM, SAP y Pinbox.
- Recepción y certificación de Panel Marketing, mensual vía ETL Python.
- Normalización diaria en capa Integration.
- Control de calidad diario.
- Cálculo mensual del motor de segmentación.
- Publicación de datasets en capa Serving.
- Purga de histórico técnico.

### ETL Python corporativo

Adaptador de integración para fuentes no accesibles desde Oracle.

- Extrae datos desde SQL Server de Panel Marketing.
- Carga tablas Landing en UNOREP.
- Ejecuta procedimientos de confirmación de carga.
- Registra estatus de integración externa.

**Principio de uso:** Python solo resuelve integración y abastecimiento. No implementa lógica de negocio del modelo. La lógica vive en Oracle.

### API del módulo de retención (.NET)

Backend ligero y orientado a casos de uso.

- Valida token y roles con Microsoft Entra ID.
- Expone endpoints de tablero, detalle, trazabilidad y parámetros.
- Consulta UNOREP para datos analíticos.
- Lee y escribe en la BD transaccional de la aplicación.
- Compone la respuesta final al frontend.
- Registra auditoría operativa donde aplica.

**Regla:** La API orquesta consumo; no duplica la lógica del motor. Actúa como barrera de acceso y punto único de composición.

### Micro frontend de retención

Módulo de presentación integrable al App Shell corporativo.

- Vista operativa para Analista y PO: lista priorizada, filtros, drill-down y exportaciones.
- Vista ejecutiva resumida para Dirección.
- Administración de parámetros del modelo (HU1.2).
- Bitácora y marcados operativos.
- Visualización de riesgo indeterminado y calidad de datos.
- Diseñado para ser embebible en el App Shell y operar relativamente autónomo en la fase inicial del MVP.

### App Shell corporativo

Relevante para este módulo en:

- Autenticación centralizada con Microsoft Entra ID.
- Interpretación del JWT y habilitación visual por roles.
- Carga dinámica del micro frontend.
- Menú y navegación centralizada.

### Base de datos transaccional de aplicación

Oracle de la aplicación, con ambientes DEV/QA/PROD. Exclusiva para operación humana.

- Bitácora de gestión manual con comentarios y seguimiento.
- Marcados operativos ligeros por cliente.
- Auditoría de exportaciones.
- Metadatos operativos de la aplicación.

**Regla:** No es fuente de verdad del motor. Complementa el plano analítico con la operación humana. UNOREP decide; esta BD registra.

## Roles y responsabilidades por componente

| Componente | Responsable | Responsabilidades principales |
|---|---|---|
| Oracle UNOREP | Mario Benitez | Recepción de datos, integración, score, segmentación, parámetros, calidad, serving, histórico y observabilidad técnica. |
| ETL Python | Jeavaej | Conectividad a fuentes externas, extracción de Panel Marketing y entrega certificada a Oracle. |
| API .NET | Juan Durón | Exposición de servicios, composición de datos, seguridad funcional, escrituras operativas y auditoría de interacción. |
| Micro frontend | Juan Durón | Experiencia de usuario, filtros, tablero, formularios, navegación de detalle y acceso por rol. |
| App Shell | Jeavaej | Sesión, hosting del módulo, integración con Entra ID, menú y navegación centralizada. |
| Mercadotecnia / PO | Negocio | Administración funcional de parámetros, ajuste del modelo, solicitud de re-cálculos y validación funcional. |
| Analista de Retención | Operación | Consumo operativo del tablero, revisión de casos, gestión manual, uso de exportaciones y seguimiento de riesgo indeterminado. |
| Dirección | Negocio | Consumo de vistas resumidas y seguimiento ejecutivo del programa. |

## Flujos end-to-end

### Flujo 1 — Ingesta diaria

Objetivo: actualizar el plano analítico con cambios recientes de fuentes operativas.

1. DBMS_SCHEDULER lanza extracción diaria desde IAM (`rep_*@unorep`).
2. Se extraen datos de `SAP_USER@UNOREP`.
3. Se extraen datos de Pinbox (`mob_user@UNOAPP`).
4. Los datos aterrizan en Landing con fecha y hora de carga.
5. Se registra volumen, estado, fuente y ejecución.
6. Se disparan validaciones básicas de recepción.

**Salida:** Landing actualizado y registro de control de carga.

### Flujo 2 — Ingesta mensual de Panel Marketing

Objetivo: incorporar visitas del mes vencido para soporte de la dimensión de frecuencia y localización (FL).

1. ETL Python se conecta a SQL Server de Panel Marketing.
2. Extrae visitas por sitio y metadatos necesarios.
3. Escribe en tablas Landing de UNOREP.
4. Ejecuta procedimiento de certificación o confirmación en Oracle.
5. Oracle registra frescura, conteos y estado de recepción.
6. Si falla, se generan alertas y se marca el insumo como desactualizado, con riesgo indeterminado.

**Salida:** Landing de marketing poblado y control de entrega de fuente externa.

### Flujo 3 — Normalización e integración

Objetivo: generar un modelo unificado por `advertiser_id`.

1. Procesos PL/SQL toman datos de Landing.
2. Se homologan claves y se validan campos críticos.
3. Se calculan flags: `tiene_monto`, `queja_activa`, `antigüedad_case`, validez de contacto y vigencia de contrato.
4. Se agregan visitas a nivel advertiser/mes.
5. Se consolida rezago, productos, cases y retroalimentación FDV.
6. Se publican tablas en capa Integration.

**Salida:** Modelo unificado y canonizado.

### Flujo 4 — Calidad de datos

Objetivo: detectar problemas que afecten el cálculo del modelo.

1. Se validan reglas de completitud, formato, consistencia y frescura.
2. Se detectan outliers simples.
3. Se generan eventos agregados de calidad.
4. Se marcan clientes con datos insuficientes para riesgo indeterminado.
5. Se genera reporte de calidad del ciclo.

**Salida:** Dataset de calidad, eventos abiertos y lista de clientes con riesgo indeterminado.

### Flujo 5 — Cálculo mensual del motor

Objetivo: emitir score, etiqueta y nivel de riesgo del universo activo.

1. Se identifica el ciclo a calcular.
2. Se toma la versión vigente de parámetros.
3. Se selecciona el universo válido de clientes.
4. Se calcula score por producto y se suma score por cliente.
5. Se evalúan etiquetas en orden de prioridad.
6. Se asigna nivel de riesgo y acción sugerida.
7. Se marca riesgo indeterminado cuando aplique.
8. Se persiste resultado por cliente y detalle por ciclo.
9. Se actualizan resúmenes del ciclo.
10. Se generan universos para acción o campaña manual.

**Salida:** Resultado mensual completo y trazable.

### Flujo 6 — Consumo operativo del tablero

Objetivo: permitir consulta y operación diaria desde el módulo de Retención.

1. El usuario entra al App Shell y se autentica con Microsoft Entra ID.
2. Se habilita el micro frontend según roles.
3. El frontend invoca la API del módulo.
4. La API consulta UNOREP para datasets analíticos.
5. La API consulta la BD transaccional para bitácora y marcados.
6. La API compone la respuesta y el usuario visualiza lista priorizada, detalle y trazabilidad.

**Salida:** Vista operativa o ejecutiva según rol.

### Flujo 7 — Administración de parámetros

Objetivo: permitir ajuste del modelo sin desplegar código.

1. El PO accede al panel de parámetros.
2. Modifica umbrales, reglas o catálogos permitidos.
3. La API valida autorización.
4. Oracle registra nueva versión programada con historial de diferencias.
5. El siguiente ciclo usa la nueva versión automáticamente.

**Salida:** Parámetros programados y trazabilidad de cambio.

### Flujo 8 — Re-cálculo de ciclo

Objetivo: corregir o recalcular un periodo sin perder histórico.

1. PO o Sistemas solicita re-cálculo.
2. Oracle genera una nueva corrida o versión del mismo ciclo.
3. Se conserva intacta la corrida original.
4. El tablero puede consultar ambas versiones.
5. La organización mantiene auditabilidad plena.

**Salida:** Nueva corrida del ciclo sin sobrescritura histórica.

### Flujo 9 — Exportaciones controladas

Objetivo: entregar universos de acción para campañas manuales o seguimiento.

1. El usuario autorizado consulta un segmento o universo en el tablero.
2. Solicita exportación.
3. La API genera la salida consumiendo Serving en UNOREP.
4. Registra la auditoría en la BD transaccional.
5. El archivo o listado queda disponible para otro equipo o sistema.

**Salida:** Universo exportado y auditoría de exportación.

## Modelo de seguridad

### Autenticación

- Microsoft Entra ID centraliza la autenticación.
- El App Shell centraliza la sesión.
- El micro frontend consume el contexto de sesión desde el shell.
- La API .NET valida el token en cada solicitud.

### Roles MVP

| Rol | Acceso |
|---|---|
| Analista de Retención | Tablero completo, detalle de clientes, bitácora, exportaciones y riesgo indeterminado. |
| Mercadotecnia / PO | Todo lo anterior más administración de parámetros y solicitud de re-cálculos. |
| Dirección / Solo lectura | Vistas ejecutivas resumidas. Sin acceso a operación ni parámetros. |

### Autorización

Modelo de doble capa:

- En .NET: menús, pantallas, acciones, botones de exportación, edición de parámetros y solicitud de re-cálculo.
- En Oracle: usuario técnico restringido, acceso solo a vistas y procedimientos publicados, sin acceso libre a tablas internas del motor.

## Calidad de datos

Se monitorean las siguientes dimensiones con ejecución diaria y reporte por ciclo:

| Dimensión | Descripción |
|---|---|
| Frescura por fuente | Verificación de que cada fuente actualizó dentro del período esperado. |
| Validación de contacto | Completitud y validez de datos de contacto por cliente. |
| Productos no mapeados | Productos en fuentes origen sin equivalente en catálogos del modelo. |
| Visitas faltantes | Clientes activos sin registro de visitas en Panel Marketing. |
| Rezago no actualizado | Clientes con información de morosidad no refrescada. |
| Inconsistencias | Datos contradictorios entre fuentes para el mismo `advertiser_id`. |

### Clasificación de eventos

- Críticos: alertan o bloquean el cálculo. El cliente queda con riesgo indeterminado hasta resolución.
- No críticos: se reportan y registran en el dataset de calidad sin bloquear el cálculo.

## Histórico y retención de datos

| Tipo | Detalle |
|---|---|
| Histórico analítico — 24 meses | Score por cliente/ciclo, productos considerados, etiqueta y nivel, condición disparadora, versión de parámetros, corrida/versión del ciclo y resúmenes de ciclo. |
| Histórico técnico — 6 meses | Ejecuciones de jobs, reconciliación, calidad de datos, alertas técnicas y frescura de fuentes. |

## Observabilidad y control operativo

Capacidad mínima de observabilidad implementada dentro de UNOREP para facilitar soporte y detectar fallos de extracción.

### Registros requeridos por cada job y ciclo

- Job ejecutado, inicio, fin y estado.
- Fuente, registros esperados vs. recibidos y diferencia contra corrida previa.
- Error técnico y reintentos.
- Datos desactualizados y eventos de calidad abiertos.

**Objetivo MVP:** facilitar soporte, detectar fallos de extracción y dar soporte al tratamiento de riesgo indeterminado. En fases posteriores puede evolucionar hacia monitoreo formal con alertas activas.

## Volumen y capacidad

| Dimensión | Valor referencial |
|---|---|
| Clientes activos | ~27,000 |
| Productos promedio por cliente | ~5 |
| Cases mensuales | ~3,500 |
| Visitas mensuales (Panel Marketing) | ~335,000 |
| Usuarios concurrentes del tablero | ~10 |

**Conclusión:** Los volúmenes del MVP no requieren arquitectura distribuida. Oracle 11g es suficiente para la carga analítica proyectada. El diseño modular permite escalar componentes individualmente si el volumen crece en fases posteriores.

## Riesgos arquitectónicos y mitigación

| Riesgo | Descripción | Mitigación |
|---|---|---|
| Dependencia de Oracle 11g | Tecnología legacy que podría limitar funcionalidad futura. | Arquitectura por capas lógicas, PL/SQL encapsulado en paquetes, API .NET como barrera de acceso y diseño modular para migración gradual. |
| Panel Marketing aislado | Falla en la extracción mensual degrada la señal FL. | ETL Python formalizado con certificación de entrega, validación de frescura y riesgo indeterminado cuando falte el insumo. |
| App Shell sin ambiente definitivo | La integración puede madurar después del MVP. | Micro frontend diseñado para integrarse, pero con capacidad de operación relativamente autónoma al inicio. |
| Evolución rápida del modelo | Ajustes frecuentes de parámetros y reglas. | Parámetros configurables en Oracle con versionado, re-cálculo sin sobrescritura y trazabilidad completa. |
| Mezcla analítico / operativo | Duplicidad o ambigüedad entre UNOREP y la BD transaccional. | Regla clara: UNOREP decide y publica; la BD transaccional registra la operación humana. |

## Estrategia de despliegue

- Desarrollo en entorno tipo preproducción.
- El micro frontend puede operar de forma relativamente autónoma si la integración con el App Shell tarda más que el MVP.
- Evolución a producción con QA previo.
- La BD transaccional de aplicación tendrá ambientes propios: DEV, QA y PROD.
- El plano UNOREP es compartido; los objetos del módulo se crean con naming convention propio para evitar colisiones.

## Evolución prevista post-MVP

### Sprint 2 — Activación automática

Objetivo: evolucionar de universos manuales a integración con Infobip.

- Mantener en UNOREP la generación de universos de activación.
- Incorporar conector de activación vía API o servicio hacia Infobip.
- Consumir universos por canal: Email y WhatsApp.
- Registrar trazabilidad de envío y estado de campaña.

### Mediano plazo

- Incorporación de más señales al modelo: NPS y leads consolidados.
- Sustitución de visitas por señales de mayor calidad.
- ML para priorización o refinamiento del score.
- Cálculos más frecuentes: quincenal o semanal.
- Customer Health Score más robusto.
- Win-back automatizado.

## Conclusión

La arquitectura propuesta está orientada a entrega rápida de valor sin sacrificar escalabilidad funcional.

### Síntesis

- Reutiliza infraestructura existente con bajo costo de integración.
- Separa decisión y operación con una regla simple y duradera.
- Centraliza el motor en Oracle con trazabilidad total desde el primer ciclo.
- Habilita una consola operativa moderna en .NET integrable al App Shell.
- Deja el camino preparado para activación automática y evolución futura sin rediseño.
- Es apta para socialización con IT, Arquitectura, Desarrollo, Infraestructura y áreas dueñas del proceso.

**Stack recomendado:** `Landing → Integration → Serving + Control & Config` en UNOREP | motor en PL/SQL encapsulado en paquetes | API .NET ligera | micro frontend integrable al App Shell | BD transaccional separada para operación humana | ETL Python solo como adaptador de integración.
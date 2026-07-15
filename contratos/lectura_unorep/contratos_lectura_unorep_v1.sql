/* =============================================================================
   CONTRATOS DE LECTURA – report_work@UNOREP
   Dashboard / API – Consola de Gestión Modelo de Retención
   Versión 1.0 | Mayo 2026
   =============================================================================

   PROPÓSITO
   ---------
   Define el conjunto completo de vistas Oracle que la API .NET del módulo
   de Retención consume desde report_work@UNOREP. Ningún componente del
   Dashboard (frontend ni API) accede directamente a tablas internas del
   motor. Todo acceso ocurre exclusivamente a través de las vistas de
   Serving definidas en este contrato.

   CONTEXTO DE ACCESO
   ------------------
   Plano origen     : report_work@UNOREP (Oracle 11g — Analítico-Decisional)
   Consumidor       : API .NET – Módulo de Retención
   Usuario técnico  : rw_api_ro (solo lectura sobre vistas de Serving)
  Plano transacc.  : APP_USER@UNOAPP — complementado por contrato separado
               para read models operativos. Las escrituras operativas
               (bitácora, marcados, auditoría de exportaciones) y la
               resolución de contacto vigente quedan fuera de este documento.

   ESTRUCTURA DEL DOCUMENTO
   ------------------------
   SECCIÓN A  Vistas existentes — inventario y evaluación de gaps
   SECCIÓN B  Nuevas vistas de Serving (contratos nuevos)
     B.01  vw_ret_list_operativa          Lista operativa del ciclo vigente
     B.02  vw_ret_risk_indeterminate      Riesgo indeterminado
     B.03  vw_ret_out_of_universe         Fuera de universo
     B.04  vw_ret_advertiser_signals      Perfil de señales del advertiser
     B.05  vw_ret_advertiser_products     Productos por corrida (drill-down)
     B.06  vw_ret_advertiser_rules        Trazabilidad de reglas (drill-down)
     B.07  vw_ret_cycle_run_history       Historial de ciclos y corridas
     B.08  vw_ret_param_versions          Versiones de parámetros
     B.09  vw_ret_param_values            Valores de parámetros por versión
     B.10  vw_ret_param_lists             Listas de parámetros por versión
     B.11  vw_ret_product_scores          Scores de producto por versión
     B.12  vw_ret_quality_events          Eventos de calidad de datos
     B.13  vw_ret_quality_samples         Muestras de eventos de calidad
     B.14  vw_ret_export_published        Exportación desde corrida publicada
     B.15  vw_ret_label_catalog           Catálogo de etiquetas (decode de segmentos)
   SECCIÓN C  Índices de soporte adicionales
   SECCIÓN D  Grants al usuario técnico
   SECCIÓN E  Mapa de contratos por endpoint de la API

   NOTAS GENERALES
   ---------------
   1. Todas las vistas nuevas viven bajo el esquema report_work.
   2. Convención de nombrado: vw_ret_<propósito>.
   3. Las vistas de resultado (B.01–B.03) siempre filtran is_published = 1
      para garantizar que el Dashboard solo expone la versión oficial del ciclo.
   4. Las vistas de drill-down (B.05, B.06) NO filtran por is_published para
      soportar también la consulta de corridas históricas (re-cálculo).
      La API provee el run_result_id correcto según el contexto de navegación.
   5. Compatibilidad: Oracle 11g. No se usan funciones de versiones superiores.
      Los índices parciales (filtered indexes) no están disponibles en 11g;
      se usan índices compuestos estándar como alternativa.
   6. rw_case_agg_cycle: existe en el modelo físico (DDL confirmado) pero
      no aparece en DATA_DICTIONARY_tables_v1.txt. Se utiliza en B.04.
      Requiere ser incorporada al diccionario en la próxima revisión.
   ============================================================================= */


/* =============================================================================
   SECCIÓN A – VISTAS EXISTENTES: INVENTARIO Y EVALUACIÓN DE GAPS
   =============================================================================
   Las siguientes tres vistas ya existen en report_work@UNOREP.
   No se recrean aquí. Se documentan para establecer cómo las consume la API
   y registrar los gaps identificados.

   ┌─────────────────────────────────────┬──────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────┐
   │ Vista existente                     │ Uso en API                               │ Evaluación / Gap                                                        │
   ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
   │ vw_retention_current_result         │ Base general del resultado por advertiser │ OK. Filtra is_published=1. Expone todos los advertisers del universo    │
   │                                     │ (publicado). La API aplica filtros de     │ (elegibles, inelegibles e indeterminados). La segmentación fina se      │
   │                                     │ segmentación adicionales según endpoint.  │ delega a las vistas nuevas B.01–B.03. Esta vista queda como base de     │
   │                                     │                                           │ referencia y puede usarse para consultas ad-hoc internas.               │
   ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
   │ vw_retention_current_summary        │ Vista ejecutiva / KPIs del ciclo vigente. │ OK. Filtra is_published=1. Lista para consumo directo por el endpoint   │
   │                                     │ Endpoint GET /api/retention/summary.      │ de resumen ejecutivo. No requiere vista adicional.                      │
   ├─────────────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
   │ vw_retention_export_base            │ (REEMPLAZADA para uso de exportaciones)   │ GAP CRÍTICO: No filtra is_published=1. Consulta rw_run_result sin       │
   │                                     │ No debe usarse directamente para          │ restricción de corrida publicada. Podría retornar resultados de         │
   │                                     │ exportaciones del Dashboard.              │ corridas no publicadas si el caller no provee run_id explícito.         │
   │                                     │                                           │ RESOLUCIÓN: Usar vw_ret_export_published (B.14) en su lugar.           │
   │                                     │                                           │ vw_retention_export_base se conserva para compatibilidad interna.       │
   └─────────────────────────────────────┴──────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────┘
   ============================================================================= */


/* =============================================================================
   SECCIÓN B – NUEVAS VISTAS DE SERVING (CONTRATOS NUEVOS)
   ============================================================================= */


/* -----------------------------------------------------------------------------
   B.01  LISTA OPERATIVA DEL CICLO VIGENTE
   -----------------------------------------------------------------------------
   Propósito    : Fuente principal del tablero operativo para Analista de
                  Retención y PO. Expone únicamente los advertisers elegibles
                  del universo con resultado concluyente (no indeterminado)
                  de la corrida publicada del ciclo vigente.
                  Los clientes indeterminados y fuera de universo tienen sus
                  propias vistas (B.02 y B.03).

   Endpoint API : GET /api/retention/advertisers
   Filtros API  : label_code, risk_level_code, action_code, has_rezago
                  (aplicados como WHERE adicional sobre esta vista)
   Paginación   : Implementada en capa API (ROWNUM / OFFSET en la query)
   Orden suger. : score_total DESC, advertiser_name ASC (configurable en API)
   Roles        : Analista de Retención, PO / Mercadotecnia

   Tablas base  : rw_run_result, rw_run, rw_cycle, rw_cat_ret_label
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_list_operativa AS
SELECT
    /* — Identificadores de corrida y ciclo — */
    rr.run_result_id,
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    /* — Identificación del advertiser — */
    rr.advertiser_id,
    rr.advertiser_name,

    /* — Resultado del motor — */
    rr.score_total,
    rr.contract_amount_total,
    rr.assigned_label_code,          -- Código interno: VP / CQ / SP / FL / TA / CS_MEDIO / CS_BAJO / RB
    lc.label_name,                   -- Nombre de negocio: "Quejas Explícitas", "Alto Valor (VIP)", etc.
    lc.label_short_desc,             -- Descripción breve del criterio de asignación
    rr.assigned_risk_level_code,     -- REVISION / ALTO / MEDIO / BAJO
    rr.assigned_action_code,         -- MANUAL_VENTAS / CAC / SEND_CAMPAIGN / NO_ACTION

    /* — Razón de la clasificación (trazabilidad de primer nivel) — */
    rr.trigger_reason_code,

    /* — Señales observables — */
    rr.has_rezago,
    rr.visits_month,
    rr.sessions_month,
    rr.open_cases_count,
    rr.has_digital_campaign,

    /* — Metadatos de ciclo — */
    rr.parameter_version_id,
    r.published_at

FROM      report_work.rw_run_result   rr
JOIN      report_work.rw_run          r   ON r.run_id       = rr.run_id
JOIN      report_work.rw_cycle        c   ON c.cycle_id     = rr.cycle_id
LEFT JOIN report_work.rw_cat_ret_label lc ON lc.label_code  = rr.assigned_label_code
WHERE     r.is_published        = 1
  AND     rr.universe_eligible  = 1
  AND     rr.out_of_universe    = 0
  AND     rr.risk_indeterminate = 0;

COMMENT ON TABLE report_work.vw_ret_list_operativa IS
    'Lista operativa del ciclo vigente. Solo universe_eligible=1, out_of_universe=0, risk_indeterminate=0 de la corrida publicada. Incluye label_name y label_short_desc desde rw_cat_ret_label para presentacion directa en el Dashboard sin decode en la API. Fuente del tablero principal.';


/* -----------------------------------------------------------------------------
   B.02  RIESGO INDETERMINADO – LISTA DEL CICLO VIGENTE
   -----------------------------------------------------------------------------
   Propósito    : Expone los advertisers cuya clasificación no pudo
                  determinarse en la corrida publicada del ciclo vigente,
                  junto con la razón del bloqueo para soporte operativo.
                  Garantiza el principio de trazabilidad: toda exclusión
                  implícita por calidad de datos es explícita y auditable.

   Endpoint API : GET /api/retention/indeterminate
   Filtros API  : reason_code (opcional)
   Roles        : Analista de Retención, PO / Mercadotecnia

   Tablas base  : rw_run_result, rw_run, rw_cycle
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_risk_indeterminate AS
SELECT
    rr.run_result_id,
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    rr.advertiser_id,
    rr.advertiser_name,

    /* — Razón de indeterminación — */
    rr.risk_indeterminate_reason_code,
    rr.trigger_reason_code,
    rr.trigger_reason_detail,

    /* — Contexto comercial básico — */
    rr.score_total,
    rr.contract_amount_total,

    /* — Banderas de universo — */
    rr.universe_eligible,
    rr.out_of_universe,
    rr.out_of_universe_reason_code,

    /* — Señales disponibles pese al bloqueo — */
    rr.has_rezago,
    rr.visits_month,
    rr.open_cases_count,

    r.published_at

FROM      report_work.rw_run_result rr
JOIN      report_work.rw_run        r  ON r.run_id   = rr.run_id
JOIN      report_work.rw_cycle      c  ON c.cycle_id = rr.cycle_id
WHERE     r.is_published        = 1
  AND     rr.risk_indeterminate = 1;

COMMENT ON TABLE report_work.vw_ret_risk_indeterminate IS
    'Advertisers con riesgo indeterminado en la corrida publicada. Incluye razón de bloqueo para soporte operativo y resolución de calidad de datos. Principio: toda exclusión debe ser explícita.';


/* -----------------------------------------------------------------------------
   B.03  FUERA DE UNIVERSO – LISTA DEL CICLO VIGENTE
   -----------------------------------------------------------------------------
   Propósito    : Trazabilidad de advertisers excluidos del universo de
                  evaluación en el ciclo vigente, con razón de exclusión.
                  Garantiza que ningún cliente sea descartado silenciosamente.

   Endpoint API : GET /api/retention/out-of-universe
   Filtros API  : reason_code (opcional)
   Roles        : Analista de Retención, PO / Mercadotecnia

   Tablas base  : rw_run_result, rw_run, rw_cycle
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_out_of_universe AS
SELECT
    rr.run_result_id,
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    rr.advertiser_id,
    rr.advertiser_name,

    /* — Razón de exclusión — */
    rr.out_of_universe_reason_code,

    /* — Contexto mínimo — */
    rr.contract_amount_total,
    rr.score_total,

    r.published_at

FROM      report_work.rw_run_result rr
JOIN      report_work.rw_run        r  ON r.run_id   = rr.run_id
JOIN      report_work.rw_cycle      c  ON c.cycle_id = rr.cycle_id
WHERE     r.is_published    = 1
  AND     rr.out_of_universe = 1;

COMMENT ON TABLE report_work.vw_ret_out_of_universe IS
    'Advertisers excluidos del universo de evaluación en la corrida publicada. Trazabilidad de exclusiones explícitas por ciclo. Principio: toda exclusión debe ser visible y auditable.';


/* -----------------------------------------------------------------------------
   B.04  SEÑALES Y PERFIL DEL ADVERTISER (DRILL-DOWN)
   -----------------------------------------------------------------------------
   Propósito    : Perfil completo de señales de un advertiser específico en
                  la corrida publicada del ciclo vigente. Consolida en una
                  sola vista el resultado del motor, las señales de la capa
                  de integración y las métricas agregadas de cases. Evita
                  múltiples round-trips del frontend hacia la API para
                  poblar el panel de detalle.

   Endpoint API : GET /api/retention/advertisers/{advertiser_id}
   Filtro API   : WHERE advertiser_id = :advertiser_id (aplicado sobre la vista)
   Roles        : Analista de Retención, PO / Mercadotecnia

   Tablas base  : rw_run_result, rw_run, rw_cycle,
                  rw_int_advertiser, rw_case_agg_cycle
   Nota         : rw_case_agg_cycle existe en el modelo físico confirmado.
                  No está en DATA_DICTIONARY_tables_v1.txt — pendiente de
                  incorporar en próxima revisión del diccionario.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_advertiser_signals AS
SELECT
    /* — Identificadores de corrida y ciclo — */
    rr.run_result_id,
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    /* — Identificación — */
    rr.advertiser_id,
    rr.advertiser_name,

    /* — Resultado del motor — */
    rr.score_total,
    rr.contract_amount_total,
    rr.assigned_label_code,
    rr.assigned_risk_level_code,
    rr.assigned_action_code,
    rr.trigger_reason_code,
    rr.trigger_reason_detail,

    /* — Trazabilidad del ciclo — */
    rr.parameter_version_id,
    r.published_at,

    /* — Señales comerciales (del resultado) — */
    rr.has_rezago,
    rr.has_digital_campaign,
    rr.universe_eligible,
    rr.out_of_universe,
    rr.out_of_universe_reason_code,
    rr.risk_indeterminate,
    rr.risk_indeterminate_reason_code,

    /* — Señales de interacción digital — */
    rr.visits_month,
    rr.sessions_month,

    /* — Señales de atención (nivel resultado) — */
    rr.open_cases_count,

    /* — Señales de atención detalladas (capa Integration) — */
    ia.flg_meets_cq,                  -- 1 = cumple condición de Queja (CQ)
    ia.flg_meets_ta,                  -- 1 = cumple condición de Atención Abierta (TA)
    ia.flg_meets_cs,                  -- 1 = cumple condición de Silencio (CS)
    ia.total_products_relevant,
    ia.total_cases_window_120d,
    ia.flg_data_incomplete,

    /* — Métricas agregadas de cases (rw_case_agg_cycle) — */
    cac.cq_case_count,                -- Total cases CQ-relevantes en el mes
    cac.cq_same_subtype_max_count,    -- Máximo cases del mismo subtipo CQ
    cac.cq_distinct_subtype_count,    -- Subtipos CQ distintos activados
    cac.ta_case_count,                -- Total cases TA-relevantes
    cac.cs_case_90d_count             -- Cases en silencio últimos 90 días

FROM      report_work.rw_run_result rr
JOIN      report_work.rw_run             r   ON r.run_id         = rr.run_id
JOIN      report_work.rw_cycle           c   ON c.cycle_id        = rr.cycle_id
LEFT JOIN report_work.rw_int_advertiser  ia  ON ia.cycle_id      = rr.cycle_id
                                            AND ia.advertiser_id  = rr.advertiser_id
LEFT JOIN report_work.rw_case_agg_cycle  cac ON cac.cycle_id     = rr.cycle_id
                                            AND cac.advertiser_id = rr.advertiser_id
WHERE     r.is_published = 1;

COMMENT ON TABLE report_work.vw_ret_advertiser_signals IS
    'Perfil completo de señales por advertiser en la corrida publicada del ciclo vigente. Consolida resultado del motor, señales de integración y métricas de cases. Fuente del panel de detalle del Dashboard. La API filtra por advertiser_id.';


/* -----------------------------------------------------------------------------
   B.05  PRODUCTOS POR CORRIDA (DRILL-DOWN)
   -----------------------------------------------------------------------------
   Propósito    : Detalle de los productos que contribuyeron al score del
                  advertiser en una corrida específica. Permite al Analista
                  entender la composición del score por producto.

   Endpoint API : GET /api/retention/advertisers/{advertiser_id}/products
   Filtro API   : WHERE run_result_id = :run_result_id
                  (el run_result_id se obtiene previamente del endpoint B.04)
   Roles        : Analista de Retención, PO / Mercadotecnia

   Nota         : Esta vista NO filtra por is_published para soportar también
                  la consulta de corridas históricas en el flujo de re-cálculo.
                  La API provee siempre un run_result_id explícito.

   Tablas base  : rw_run_result_product, rw_run_result
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_advertiser_products AS
SELECT
    rrp.run_result_product_id,
    rrp.run_result_id,

    /* — Contexto de la corrida (para joins en API si se requiere) — */
    rr.run_id,
    rr.cycle_id,
    rr.advertiser_id,

    /* — Datos del producto — */
    rrp.bc_product_id,
    rrp.business_id,
    rrp.product_code,
    rrp.product_name,
    rrp.product_status,
    rrp.contract_amount,

    /* — Contribución al score — */
    rrp.score_assigned,
    rrp.score_source,
    rrp.included_in_score            -- 1 = incluido, 0 = excluido del cómputo

FROM      report_work.rw_run_result_product rrp
JOIN      report_work.rw_run_result         rr  ON rr.run_result_id = rrp.run_result_id;

COMMENT ON TABLE report_work.vw_ret_advertiser_products IS
    'Detalle de productos considerados en el score por advertiser y corrida. No filtra por is_published para soportar corridas publicadas e históricas. La API filtra por run_result_id.';


/* -----------------------------------------------------------------------------
   B.06  TRAZABILIDAD DE REGLAS POR ADVERTISER (DRILL-DOWN)
   -----------------------------------------------------------------------------
   Propósito    : Evidencia de la evaluación de reglas del motor por advertiser
                  en una corrida. Permite al Analista verificar exactamente
                  qué condición disparó la etiqueta asignada y qué reglas
                  no aplicaron (NO_MATCH / SKIPPED).

   Endpoint API : GET /api/retention/advertisers/{advertiser_id}/rules
   Filtro API   : WHERE run_result_id = :run_result_id
   Roles        : Analista de Retención, PO / Mercadotecnia, Sistemas

   Nota         : Esta vista NO filtra por is_published para soportar también
                  corridas históricas. La API provee el run_result_id correcto.
                  El orden de evaluación está dado por evaluation_order ASC.

   Tablas base  : rw_run_result_rule, rw_run_result
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_advertiser_rules AS
SELECT
    rrr.run_result_rule_id,
    rrr.run_result_id,

    /* — Contexto de la corrida — */
    rr.run_id,
    rr.cycle_id,
    rr.advertiser_id,

    /* — Identificación de la regla — */
    rrr.rule_group_code,             -- SCORE / VP / CQ / SP / FL / TA / CS / RB / QUALITY
    rrr.rule_code,
    rrr.evaluation_order,

    /* — Resultado de la evaluación — */
    rrr.rule_result,                 -- MATCH / NO_MATCH / SKIPPED / ERROR

    /* — Valores utilizados en la evaluación — */
    rrr.rule_value_num,
    rrr.rule_value_date,
    rrr.rule_value_text,
    rrr.rule_detail

FROM      report_work.rw_run_result_rule rrr
JOIN      report_work.rw_run_result      rr  ON rr.run_result_id = rrr.run_result_id;

COMMENT ON TABLE report_work.vw_ret_advertiser_rules IS
    'Traza de evaluación de reglas por advertiser y corrida. Permite entender qué condición disparó la etiqueta asignada. Soporta corridas publicadas e históricas. La API filtra por run_result_id y puede ordenar por evaluation_order ASC.';


/* -----------------------------------------------------------------------------
   B.07  HISTORIAL DE CICLOS Y CORRIDAS
   -----------------------------------------------------------------------------
   Propósito    : Lista de ciclos y todas sus corridas (publicadas e históricas)
                  para el selector de ciclo del Dashboard, la pantalla de
                  re-cálculo, y la auditoría histórica.

   Endpoint API : GET /api/retention/cycles
   Filtros API  : is_published (true = solo versión oficial del ciclo),
                  cycle_year, cycle_month
   Roles        : Analista de Retención, PO / Mercadotecnia, Sistemas

   Nota         : La vista hace LEFT JOIN para mostrar ciclos sin corridas
                  (ej: ciclo abierto que aún no ha sido calculado).
                  Si se omite el filtro is_published, devuelve todas las
                  corridas del ciclo (útil para comparar corridas en re-cálculo).

   Tablas base  : rw_cycle, rw_run, rw_parameter_version, rw_run_summary
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_cycle_run_history AS
SELECT
    /* — Ciclo — */
    c.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,
    c.status                    AS cycle_status,   -- OPEN / RUNNING / CLOSED / FAILED / REOPENED

    /* — Corrida — */
    r.run_id,
    r.run_status,
    r.is_published,
    r.published_at,
    r.started_at                AS run_started_at,
    r.finished_at               AS run_finished_at,

    /* — Versión de parámetros usada en la corrida — */
    r.parameter_version_id,
    pv.version_name             AS parameter_version_name,
    pv.status                   AS parameter_version_status,

    /* — Resumen de resultados de la corrida (si existe) — */
    rs.total_advertisers_processed,
    rs.total_universe_eligible,
    rs.total_out_of_universe,
    rs.total_risk_indeterminate,
    rs.total_label_vp,
    rs.total_label_cq,
    rs.total_label_sp,
    rs.total_label_fl,
    rs.total_label_ta,
    rs.total_label_cs,
    rs.total_label_rb,
    rs.total_risk_revision,
    rs.total_risk_alto,
    rs.total_risk_medio,
    rs.total_risk_bajo

FROM            report_work.rw_cycle              c
LEFT JOIN       report_work.rw_run                r   ON r.cycle_id           = c.cycle_id
LEFT JOIN       report_work.rw_parameter_version  pv  ON pv.parameter_version_id = r.parameter_version_id
LEFT JOIN       report_work.rw_run_summary        rs  ON rs.run_id            = r.run_id;

/* Nota: ORDER BY no se incluye en la definición de la vista (Oracle 11g no
   garantiza orden en la materialización). La API debe aplicar ORDER BY
   c.cycle_year DESC, c.cycle_month DESC, r.run_id DESC en la query sobre
   esta vista. */

COMMENT ON TABLE report_work.vw_ret_cycle_run_history IS
    'Historial completo de ciclos y corridas con resumen de resultados y versión de parámetros. Fuente del selector de ciclo y pantalla de re-cálculo. La API aplica ORDER BY cycle_year DESC, cycle_month DESC, run_id DESC.';


/* -----------------------------------------------------------------------------
   B.08  VERSIONES DE PARÁMETROS (PANEL DE PARAMETRIZACIÓN)
   -----------------------------------------------------------------------------
   Propósito    : Lista de todas las versiones de parámetros del modelo para
                  el panel de administración. Permite al PO ver qué versión
                  está vigente, cuál está programada para el próximo ciclo,
                  y consultar el historial de versiones anteriores.

   Endpoint API : GET /api/retention/parameters/versions
   Filtros API  : status (VIGENTE, PROGRAMADA, HISTORICA)
   Roles        : PO / Mercadotecnia (VIGENTE + PROGRAMADA),
                  Analista de Retención (solo lectura), Sistemas (HISTORICA)

   Tablas base  : rw_parameter_version, rw_cycle
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_param_versions AS
SELECT
    pv.parameter_version_id,
    pv.version_name,
    pv.status,                        -- VIGENTE / PROGRAMADA / HISTORICA

    /* — Ciclo de entrada en vigencia — */
    pv.effective_from_cycle_id,
    c.cycle_year      AS effective_from_year,
    c.cycle_month     AS effective_from_month,
    c.cycle_date      AS effective_from_date,

    pv.created_at,
    pv.created_by

FROM      report_work.rw_parameter_version pv
LEFT JOIN report_work.rw_cycle             c   ON c.cycle_id = pv.effective_from_cycle_id;

COMMENT ON TABLE report_work.vw_ret_param_versions IS
    'Versiones de parámetros del modelo con ciclo de vigencia. Fuente del panel de parametrización. La API filtra por status (VIGENTE/PROGRAMADA para el panel activo, HISTORICA para auditoría).';


/* -----------------------------------------------------------------------------
   B.09  VALORES DE PARÁMETROS POR VERSIÓN (PANEL DE PARAMETRIZACIÓN)
   -----------------------------------------------------------------------------
   Propósito    : Parámetros clave-valor simples de una versión del modelo.
                  Fuente del formulario de edición de parámetros en el panel.
                  Soporta los tres tipos de dato: NUMBER, STRING, DATE.

   Endpoint API : GET /api/retention/parameters/versions/{version_id}/values
   Filtro API   : WHERE parameter_version_id = :version_id
                  Opcionalmente filtrado por param_group para agrupar secciones
                  en el formulario del panel.
   Roles        : PO / Mercadotecnia

   Nota         : El panel del frontend unifica value_number / value_string /
                  value_date en un campo tipado según el tipo declarado en
                  param_group o por convención de naming del param_code.
                  La escritura de cambios se realiza mediante stored procedure
                  de parametrización (no a través de este contrato de lectura).

   Tablas base  : rw_parameter_value, rw_parameter_version
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_param_values AS
SELECT
    pval.parameter_value_id,
    pval.parameter_version_id,
    pv.version_name,
    pv.status        AS version_status,

    pval.param_group,
    pval.param_code,

    /* — Valor tipado (solo uno de los tres será no nulo por registro) — */
    pval.value_number,
    pval.value_string,
    pval.value_date

FROM      report_work.rw_parameter_value   pval
JOIN      report_work.rw_parameter_version pv   ON pv.parameter_version_id = pval.parameter_version_id;

COMMENT ON TABLE report_work.vw_ret_param_values IS
    'Parámetros clave-valor tipados por versión del modelo. La API filtra por parameter_version_id. Fuente del formulario de edición del panel de parametrización. Lectura solamente — escrituras vía stored procedure.';


/* -----------------------------------------------------------------------------
   B.10  LISTAS DE PARÁMETROS POR VERSIÓN (PANEL DE PARAMETRIZACIÓN)
   -----------------------------------------------------------------------------
   Propósito    : Listas de valores configurables (ej: tipos de case válidos
                  para CQ, tipos de case válidos para TA) por versión.
                  Complementa B.09. Cada param_code puede tener N valores.

   Endpoint API : GET /api/retention/parameters/versions/{version_id}/lists
   Filtro API   : WHERE parameter_version_id = :version_id
                  Opcionalmente filtrado por param_code para cargar la lista
                  específica que se está editando.
   Roles        : PO / Mercadotecnia

   Nota         : El panel agrupa por param_code para presentar cada lista
                  en su propio editor (chips / multi-select). La escritura
                  se realiza mediante stored procedure de parametrización.

   Tablas base  : rw_parameter_list, rw_parameter_version
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_param_lists AS
SELECT
    pl.parameter_list_id,
    pl.parameter_version_id,
    pv.version_name,
    pv.status     AS version_status,
    pl.param_code,
    pl.param_value

FROM      report_work.rw_parameter_list    pl
JOIN      report_work.rw_parameter_version pv  ON pv.parameter_version_id = pl.parameter_version_id;

COMMENT ON TABLE report_work.vw_ret_param_lists IS
    'Listas de valores configurables por versión del modelo. La API filtra por parameter_version_id y opcionalmente por param_code. Fuente del editor de listas del panel de parametrización.';


/* -----------------------------------------------------------------------------
   B.11  SCORES DE PRODUCTO POR VERSIÓN (PANEL DE PARAMETRIZACIÓN)
   -----------------------------------------------------------------------------
   Propósito    : Catálogo de scores asignados por código de producto para
                  la versión de parámetros activa (VIGENTE) o programada.
                  Visible y editable desde el panel de parametrización.

   Endpoint API : GET /api/retention/parameters/versions/{version_id}/product-scores
   Filtro API   : WHERE parameter_version_id = :version_id
   Roles        : PO / Mercadotecnia

   Nota         : Cada versión tiene una copia completa e independiente del
                  catálogo de scores. No se referencian catálogos externos
                  para garantizar la reproducibilidad total del cálculo.
                  La escritura se realiza mediante stored procedure.

   Tablas base  : rw_product_score, rw_parameter_version
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_product_scores AS
SELECT
    ps.product_score_id,
    ps.parameter_version_id,
    pv.version_name,
    pv.status       AS version_status,
    ps.product_code,
    ps.score

FROM      report_work.rw_product_score     ps
JOIN      report_work.rw_parameter_version pv  ON pv.parameter_version_id = ps.parameter_version_id;

COMMENT ON TABLE report_work.vw_ret_product_scores IS
    'Catálogo de score por producto por versión (copia completa por versión para reproducibilidad). La API filtra por parameter_version_id. Fuente de la tabla de scores del panel de parametrización.';


/* -----------------------------------------------------------------------------
   B.12  EVENTOS DE CALIDAD DE DATOS (PANEL DE CALIDAD)
   -----------------------------------------------------------------------------
   Propósito    : Eventos de calidad detectados en el ciclo vigente para
                  visualización en el panel de calidad del Dashboard.
                  Expone severidad, estado de resolución, métricas de impacto
                  y si existen muestras de registros disponibles para debug.

   Endpoint API : GET /api/retention/quality/events
   Filtros API  : cycle_id (del ciclo publicado — obtenido de /cycles o /summary),
                  severity_code (INFO / WARN / ERROR / FATAL),
                  event_status (OPEN / IN_REVIEW / RESOLVED / ACCEPTED)
   Roles        : Analista de Retención, PO / Mercadotecnia, Sistemas

   Semántica de severidad:
     FATAL  → bloquea el cálculo total del ciclo
     ERROR  → genera risk_indeterminate en clientes afectados
     WARN   → reportado pero no bloquea el cálculo
     INFO   → informativo de monitoreo

   Tablas base  : rw_quality_event, rw_cycle, rw_quality_event_sample (EXISTS)
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_quality_events AS
SELECT
    qe.quality_event_id,
    qe.cycle_id,
    c.cycle_year,
    c.cycle_month,
    qe.source_load_id,

    qe.event_timestamp,
    qe.source_name,                   -- IAM / SAP / PINBOX / VISITS / INTEGRATION
    qe.entity_name,                   -- ADVERTISER / PRODUCT / CASE / SITE_METRIC
    qe.field_name,
    qe.rule_code,
    qe.severity_code,                 -- INFO / WARN / ERROR / FATAL
    qe.affected_record_count,
    qe.event_status,                  -- OPEN / IN_REVIEW / RESOLVED / ACCEPTED

    qe.null_rate_pct,
    qe.previous_null_rate_pct,
    qe.remarks,

    /* — Indicador de muestras disponibles para debugging —
       Evita una llamada extra a la API para saber si hay detalle disponible.
       El frontend puede habilitar el botón de "Ver muestra" condicionalmente. */
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM   report_work.rw_quality_event_sample qs
            WHERE  qs.quality_event_id = qe.quality_event_id
        ) THEN 1
        ELSE 0
    END AS has_samples

FROM      report_work.rw_quality_event qe
JOIN      report_work.rw_cycle         c   ON c.cycle_id = qe.cycle_id;

COMMENT ON TABLE report_work.vw_ret_quality_events IS
    'Eventos de calidad de datos por ciclo con indicador de muestras disponibles. La API filtra por cycle_id del ciclo publicado y opcionalmente por severity_code y event_status. Fuente del panel de calidad del Dashboard.';


/* -----------------------------------------------------------------------------
   B.13  MUESTRAS DE EVENTOS DE CALIDAD
   -----------------------------------------------------------------------------
   Propósito    : Muestra representativa de registros específicos afectados
                  por un evento de calidad, para debugging y soporte operativo.
                  Solo se consulta cuando el Analista o Sistemas necesita
                  inspeccionar qué registros puntualmente están afectados.

   Endpoint API : GET /api/retention/quality/events/{event_id}/samples
   Filtro API   : WHERE quality_event_id = :event_id
   Roles        : Analista de Retención, Sistemas

   Nota         : El event_id es suficientemente específico como filtro.
                  La vista no filtra por ciclo porque la especificidad del
                  event_id garantiza el aislamiento correcto del dato.

   Tablas base  : rw_quality_event_sample, rw_quality_event
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_quality_samples AS
SELECT
    qs.quality_event_sample_id,
    qs.quality_event_id,

    /* — Contexto del evento para evitar join adicional en la API — */
    qe.cycle_id,
    qe.source_name,
    qe.rule_code,
    qe.severity_code,

    /* — Entidad afectada (según el tipo de evento, uno o varios de estos
         campos serán no nulos) — */
    qs.advertiser_id,
    qs.business_id,
    qs.bc_product_id,
    qs.case_id,
    qs.domain_normalized,
    qs.sample_value                   -- Valor problemático observado

FROM      report_work.rw_quality_event_sample qs
JOIN      report_work.rw_quality_event        qe  ON qe.quality_event_id = qs.quality_event_id;

COMMENT ON TABLE report_work.vw_ret_quality_samples IS
    'Muestras de registros afectados por evento de calidad. La API filtra por quality_event_id. Uso en inspección de debugging desde el panel de calidad. Solo se consulta cuando has_samples=1 en vw_ret_quality_events.';


/* -----------------------------------------------------------------------------
   B.14  EXPORTACIÓN DESDE CORRIDA PUBLICADA
   -----------------------------------------------------------------------------
   Propósito    : Base confiable para exportaciones operativas del Dashboard.
                  Garantiza que el universo exportado corresponde siempre
                  a la corrida publicada del ciclo vigente.

                  REEMPLAZA vw_retention_export_base para el caso de uso de
                  exportaciones del Dashboard. vw_retention_export_base se
                  conserva para uso interno del motor.

   Endpoint API : GET /api/retention/export
   Filtros API  : assigned_label_code, assigned_risk_level_code (opcionales).
                  El ciclo ya está delimitado por is_published=1 en la vista.
   Roles        : Analista de Retención, PO / Mercadotecnia

  Nota         : Incluye señales de atención de la capa de integración
                  (flg_meets_cq, flg_meets_ta, flg_meets_cs) para exportaciones
                  completas destinadas a equipos de campaña y seguimiento.
                  La auditoría de la exportación se registra en APP_USER@UNOAPP
            (plano transaccional — contrato separado). La resolución de
            contacto vigente para preparación de audiencias con Infobip
            no sale de esta vista; se obtiene desde el read model de
            contacto resuelto en APP_USER@UNOAPP.

   Tablas base  : rw_run_result, rw_run, rw_cycle, rw_int_advertiser
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_export_published AS
SELECT
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    /* — Identificación del advertiser — */
    rr.advertiser_id,
    rr.advertiser_name,

    /* — Resultado del motor — */
    rr.assigned_label_code,
    rr.assigned_risk_level_code,
    rr.assigned_action_code,
    rr.score_total,
    rr.contract_amount_total,
    rr.trigger_reason_code,

    /* — Señales de primer nivel — */
    rr.has_rezago,
    rr.visits_month,
    rr.sessions_month,
    rr.open_cases_count,
    rr.has_digital_campaign,

    /* — Estado en el universo — */
    rr.universe_eligible,
    rr.out_of_universe,
    rr.out_of_universe_reason_code,
    rr.risk_indeterminate,
    rr.risk_indeterminate_reason_code,

    /* — Señales de atención de integración (para exportaciones completas) — */
    ia.flg_meets_cq,
    ia.flg_meets_ta,
    ia.flg_meets_cs,

    r.published_at

FROM      report_work.rw_run_result    rr
JOIN      report_work.rw_run           r   ON r.run_id       = rr.run_id
JOIN      report_work.rw_cycle         c   ON c.cycle_id     = rr.cycle_id
LEFT JOIN report_work.rw_int_advertiser ia ON ia.cycle_id    = rr.cycle_id
                                         AND ia.advertiser_id = rr.advertiser_id
WHERE     r.is_published = 1;

COMMENT ON TABLE report_work.vw_ret_export_published IS
    'Base para exportaciones operativas del Dashboard desde la corrida publicada del ciclo vigente. Corrige el gap de vw_retention_export_base (que no filtra is_published=1). Incluye señales de atención de integración para exportaciones completas a equipos de campaña.';


/* -----------------------------------------------------------------------------
   B.15  CATÁLOGO DE ETIQUETAS DE RETENCIÓN (DECODE DE SEGMENTOS)
   -----------------------------------------------------------------------------
   Propósito    : Fuente oficial del decode de assigned_label_code para el
                  Dashboard y la API. Permite al frontend y a la API resolver
                  el nombre de negocio y descripción de cada segmento sin
                  mantener una copia local del catálogo.
                  Garantiza un único punto de mantenimiento: cualquier cambio
                  en nombre, descripción u orden de un segmento se aplica aquí
                  y se propaga automáticamente a todos los consumidores.

   Endpoint API : GET /api/retention/labels
   Filtros API  : Ninguno (catálogo completo). La API puede cachear esta
                  respuesta al arranque o refrescarla por ciclo.
   Roles        : Todos los roles del Dashboard (lectura pública del catálogo)

   Tablas base  : rw_cat_ret_label
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW report_work.vw_ret_label_catalog AS
SELECT
    label_code,
    label_name,
    label_short_desc,
    display_order
FROM report_work.rw_cat_ret_label;

COMMENT ON TABLE report_work.vw_ret_label_catalog IS
    'Catálogo de etiquetas de retención. Decode oficial de assigned_label_code hacia nombre de negocio y descripción. Unico punto de mantenimiento para nomenclatura de segmentos expuesta en el Dashboard y la API.';


/* =============================================================================
   SECCIÓN C – ÍNDICES DE SOPORTE ADICIONALES
   =============================================================================
   Los índices sobre tablas base definidos en el modelo físico (DDL v2)
   ya cubren los patrones principales de acceso. Los siguientes índices
   complementan patrones de acceso específicos de la API del Dashboard
   no contemplados en el DDL original.
   ============================================================================= */

/* C.1 — Soporte a filtros compuestos de la lista operativa (B.01)
         Patrón: LIST con filtro por label + risk sobre la corrida publicada
         Uso:    GET /api/retention/advertisers?label=CQ&risk=ALTO             */
CREATE INDEX idx_run_result_label_risk
    ON report_work.rw_run_result (run_id, assigned_label_code, assigned_risk_level_code);

/* C.2 — Soporte a consulta de indeterminados por ciclo (B.02)
         Patrón: WHERE cycle_id = :id AND risk_indeterminate = 1
         Nota:   Oracle 11g no soporta filtered indexes. Se usa índice
                 compuesto estándar como alternativa funcional.               */
CREATE INDEX idx_run_result_cycle_ind
    ON report_work.rw_run_result (cycle_id, risk_indeterminate);

/* C.3 — Soporte a consulta de fuera de universo por ciclo (B.03)
         Patrón: WHERE cycle_id = :id AND out_of_universe = 1                 */
CREATE INDEX idx_run_result_cycle_oou
    ON report_work.rw_run_result (cycle_id, out_of_universe);

/* C.4 — Soporte a búsqueda de versiones de parámetros por estado (B.08)
         Patrón: WHERE status = 'VIGENTE' o WHERE status = 'PROGRAMADA'       */
CREATE INDEX idx_param_version_status
    ON report_work.rw_parameter_version (status);

/* C.5 — Soporte a consulta de calidad por ciclo + severidad (B.12)
         El índice existente (idx_quality_event_source_sev) no comienza
         por cycle_id, lo que degrada el filtro de ciclo vigente.
         Este índice complementa para el patrón principal del Dashboard.      */
CREATE INDEX idx_quality_event_cycle_sev
    ON report_work.rw_quality_event (cycle_id, severity_code, event_status);

/* C.6 — Soporte a historial de corridas por ciclo (B.07)
         Patrón: LEFT JOIN rw_run ON cycle_id + filtros de estado y publicación */
CREATE INDEX idx_run_cycle_published
    ON report_work.rw_run (cycle_id, is_published, run_status);

/* C.7 — Soporte a listas de parámetros por versión + código (B.10)
         Patrón: WHERE parameter_version_id = :id AND param_code = :code      */
CREATE INDEX idx_param_list_version_code
    ON report_work.rw_parameter_list (parameter_version_id, param_code);

/* C.8 — Soporte a scores de producto por versión (B.11)
         Patrón: WHERE parameter_version_id = :id                             */
CREATE INDEX idx_product_score_version
    ON report_work.rw_product_score (parameter_version_id);

/* C.9 — Soporte a join de señales del advertiser con case_agg (B.04)
         Patrón: JOIN rw_case_agg_cycle ON cycle_id + advertiser_id
         Nota:   La PK de rw_case_agg_cycle es (cycle_id, advertiser_id),
                 por lo que este índice existe implícitamente. Se documenta
                 aquí para referencia. No requiere creación explícita.        */
-- Ya cubierto por PK_RW_CASE_AGG_CYCLE (cycle_id, advertiser_id)


/* =============================================================================
   SECCIÓN D – GRANTS AL USUARIO TÉCNICO DE LA API
   =============================================================================
   El usuario técnico rw_api_ro recibe SELECT exclusivamente sobre las
   vistas de Serving. Sin acceso directo a tablas internas del motor.

   Para escrituras de parámetros del modelo (nuevas versiones, ajustes de
   valores), la API usará un usuario técnico separado con EXECUTE sobre
   los packages PL/SQL de parametrización (a definir cuando se construyan
   dichos packages).

   Las escrituras operativas (bitácora, marcados, auditoría de exportaciones)
   se realizan sobre APP_USER@UNOAPP — fuera del alcance de este contrato.
   ============================================================================= */

/* — Vistas existentes — */
GRANT SELECT ON report_work.vw_retention_current_result  TO rw_api_ro;
GRANT SELECT ON report_work.vw_retention_current_summary TO rw_api_ro;
/* vw_retention_export_base: no se otorga grant para exportaciones del
   Dashboard. Se usa vw_ret_export_published en su lugar. Se puede otorgar
   si se requiere acceso interno. */

/* — Nuevas vistas de Serving (contratos nuevos) — */
GRANT SELECT ON report_work.vw_ret_list_operativa        TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_risk_indeterminate    TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_out_of_universe       TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_advertiser_signals    TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_advertiser_products   TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_advertiser_rules      TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_cycle_run_history     TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_param_versions        TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_param_values          TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_param_lists           TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_product_scores        TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_quality_events        TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_quality_samples       TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_export_published      TO rw_api_ro;
GRANT SELECT ON report_work.vw_ret_label_catalog         TO rw_api_ro;


/* =============================================================================
   SECCIÓN E – MAPA DE CONTRATOS POR ENDPOINT DE LA API
   =============================================================================

   Cada fila mapea un endpoint de la API .NET al contrato de lectura que
   consume en report_work@UNOREP, los filtros que aplica la API y el rol
   mínimo requerido.

   PANEL OPERATIVO (Analista / PO)
   ─────────────────────────────────────────────────────────────────────────────
   Endpoint                                          Vista UNOREP
   GET /api/retention/advertisers                    vw_ret_list_operativa
     Filtros:  label_code, risk_level_code,
               action_code, has_rezago (opcionales)
     Paginación: ROWNUM / OFFSET en API
     Orden:    score_total DESC, advertiser_name ASC

   GET /api/retention/advertisers/{id}               vw_ret_advertiser_signals
     Filtro:   WHERE advertiser_id = :id
     Nota:     Devuelve siempre el ciclo publicado

   GET /api/retention/advertisers/{id}/products      vw_ret_advertiser_products
     Filtro:   WHERE run_result_id = :run_result_id
     Orden:    score_assigned DESC, product_code ASC

   GET /api/retention/advertisers/{id}/rules         vw_ret_advertiser_rules
     Filtro:   WHERE run_result_id = :run_result_id
     Orden:    evaluation_order ASC

   GET /api/retention/indeterminate                  vw_ret_risk_indeterminate
     Filtros:  risk_indeterminate_reason_code (opcional)
     Nota:     Ciclo vigente ya incluido en la vista

   GET /api/retention/out-of-universe                vw_ret_out_of_universe
     Filtros:  out_of_universe_reason_code (opcional)

   PANEL EJECUTIVO (Dirección)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/summary                        vw_retention_current_summary
     Nota:     Vista existente. Sin filtros adicionales.

   HISTORIAL / RE-CÁLCULO (Analista / PO / Sistemas)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/cycles                         vw_ret_cycle_run_history
     Filtros:  is_published (true = solo versión oficial),
               cycle_year, cycle_month (opcionales)
     Orden:    cycle_year DESC, cycle_month DESC, run_id DESC  ← aplicar en API

   PANEL DE PARAMETRIZACIÓN (PO / Mercadotecnia)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/parameters/versions            vw_ret_param_versions
     Filtros:  status (VIGENTE, PROGRAMADA, HISTORICA)

   GET /api/retention/parameters/versions/{id}/values     vw_ret_param_values
     Filtro:   WHERE parameter_version_id = :id
     Filtro:   param_group (opcional, para cargar secciones del formulario)

   GET /api/retention/parameters/versions/{id}/lists      vw_ret_param_lists
     Filtro:   WHERE parameter_version_id = :id
     Filtro:   param_code (opcional, para cargar lista específica)

   GET /api/retention/parameters/versions/{id}/scores     vw_ret_product_scores
     Filtro:   WHERE parameter_version_id = :id

   PANEL DE CALIDAD (Analista / Sistemas)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/quality/events                 vw_ret_quality_events
     Filtro:   WHERE cycle_id = :published_cycle_id  ← obtener de /cycles o /summary
     Filtros:  severity_code, event_status (opcionales)
     Orden:    severity_code DESC, affected_record_count DESC  ← aplicar en API

   GET /api/retention/quality/events/{id}/samples    vw_ret_quality_samples
     Filtro:   WHERE quality_event_id = :id
     Nota:     Solo disponible cuando has_samples = 1 en vw_ret_quality_events

   EXPORTACIONES (Analista / PO)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/export                         vw_ret_export_published
     Filtros:  assigned_label_code, assigned_risk_level_code (opcionales)
     Nota:     La auditoría de exportación se registra en APP_USER@UNOAPP
               (plano transaccional — contrato pendiente de definición)

   CATÁLOGO (todos los roles)
   ─────────────────────────────────────────────────────────────────────────────
   GET /api/retention/labels                         vw_ret_label_catalog
     Filtros:  Ninguno (catálogo completo)
     Nota:     Decode oficial de assigned_label_code → label_name / label_short_desc.
               La API puede cachear al arranque. Sin paginación requerida.

   NOTAS SOBRE ESCRITURAS
   ─────────────────────────────────────────────────────────────────────────────
   Las escrituras de parámetros (nuevas versiones, ajuste de valores) se
   realizan mediante packages PL/SQL en UNOREP, invocados por la API con
   un usuario técnico de escritura (distinto de rw_api_ro, a definir).

   Las escrituras operativas (bitácora de gestión manual, marcados por
   cliente, auditoría de exportaciones) se realizan sobre APP_USER@UNOAPP.
   Ese plano transaccional no existe aún y su contrato se define en un
   documento separado.

   ─────────────────────────────────────────────────────────────────────────────
   Inventario de vistas de Serving — report_work@UNOREP
   ─────────────────────────────────────────────────────────────────────────────
   #    Vista                              Tipo       Filtra published  Uso
   ───  ─────────────────────────────────  ─────────  ────────────────  ─────────────────────────────────────────────────────
   E    vw_retention_current_result        Existente  SÍ                Base general de resultado (referencia / ad-hoc)
   E    vw_retention_current_summary       Existente  SÍ                Vista ejecutiva / KPIs del ciclo
   E    vw_retention_export_base           Existente  NO (gap)          Uso interno motor. NO usar para exportaciones API.
   B01  vw_ret_list_operativa              Nueva      SÍ                Tablero principal — solo elegibles no indeterminados
   B02  vw_ret_risk_indeterminate          Nueva      SÍ                Panel de indeterminados
   B03  vw_ret_out_of_universe             Nueva      SÍ                Panel de fuera de universo
   B04  vw_ret_advertiser_signals          Nueva      SÍ                Detalle / señales del advertiser (drill-down)
   B05  vw_ret_advertiser_products         Nueva      NO (por diseño)   Productos por corrida (drill-down, incl. históricas)
   B06  vw_ret_advertiser_rules            Nueva      NO (por diseño)   Trazabilidad de reglas (drill-down, incl. históricas)
   B07  vw_ret_cycle_run_history           Nueva      Filtro en API     Historial ciclos/corridas — selector y re-cálculo
   B08  vw_ret_param_versions              Nueva      N/A               Versiones de parámetros — panel de parametrización
   B09  vw_ret_param_values                Nueva      N/A               Valores KV de parámetros — formulario
   B10  vw_ret_param_lists                 Nueva      N/A               Listas de parámetros — editor de listas
   B11  vw_ret_product_scores              Nueva      N/A               Scores de producto — tabla de scores
   B12  vw_ret_quality_events              Nueva      Filtro en API     Eventos de calidad — panel de calidad
   B13  vw_ret_quality_samples             Nueva      N/A               Muestras de eventos — debug de calidad
   B14  vw_ret_export_published            Nueva      SÍ                Exportaciones operativas del Dashboard
   B15  vw_ret_label_catalog               Nueva      N/A               Catálogo decode de segmentos (label_name)
   ============================================================================= */

/* — Fin del documento de contratos de lectura —
   report_work@UNOREP | Modelo de Retención | v1.0 | Mayo 2026         */
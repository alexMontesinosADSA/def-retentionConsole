# Documentación — Consola de Gestión · Modelo de Retención

Repositorio de documentación técnica y funcional del componente **Dashboard / API — Consola de Gestión del Modelo de Retención**.

Este componente es la capa de presentación y acceso del sistema de retención. Expone el resultado del motor analítico a través de una API .NET y un micro frontend integrable al App Shell corporativo.

---

## Contexto del componente

El motor de retención vive en `report_work@UNOREP` (Oracle 11g). Este componente **no decide ni calcula** — consume, presenta y permite operar el resultado. Su responsabilidad es:

- Exponer los resultados del ciclo a Analistas, PO y Dirección
- Permitir la administración de parámetros del modelo sin cambios de código
- Registrar la operación humana (bitácora, marcados, exportaciones)
- Actuar como barrera de acceso entre el plano analítico y el frontend

**Regla de oro del sistema:**
> `report_work@UNOREP` decide y publica. `APP_USER@UNOAPP` registra la operación humana. Este componente orquesta ambos planos.

---

## Estructura del repositorio

```
/
├── README.md                        Este archivo
│
├── arquitectura/                    Decisiones y diseño del componente
│   └── ...
│
├── contratos/                       Contratos de datos entre capas
│   ├── lectura_unorep/              Vistas que la API consume desde UNOREP
│   ├── lectura_unoapp/              Read models y contratos de lectura en APP_USER@UNOAPP
│   └── escritura_unoapp/            Modelo transaccional de APP_USER@UNOAPP
│
├── api/                             Especificación de la API .NET
│   └── ...
│
├── frontend/                        Especificación del micro frontend
│   └── ...
│
└── decisiones/                      ADRs — registro de decisiones técnicas
    └── ...
```

> La estructura se irá poblando a medida que se definen los componentes. Cada carpeta tendrá su propio README cuando tenga contenido.

---

## Estado actual

| Área | Estado |
|---|---|
| Arquitectura general del sistema |  Definida (`arq_mvp_retencion_consolidada_v1`) |
| Contratos de lectura desde UNOREP |  v1.0 definidos |
| Contrato de lectura de contacto resuelto en APP_USER@UNOAPP |  v1.0 definido |
| Modelo transaccional APP_USER@UNOAPP |  Parcialmente definido |
| Especificación API .NET |  Pendiente |
| Especificación micro frontend |  Pendiente |

---

## Documentos de referencia del sistema

Este repo documenta solo el componente Dashboard / API. Los documentos del sistema completo viven fuera de este repositorio:

- `OVERVIEW_proyecto.txt` — Propósito, alcance y capacidades funcionales del motor de retención
- `arq_mvp_retencion_consolidada_v1.docx` — Arquitectura de solución del MVP
- `modelo_fisico_datos_v2.sql` — DDL del modelo físico en `report_work@UNOREP`
- `DATA_DICTIONARY_tables_v1.txt` — Diccionario de tablas y vistas de UNOREP

---

## Convenciones

- Los archivos SQL de contratos son ejecutables en Oracle 11g sobre `report_work@UNOREP`
- Los contratos lógicos aún no aterrizados a DDL físico pueden documentarse en Markdown
- Las vistas de Serving nuevas siguen la convención `vw_ret_<propósito>`
- Los ADRs se numeran secuencialmente: `ADR-001`, `ADR-002`, ...
- Versiones de documentos: `_v1`, `_v2`, ... sobre el nombre del archivo

---

*Componente: Dashboard / API — Consola de Gestión · Modelo de Retención*
*Proyecto: Retención Proactiva MVP · Sprint 1*

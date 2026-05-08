-- 1. SECUENCIAS (ESTÁNDAR GLOBAL)
CREATE SEQUENCE report_work.seq_cycle START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_run START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_parameter_version START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_batch START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_source_load START WITH 1 INCREMENT BY 1;

--2. CICLO (CORE DEL MODELO)
CREATE TABLE report_work.rw_cycle (
    cycle_id        NUMBER PRIMARY KEY,
    cycle_year      NUMBER(4) NOT NULL,
    cycle_month     NUMBER(2) NOT NULL,
    cycle_date      DATE NOT NULL, -- ej: 2026-04-01
    status          VARCHAR2(20),  -- OPEN / CLOSED
    created_at      TIMESTAMP DEFAULT SYSTIMESTAMP
);

ALTER TABLE report_work.rw_cycle ADD CONSTRAINT chk_rw_cycle_status
CHECK (status IN ('OPEN', 'RUNNING', 'CLOSED', 'FAILED', 'REOPENED'));

CREATE UNIQUE INDEX idx_rw_cycle_ym 
ON report_work.rw_cycle (cycle_year, cycle_month);

--3. CORRIDA (RUN DEL MOTOR)
CREATE TABLE report_work.rw_run (
    run_id              NUMBER PRIMARY KEY,
    cycle_id            NUMBER NOT NULL,
    parameter_version_id NUMBER NOT NULL,

    run_status          VARCHAR2(20), -- RUNNING / COMPLETED / FAILED
    is_published        NUMBER(1) DEFAULT 0, -- 1 = publicada
    published_at        TIMESTAMP,

    started_at          TIMESTAMP,
    finished_at         TIMESTAMP,

    CONSTRAINT fk_rw_run_cycle
        FOREIGN KEY (cycle_id) REFERENCES report_work.rw_cycle(cycle_id)
);

ALTER TABLE report_work.rw_run
    ADD CONSTRAINT chk_rw_run_is_published
    CHECK (is_published IN (0,1));


ALTER TABLE report_work.rw_run ADD CONSTRAINT chk_rw_run_status
CHECK (run_status IN ('CREATED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'));


--4. PARAMETER VERSION (VERSIÓN INTEGRAL)
CREATE TABLE report_work.rw_parameter_version (
    parameter_version_id NUMBER PRIMARY KEY,
    version_name         VARCHAR2(100),
    status               VARCHAR2(20), -- VIGENTE / PROGRAMADA / HISTORICA

    effective_from_cycle_id NUMBER,
    created_at           TIMESTAMP DEFAULT SYSTIMESTAMP,
    created_by           VARCHAR2(50)
);

ALTER TABLE report_work.rw_run ADD CONSTRAINT fk_rw_run_param_ver
  FOREIGN KEY (parameter_version_id)
  REFERENCES report_work.rw_parameter_version(parameter_version_id);


--5. PARAMETROS (MODELO HÍBRIDO)
CREATE TABLE report_work.rw_parameter_value (
    parameter_value_id   NUMBER PRIMARY KEY,
    parameter_version_id NUMBER NOT NULL,

    param_code           VARCHAR2(100) NOT NULL,
    param_group          VARCHAR2(50),

    value_number         NUMBER,
    value_string         VARCHAR2(200),
    value_date           DATE,

    CONSTRAINT fk_param_value_version
        FOREIGN KEY (parameter_version_id)
        REFERENCES report_work.rw_parameter_version(parameter_version_id)
);

-- sequencia de parameter_value
create sequence SEQ_PARAMETER_VALUE minvalue 1 maxvalue 9999999999999999999999999999 start
  with 25 increment by 1 nocache;


CREATE INDEX idx_param_code_version 
ON report_work.rw_parameter_value (param_code, parameter_version_id);



--5.2 Lista de valores (ej: tipos de case)
CREATE TABLE report_work.rw_parameter_list (
    parameter_list_id    NUMBER PRIMARY KEY,
    parameter_version_id NUMBER NOT NULL,

    param_code           VARCHAR2(100),
    param_value          VARCHAR2(100),

    CONSTRAINT fk_param_list_version
        FOREIGN KEY (parameter_version_id)
        REFERENCES report_work.rw_parameter_version(parameter_version_id)
);



-- secuencia de parameter_list
create sequence SEQ_PARAMETER_LIST minvalue 1 maxvalue 9999999999999999999999999999 start
  with 38 increment by 1 nocache;

--5.3 Catálogo de score de producto (copia por versión)
CREATE TABLE report_work.rw_product_score (
    product_score_id     NUMBER PRIMARY KEY,
    parameter_version_id NUMBER NOT NULL,

    product_code         VARCHAR2(50) NOT NULL,
    score                NUMBER NOT NULL,

    CONSTRAINT fk_product_score_version
        FOREIGN KEY (parameter_version_id)
        REFERENCES report_work.rw_parameter_version(parameter_version_id)
);

-- Create sequence de rw_product_score
create sequence SEQ_PRODUCT_SCORE minvalue 1 maxvalue 9999999999999999999999999999 start
  with 1 increment by 1 nocache;

CREATE INDEX idx_product_score_code 
ON report_work.rw_product_score (product_code);


-- 6. CATÁLOGO PRODUCT STATUS
CREATE TABLE report_work.rw_cat_product_status (
    status_code     VARCHAR2(1) PRIMARY KEY,
    status_name     VARCHAR2(50),
    is_model_eligible NUMBER(1),
    priority_order  NUMBER
);

INSERT INTO report_work.rw_cat_product_status VALUES ('L','Live',1,1);
INSERT INTO report_work.rw_cat_product_status VALUES ('I','In Process',1,2);
INSERT INTO report_work.rw_cat_product_status VALUES ('D','Draft',1,3);
INSERT INTO report_work.rw_cat_product_status VALUES ('S','Suspend',1,4);

INSERT INTO report_work.rw_cat_product_status VALUES ('C','Cancel',0,NULL);
INSERT INTO report_work.rw_cat_product_status VALUES ('E','Expired',0,NULL);
INSERT INTO report_work.rw_cat_product_status VALUES ('M','Complete',0,NULL);
INSERT INTO report_work.rw_cat_product_status VALUES ('N','New',0,NULL);
INSERT INTO report_work.rw_cat_product_status VALUES ('T','Deleted',0,NULL);
INSERT INTO report_work.rw_cat_product_status VALUES ('Z','Disassociated',0,NULL);


-- 7. CONTROL DE CARGAS

-- Create table RW_BATCH
-- Create table
create table RW_BATCH
(
  batch_id        NUMBER not null,
  started_at      TIMESTAMP(6),
  finished_at     TIMESTAMP(6),
  status          VARCHAR2(20),
  parent_batch_id NUMBER,
  source_name     VARCHAR2(50),
  batch_type      VARCHAR2(20) not null
)
tablespace POOL_DATA
  pctfree 10
  pctused 40
  initrans 1
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate indexes 
create index IDX_RW_BATCH_PARENT on RW_BATCH (PARENT_BATCH_ID)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate primary, unique and foreign key constraints 
alter table RW_BATCH
  add primary key (BATCH_ID)
  using index 
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
alter table RW_BATCH
  add constraint FK_RW_BATCH_PARENT foreign key (PARENT_BATCH_ID)
  references RW_BATCH (BATCH_ID);
-- Create/Recreate check constraints 
alter table RW_BATCH
  add constraint CHK_RW_BATCH_STATUS
  check (status IN ('CREATED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED'));
alter table RW_BATCH
  add constraint CHK_RW_BATCH_TYPE
  check (batch_type IN ('MASTER','CHILD'));



-- -----------------------------------------------------------------------------
-- 2. JERARQUÍA MAESTRO/HIJO EN rw_batch
--    Agrega parent_batch_id como auto-referencia opcional.
--    Convención: batch maestro → parent_batch_id = NULL
--                batch hijo    → parent_batch_id = batch_id del maestro
-- -----------------------------------------------------------------------------
ALTER TABLE report_work.rw_batch
    ADD parent_batch_id NUMBER NULL;

ALTER TABLE report_work.rw_batch
    ADD CONSTRAINT fk_rw_batch_parent
    FOREIGN KEY (parent_batch_id)
    REFERENCES report_work.rw_batch(batch_id);

-- Índice para navegación maestro → hijos y búsqueda por batch maestro
CREATE INDEX idx_rw_batch_parent
    ON report_work.rw_batch (parent_batch_id);

    


ALTER TABLE report_work.rw_batch ADD CONSTRAINT chk_rw_batch_status
CHECK (status IN ('CREATED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED'));

--Carga por fuente
CREATE TABLE report_work.rw_source_load (
    source_load_id NUMBER PRIMARY KEY,
    batch_id       NUMBER,

    source_name    VARCHAR2(50), -- IAM / SAP / PINBOX / VISITS
    load_date      DATE,
    started_at     TIMESTAMP,
    finished_at    TIMESTAMP,

    status         VARCHAR2(20),

    CONSTRAINT fk_source_batch
        FOREIGN KEY (batch_id) REFERENCES report_work.rw_batch(batch_id)
);


-- 1. LANDING DE VISITAS DESDE SQL SERVER
--1.1 Landing cruda de visitas
CREATE SEQUENCE report_work.seq_lnd_site_metric START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_domain_candidate START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_domain_resolution START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_advertiser START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_product START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_case START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_int_site_metric START WITH 1 INCREMENT BY 1;

CREATE TABLE report_work.rw_lnd_site_metric (
    lnd_site_metric_id         NUMBER PRIMARY KEY,
    source_load_id             NUMBER NOT NULL,

    metric_month               DATE NOT NULL,
    advertiser_business_raw    VARCHAR2(100) NOT NULL,   -- advertiser_id-business_id
    advertiser_id_parsed       NUMBER(10),
    business_id_parsed         NUMBER(12),

    domain_raw                 VARCHAR2(500),
    domain_normalized          VARCHAR2(500),

    sessions_count             NUMBER,
    visits_count               NUMBER,
    clicks_count               NUMBER,
    events_count               NUMBER,

    parse_status               VARCHAR2(20),             -- OK / ERROR
    parse_error_detail         VARCHAR2(500),

    CONSTRAINT fk_lnd_site_metric_load
        FOREIGN KEY (source_load_id)
        REFERENCES report_work.rw_source_load(source_load_id)
);


--Índices landing visitas
CREATE INDEX idx_lnd_site_metric_load
    ON report_work.rw_lnd_site_metric (source_load_id);

CREATE INDEX idx_lnd_site_metric_month_adv
    ON report_work.rw_lnd_site_metric (metric_month, advertiser_id_parsed);

CREATE INDEX idx_lnd_site_metric_month_dom
    ON report_work.rw_lnd_site_metric (metric_month, domain_normalized);

-- 2. INTEGRATION – CABECERA POR ADVERTISER Y CICLO
    CREATE TABLE report_work.rw_int_advertiser (
    int_advertiser_id              NUMBER PRIMARY KEY,
    cycle_id                       NUMBER NOT NULL,

    advertiser_id                  NUMBER(10) NOT NULL,
    advertiser_name                VARCHAR2(150),

    last_contract_date             DATE,
    has_rezago                     NUMBER(1) DEFAULT 0,

    total_contract_amount          NUMBER(18,2),
    total_visits_month             NUMBER,
    total_sessions_month           NUMBER,
    total_products_relevant        NUMBER,
    total_cases_window_120d        NUMBER,

    flg_universe_eligible          NUMBER(1) DEFAULT 0,
    flg_out_of_universe            NUMBER(1) DEFAULT 0,
    out_of_universe_reason_code    VARCHAR2(50),

    flg_data_incomplete            NUMBER(1) DEFAULT 0,
    flg_risk_indeterminate         NUMBER(1) DEFAULT 0,
    risk_indeterminate_reason_code VARCHAR2(50),

    metrics_excluded_by_domain_exc NUMBER DEFAULT 0,

    CONSTRAINT fk_int_advertiser_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT uq_int_advertiser_cycle_adv
        UNIQUE (cycle_id, advertiser_id)
);


ALTER TABLE report_work.rw_int_advertiser ADD (
    flg_meets_cq NUMBER(1) DEFAULT 0 NOT NULL,
    flg_meets_ta NUMBER(1) DEFAULT 0 NOT NULL,
    flg_meets_cs NUMBER(1) DEFAULT 0 NOT NULL
);


ALTER TABLE report_work.rw_int_advertiser ADD CONSTRAINT chk_int_adv_meets_cq
CHECK (flg_meets_cq IN (0,1));

ALTER TABLE report_work.rw_int_advertiser ADD CONSTRAINT chk_int_adv_meets_ta
CHECK (flg_meets_ta IN (0,1));

ALTER TABLE report_work.rw_int_advertiser ADD CONSTRAINT chk_int_adv_meets_cs
CHECK (flg_meets_cs IN (0,1));

    
    
--Índices cabecera integration
CREATE INDEX idx_int_advertiser_cycle
    ON report_work.rw_int_advertiser (cycle_id);

CREATE INDEX idx_int_advertiser_cycle_flags
    ON report_work.rw_int_advertiser (
        cycle_id,
        flg_universe_eligible,
        flg_risk_indeterminate
    );
    
--3. INTEGRATION – PRODUCTOS RELEVANTES POR CICLO
    CREATE TABLE report_work.rw_int_product (
    int_product_id                 NUMBER PRIMARY KEY,
    cycle_id                       NUMBER NOT NULL,

    advertiser_id                  NUMBER(10) NOT NULL,
    business_id                    NUMBER(12),
    business_name                  VARCHAR2(200),

    bc_product_id                  NUMBER(9) NOT NULL,
    product_code                   VARCHAR2(50) NOT NULL,
    product_name                   VARCHAR2(200),

    product_status                 VARCHAR2(1) NOT NULL,
    contract_amount                NUMBER(18,2),
    has_amount                     NUMBER(1) DEFAULT 0,

    domain_raw                     VARCHAR2(500),
    domain_normalized              VARCHAR2(500),

    contract_date                  DATE,
    campaign_code                  VARCHAR2(50),
    campaign_name                  VARCHAR2(200),
    category_name                  VARCHAR2(200),
    offer_code                     VARCHAR2(50),

    is_digital_campaign            NUMBER(1) DEFAULT 0,
    is_site_product                NUMBER(1) DEFAULT 0,

    CONSTRAINT fk_int_product_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT fk_int_product_status
        FOREIGN KEY (product_status)
        REFERENCES report_work.rw_cat_product_status(status_code),

    CONSTRAINT uq_int_product_cycle_bcprod
        UNIQUE (cycle_id, bc_product_id)
);

--Índices productos
CREATE INDEX idx_int_product_cycle_adv
    ON report_work.rw_int_product (cycle_id, advertiser_id);

CREATE INDEX idx_int_product_cycle_business
    ON report_work.rw_int_product (cycle_id, business_id);

CREATE INDEX idx_int_product_cycle_domain
    ON report_work.rw_int_product (cycle_id, domain_normalized);

CREATE INDEX idx_int_product_cycle_status
    ON report_work.rw_int_product (cycle_id, product_status);
    
    
    
-- 4. INTEGRATION – CANDIDATOS DE DOMINIO OBSERVADOS DESDE IAM
   CREATE TABLE report_work.rw_int_domain_candidate (
    int_domain_candidate_id        NUMBER PRIMARY KEY,
    cycle_id                       NUMBER NOT NULL,

    domain_raw                     VARCHAR2(500),
    domain_normalized              VARCHAR2(500) NOT NULL,

    advertiser_id                  NUMBER(10) NOT NULL,
    advertiser_name                VARCHAR2(150),

    business_id                    NUMBER(12),
    business_name                  VARCHAR2(200),

    bc_product_id                  NUMBER(9),
    product_status                 VARCHAR2(1) NOT NULL,
    contract_date                  DATE,
    contract_amount                NUMBER(18,2),

    status_priority                NUMBER NOT NULL,

    CONSTRAINT fk_int_domain_candidate_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT fk_int_domain_candidate_status
        FOREIGN KEY (product_status)
        REFERENCES report_work.rw_cat_product_status(status_code)
);

--Índices candidatos dominio
CREATE INDEX idx_int_dom_cand_cycle_dom
    ON report_work.rw_int_domain_candidate (cycle_id, domain_normalized);

CREATE INDEX idx_int_dom_cand_cycle_adv
    ON report_work.rw_int_domain_candidate (cycle_id, advertiser_id);
    
    
--5. INTEGRATION – RESOLUCIÓN DE DOMINIO GANADOR
    CREATE TABLE report_work.rw_int_domain_resolution (
    int_domain_resolution_id       NUMBER PRIMARY KEY,
    cycle_id                       NUMBER NOT NULL,

    domain_normalized              VARCHAR2(500) NOT NULL,
    candidate_count                NUMBER NOT NULL,

    resolution_status              VARCHAR2(20) NOT NULL,   -- RESOLVED / EXCEPTION
    resolution_rule_code           VARCHAR2(50),            -- STATUS_DATE_PRIORITY

    winner_advertiser_id           NUMBER(10),
    winner_business_id             NUMBER(12),
    winner_bc_product_id           NUMBER(9),

    exception_reason_code          VARCHAR2(50),            -- TIE_UNRESOLVED

    CONSTRAINT fk_int_domain_resolution_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT uq_int_dom_resol_cycle_dom
        UNIQUE (cycle_id, domain_normalized)
);
 
--Índices resolución dominio
CREATE INDEX idx_int_doma_resol_cycle_adv
    ON report_work.rw_int_domain_resolution (cycle_id, winner_advertiser_id);

CREATE INDEX idx_int_dom_resol_cycle_status
    ON report_work.rw_int_domain_resolution (cycle_id, resolution_status);
    
    
--    6. INTEGRATION – MÉTRICAS DE SITIO POR CICLO
CREATE TABLE report_work.rw_int_site_metric (
    int_site_metric_id             NUMBER PRIMARY KEY,
    cycle_id                       NUMBER NOT NULL,

    metric_month                   DATE NOT NULL,

    domain_raw_marketing           VARCHAR2(500),
    domain_normalized              VARCHAR2(500) NOT NULL,

    advertiser_id_source           NUMBER(10),
    business_id_source             NUMBER(12),

    advertiser_id_resolved         NUMBER(10),
    business_id_resolved           NUMBER(12),

    resolution_status              VARCHAR2(20) NOT NULL,   -- RESOLVED / EXCEPTION / UNMATCHED
    resolution_rule_code           VARCHAR2(50),
    excluded_from_calc             NUMBER(1) DEFAULT 0,

    sessions_count                 NUMBER,
    visits_count                   NUMBER,
    clicks_count                   NUMBER,
    events_count                   NUMBER,

    site_publish_date              DATE,
    site_age_days                  NUMBER,
    qualifies_min_age              NUMBER(1) DEFAULT 0,

    CONSTRAINT fk_int_site_metric_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT uq_int_site_metric_cycle_dom
        UNIQUE (cycle_id, domain_normalized)
);

--Índices métricas sitio
CREATE INDEX idx_int_site_metric_cycle_adv
    ON report_work.rw_int_site_metric (cycle_id, advertiser_id_resolved);

CREATE INDEX idx_int_site_metric_cycle_sts
    ON report_work.rw_int_site_metric (cycle_id, resolution_status, excluded_from_calc);


--7. INTEGRATION – CASES ÚTILES DEL MODELO, VENTANA 120 DÍAS
-- Create table
create table RW_INT_CASE
(
  int_case_id            NUMBER not null,
  cycle_id               NUMBER not null,
  advertiser_id          NUMBER(10) not null,
  case_id                NUMBER not null,
  case_type_code         VARCHAR2(10) not null,
  case_type_name         VARCHAR2(200),
  case_status            VARCHAR2(50) not null,
  opened_at              DATE not null,
  closed_at              DATE,
  opened_by_code         VARCHAR2(50),
  age_days               NUMBER,
  is_open                NUMBER(1) default 0,
  flg_cq_relevant        NUMBER(1) default 0,
  flg_ta_relevant        NUMBER(1) default 0,
  flg_cs_window_relevant NUMBER(1) default 0
)
tablespace POOL_DATA
  pctfree 10
  pctused 40
  initrans 1
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate indexes 
create index IDX_INT_CASE_CYCLE_ADV on RW_INT_CASE (CYCLE_ID, ADVERTISER_ID)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
create index IDX_INT_CASE_CYCLE_OPEN on RW_INT_CASE (CYCLE_ID, IS_OPEN, AGE_DAYS)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
create index IDX_INT_CASE_CYCLE_TYPE on RW_INT_CASE (CYCLE_ID, CASE_TYPE_CODE)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate primary, unique and foreign key constraints 
alter table RW_INT_CASE
  add primary key (INT_CASE_ID)
  using index 
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
alter table RW_INT_CASE
  add constraint UQ_INT_CASE_CYCLE_CASE unique (CYCLE_ID, CASE_ID)
  using index 
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
alter table RW_INT_CASE
  add constraint FK_INT_CASE_CYCLE foreign key (CYCLE_ID)
  references RW_CYCLE (CYCLE_ID);


-- Create table
create table RW_CASE_AGG_CYCLE
(
  cycle_id                  NUMBER(10) not null,
  advertiser_id             NUMBER(18) not null,
  total_cases_window_120d   NUMBER(10) default 0 not null,
  cq_case_count             NUMBER(10) default 0 not null,
  cq_same_subtype_max_count NUMBER(10) default 0 not null,
  cq_distinct_subtype_count NUMBER(10) default 0 not null,
  ta_case_count             NUMBER(10) default 0 not null,
  cs_case_90d_count         NUMBER(10) default 0 not null,
  flg_meets_cq              NUMBER(1) default 0 not null,
  flg_meets_ta              NUMBER(1) default 0 not null,
  flg_meets_cs              NUMBER(1) default 0 not null,
  created_at                TIMESTAMP(6) default SYSTIMESTAMP not null,
  updated_at                TIMESTAMP(6) default SYSTIMESTAMP not null
)
tablespace POOL_DATA
  pctfree 10
  pctused 40
  initrans 1
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Add comments to the table 
comment on table RW_CASE_AGG_CYCLE
  is 'Métricas agregadas de cases por cycle_id y advertiser_id para auditoría de señales CQ, TA y CS.';
-- Add comments to the columns 
comment on column RW_CASE_AGG_CYCLE.cycle_id
  is 'Ciclo al que pertenece el cálculo.';
comment on column RW_CASE_AGG_CYCLE.advertiser_id
  is 'Identificador del advertiser.';
comment on column RW_CASE_AGG_CYCLE.total_cases_window_120d
  is 'Total de cases válidos en ventana de 120 días.';
comment on column RW_CASE_AGG_CYCLE.cq_case_count
  is 'Total de cases con flg_cq_relevant = 1 en el mes.';
comment on column RW_CASE_AGG_CYCLE.cq_same_subtype_max_count
  is 'Máximo número de cases del mismo par case_type + case_sub_type CQ en el mes.';
comment on column RW_CASE_AGG_CYCLE.cq_distinct_subtype_count
  is 'Conteo de pares case_type + case_sub_type distintos del catálogo CQ en el mes.';
comment on column RW_CASE_AGG_CYCLE.ta_case_count
  is 'Total de cases con flg_ta_relevant = 1 en el mes.';
comment on column RW_CASE_AGG_CYCLE.cs_case_90d_count
  is 'Total de cases con flg_cs_window_relevant = 1 en los últimos 90 días.';
comment on column RW_CASE_AGG_CYCLE.flg_meets_cq
  is 'Resultado agregado de la evaluación CQ.';
comment on column RW_CASE_AGG_CYCLE.flg_meets_ta
  is 'Resultado agregado de la evaluación TA.';
comment on column RW_CASE_AGG_CYCLE.flg_meets_cs
  is 'Resultado agregado de la evaluación CS.';
-- Create/Recreate indexes 
create index IDX_RW_CASE_AGG_CYCLE_01 on RW_CASE_AGG_CYCLE (CYCLE_ID, FLG_MEETS_CQ, FLG_MEETS_TA, FLG_MEETS_CS)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
create index IDX_RW_CASE_AGG_CYCLE_02 on RW_CASE_AGG_CYCLE (ADVERTISER_ID, CYCLE_ID)
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate primary, unique and foreign key constraints 
alter table RW_CASE_AGG_CYCLE
  add constraint PK_RW_CASE_AGG_CYCLE primary key (CYCLE_ID, ADVERTISER_ID)
  using index 
  tablespace POOL_DATA
  pctfree 10
  initrans 2
  maxtrans 255
  storage
  (
    initial 40K
    next 40K
    minextents 1
    maxextents unlimited
    pctincrease 0
  );
-- Create/Recreate check constraints 
alter table RW_CASE_AGG_CYCLE
  add constraint CK_RW_CASE_AGG_CYCLE_FLG_CQ
  check (flg_meets_cq IN (0,1));
alter table RW_CASE_AGG_CYCLE
  add constraint CK_RW_CASE_AGG_CYCLE_FLG_CS
  check (flg_meets_cs IN (0,1));
alter table RW_CASE_AGG_CYCLE
  add constraint CK_RW_CASE_AGG_CYCLE_FLG_TA
  check (flg_meets_ta IN (0,1));

    
    
--    MODELO FÍSICO – PARTE 3: QUALITY + SERVING
CREATE SEQUENCE report_work.seq_quality_event START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_quality_event_sample START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_run_result START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_run_result_product START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_run_result_rule START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE report_work.seq_run_summary START WITH 1 INCREMENT BY 1;


--2. CALIDAD DE DATOS – EVENTO AGREGADO
CREATE TABLE report_work.rw_quality_event (
    quality_event_id              NUMBER PRIMARY KEY,
    cycle_id                      NUMBER NOT NULL,
    source_load_id                NUMBER,

    event_timestamp               TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    source_name                   VARCHAR2(50) NOT NULL,      -- IAM / SAP / PINBOX / VISITS / INTEGRATION
    entity_name                   VARCHAR2(50) NOT NULL,      -- ADVERTISER / PRODUCT / CASE / SITE_METRIC
    field_name                    VARCHAR2(100),
    rule_code                     VARCHAR2(100) NOT NULL,     -- ej: PRODUCT_CODE_NOT_MAPPED
    severity_code                 VARCHAR2(20) NOT NULL,      -- INFO / WARN / ERROR / FATAL

    affected_record_count         NUMBER NOT NULL,
    event_status                  VARCHAR2(20) NOT NULL,      -- OPEN / IN_REVIEW / RESOLVED / ACCEPTED

    null_rate_pct                 NUMBER(5,2),
    previous_null_rate_pct        NUMBER(5,2),

    remarks                       VARCHAR2(1000),

    CONSTRAINT fk_quality_event_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT fk_quality_event_load
        FOREIGN KEY (source_load_id)
        REFERENCES report_work.rw_source_load(source_load_id)
);




--Índices eventos calidad
CREATE INDEX idx_quality_event_cycle
    ON report_work.rw_quality_event (cycle_id);

CREATE INDEX idx_quality_event_source_sev
    ON report_work.rw_quality_event (source_name, severity_code, event_status);

CREATE INDEX idx_quality_event_rule
    ON report_work.rw_quality_event (rule_code);



--3. CALIDAD DE DATOS – MUESTRA DE REGISTROS AFECTADOS
CREATE TABLE report_work.rw_quality_event_sample (
    quality_event_sample_id       NUMBER PRIMARY KEY,
    quality_event_id              NUMBER NOT NULL,

    advertiser_id                 NUMBER(10),
    business_id                   NUMBER(12),
    bc_product_id                 NUMBER(9),
    case_id                       NUMBER,
    domain_normalized             VARCHAR2(500),

    sample_value                  VARCHAR2(1000),

    CONSTRAINT fk_quality_sample_event
        FOREIGN KEY (quality_event_id)
        REFERENCES report_work.rw_quality_event(quality_event_id)
);


--Índices muestras calidad
CREATE INDEX idx_quality_sample_event
    ON report_work.rw_quality_event_sample (quality_event_id);

CREATE INDEX idx_quality_sample_adv
    ON report_work.rw_quality_event_sample (advertiser_id);


--4. RESULTADO DEL MOTOR POR CORRIDA – CABECERA POR ADVERTISER
CREATE TABLE report_work.rw_run_result (
    run_result_id                 NUMBER PRIMARY KEY,
    run_id                        NUMBER NOT NULL,
    cycle_id                      NUMBER NOT NULL,

    advertiser_id                 NUMBER(10) NOT NULL,
    advertiser_name               VARCHAR2(150),

    score_total                   NUMBER NOT NULL,
    contract_amount_total         NUMBER(18,2),

    assigned_label_code           VARCHAR2(50) NOT NULL,      -- VP/CQ/SP/FL/TA/CS/RB/RIESGO_INDETERMINADO
    assigned_risk_level_code      VARCHAR2(20),               -- REVISION / ALTO / MEDIO / BAJO / NULL
    assigned_action_code          VARCHAR2(50),               -- MANUAL_VENTAS / CAC / SEND_CAMPAIGN / NO_ACTION

    trigger_reason_code           VARCHAR2(100) NOT NULL,     -- WHY matched
    trigger_reason_detail         VARCHAR2(1000),

    has_rezago                    NUMBER(1) DEFAULT 0,
    visits_month                  NUMBER,
    sessions_month                NUMBER,
    open_cases_count              NUMBER,
    has_digital_campaign          NUMBER(1) DEFAULT 0,

    universe_eligible             NUMBER(1) DEFAULT 0,
    out_of_universe               NUMBER(1) DEFAULT 0,
    out_of_universe_reason_code   VARCHAR2(50),

    risk_indeterminate            NUMBER(1) DEFAULT 0,
    risk_indeterminate_reason_code VARCHAR2(50),

    parameter_version_id          NUMBER NOT NULL,

    created_at                    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,

    CONSTRAINT fk_run_result_run
        FOREIGN KEY (run_id)
        REFERENCES report_work.rw_run(run_id),

    CONSTRAINT fk_run_result_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT fk_run_result_param_ver
        FOREIGN KEY (parameter_version_id)
        REFERENCES report_work.rw_parameter_version(parameter_version_id),

    CONSTRAINT uq_run_result_run_adv
        UNIQUE (run_id, advertiser_id)
);


--Índices resultado cabecera
CREATE INDEX idx_run_result_run
    ON report_work.rw_run_result (run_id);

CREATE INDEX idx_run_result_cycle
    ON report_work.rw_run_result (cycle_id);

CREATE INDEX idx_run_result_label
    ON report_work.rw_run_result (run_id, assigned_label_code);

CREATE INDEX idx_run_result_risk
    ON report_work.rw_run_result (run_id, assigned_risk_level_code);

CREATE INDEX idx_run_result_adv
    ON report_work.rw_run_result (advertiser_id);
    
--5. RESULTADO DEL MOTOR – DETALLE DE PRODUCTOS CONSIDERADOS EN SCORE
CREATE TABLE report_work.rw_run_result_product (
    run_result_product_id         NUMBER PRIMARY KEY,
    run_result_id                 NUMBER NOT NULL,

    advertiser_id                 NUMBER(10) NOT NULL,
    bc_product_id                 NUMBER(9) NOT NULL,
    business_id                   NUMBER(12),

    product_code                  VARCHAR2(50) NOT NULL,
    product_name                  VARCHAR2(200),
    product_status                VARCHAR2(1) NOT NULL,
    contract_amount               NUMBER(18,2),

    score_assigned                NUMBER NOT NULL,
    score_source                  VARCHAR2(50),               -- PRODUCT_SCORE_VERSIONED
    included_in_score             NUMBER(1) DEFAULT 1,

    CONSTRAINT fk_run_result_product_result
        FOREIGN KEY (run_result_id)
        REFERENCES report_work.rw_run_result(run_result_id),

    CONSTRAINT fk_run_result_product_status
        FOREIGN KEY (product_status)
        REFERENCES report_work.rw_cat_product_status(status_code),

    CONSTRAINT uq_run_result_prod
        UNIQUE (run_result_id, bc_product_id)
);


    --Índices detalle producto
    CREATE INDEX idx_run_result_product_result
    ON report_work.rw_run_result_product (run_result_id);

CREATE INDEX idx_run_result_product_adv
    ON report_work.rw_run_result_product (advertiser_id);

CREATE INDEX idx_run_result_product_code
    ON report_work.rw_run_result_product (product_code);
    
    
--6. RESULTADO DEL MOTOR – DETALLE DE REGLAS / EVIDENCIAS
   CREATE TABLE report_work.rw_run_result_rule (
    run_result_rule_id            NUMBER PRIMARY KEY,
    run_result_id                 NUMBER NOT NULL,

    rule_group_code               VARCHAR2(50) NOT NULL,      -- SCORE / VP / CQ / SP / FL / TA / CS / RB / QUALITY
    rule_code                     VARCHAR2(100) NOT NULL,
    evaluation_order              NUMBER,

    rule_result                   VARCHAR2(20) NOT NULL,      -- MATCH / NO_MATCH / SKIPPED / ERROR
    rule_value_num                NUMBER,
    rule_value_date               DATE,
    rule_value_text               VARCHAR2(500),

    rule_detail                   VARCHAR2(1000),

    CONSTRAINT fk_run_result_rule_result
        FOREIGN KEY (run_result_id)
        REFERENCES report_work.rw_run_result(run_result_id)
);


-- Índices detalle reglas
CREATE INDEX idx_run_result_rule_result
    ON report_work.rw_run_result_rule (run_result_id);

CREATE INDEX idx_run_result_rule_group
    ON report_work.rw_run_result_rule (rule_group_code, rule_code);
    
    
--7. RESUMEN EJECUTIVO DE CORRIDA
  CREATE TABLE report_work.rw_run_summary (
    run_summary_id                NUMBER PRIMARY KEY,
    run_id                        NUMBER NOT NULL,
    cycle_id                      NUMBER NOT NULL,

    total_advertisers_processed   NUMBER NOT NULL,
    total_universe_eligible       NUMBER NOT NULL,
    total_out_of_universe         NUMBER NOT NULL,
    total_risk_indeterminate      NUMBER NOT NULL,

    total_label_vp                NUMBER DEFAULT 0,
    total_label_cq                NUMBER DEFAULT 0,
    total_label_sp                NUMBER DEFAULT 0,
    total_label_fl                NUMBER DEFAULT 0,
    total_label_ta                NUMBER DEFAULT 0,
    total_label_cs                NUMBER DEFAULT 0,
    total_label_rb                NUMBER DEFAULT 0,

    total_risk_revision           NUMBER DEFAULT 0,
    total_risk_alto               NUMBER DEFAULT 0,
    total_risk_medio              NUMBER DEFAULT 0,
    total_risk_bajo               NUMBER DEFAULT 0,

    parameter_version_id          NUMBER NOT NULL,

    created_at                    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,

    CONSTRAINT fk_run_summary_run
        FOREIGN KEY (run_id)
        REFERENCES report_work.rw_run(run_id),

    CONSTRAINT fk_run_summary_cycle
        FOREIGN KEY (cycle_id)
        REFERENCES report_work.rw_cycle(cycle_id),

    CONSTRAINT fk_run_summary_param_ver
        FOREIGN KEY (parameter_version_id)
        REFERENCES report_work.rw_parameter_version(parameter_version_id),

    CONSTRAINT uq_run_summary_run
        UNIQUE (run_id)
);  


--8. RESTRICCIÓN DE UNA SOLA CORRIDA PUBLICADA POR CICLO
CREATE UNIQUE INDEX uq_run_one_published_per_cycle
ON report_work.rw_run (
    CASE WHEN is_published = 1 THEN cycle_id END
);

--9. VISTA DE SERVING – RESULTADO PUBLICADO DEL CICLO
CREATE OR REPLACE VIEW report_work.vw_retention_current_result AS
SELECT
    rr.run_result_id,
    rr.run_id,
    rr.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

    rr.advertiser_id,
    rr.advertiser_name,
    rr.score_total,
    rr.contract_amount_total,
    rr.assigned_label_code,
    rr.assigned_risk_level_code,
    rr.assigned_action_code,
    rr.trigger_reason_code,
    rr.trigger_reason_detail,

    rr.has_rezago,
    rr.visits_month,
    rr.sessions_month,
    rr.open_cases_count,
    rr.has_digital_campaign,

    rr.universe_eligible,
    rr.out_of_universe,
    rr.out_of_universe_reason_code,
    rr.risk_indeterminate,
    rr.risk_indeterminate_reason_code,

    rr.parameter_version_id,
    r.published_at
FROM report_work.rw_run_result rr
JOIN report_work.rw_run r
  ON r.run_id = rr.run_id
JOIN report_work.rw_cycle c
  ON c.cycle_id = rr.cycle_id
WHERE r.is_published = 1;


--10. VISTA DE SERVING – RESUMEN PUBLICADO
CREATE OR REPLACE VIEW report_work.vw_retention_current_summary AS
SELECT
    rs.run_id,
    rs.cycle_id,
    c.cycle_year,
    c.cycle_month,
    c.cycle_date,

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
    rs.total_risk_bajo,

    rs.parameter_version_id
FROM report_work.rw_run_summary rs
JOIN report_work.rw_run r
  ON r.run_id = rs.run_id
JOIN report_work.rw_cycle c
  ON c.cycle_id = rs.cycle_id
WHERE r.is_published = 1;


--11. VISTA DE EXPORTACIÓN OPERATIVA
CREATE OR REPLACE VIEW report_work.vw_retention_export_base AS
SELECT
    rr.run_id,
    rr.cycle_id,
    rr.advertiser_id,
    rr.advertiser_name,
    rr.assigned_label_code,
    rr.assigned_risk_level_code,
    rr.assigned_action_code,
    rr.score_total,
    rr.contract_amount_total,
    rr.has_rezago,
    rr.visits_month,
    rr.sessions_month,
    rr.open_cases_count,
    rr.has_digital_campaign,
    ia.out_of_universe_reason_code,
    ia.risk_indeterminate_reason_code
FROM report_work.rw_run_result rr
LEFT JOIN report_work.rw_int_advertiser ia
  ON ia.cycle_id = rr.cycle_id
 AND ia.advertiser_id = rr.advertiser_id;
 
-- 12. CONSTRAINTS CHECK RECOMENDADOS
-- Resultado cabecera
ALTER TABLE report_work.rw_run_result
    ADD CONSTRAINT chk_run_result_has_rezago
    CHECK (has_rezago IN (0,1));

ALTER TABLE report_work.rw_run_result
    ADD CONSTRAINT chk_run_result_digital
    CHECK (has_digital_campaign IN (0,1));

ALTER TABLE report_work.rw_run_result
    ADD CONSTRAINT chk_run_result_universe
    CHECK (universe_eligible IN (0,1));

ALTER TABLE report_work.rw_run_result
    ADD CONSTRAINT chk_run_result_out_universe
    CHECK (out_of_universe IN (0,1));

ALTER TABLE report_work.rw_run_result
    ADD CONSTRAINT chk_run_result_indeterminate
    CHECK (risk_indeterminate IN (0,1));
    
--Resultado producto
ALTER TABLE report_work.rw_run_result_product
    ADD CONSTRAINT chk_run_result_product_incl
    CHECK (included_in_score IN (0,1));    
    
    
    
    

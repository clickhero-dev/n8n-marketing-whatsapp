-- Migration 001 — schema inicial da campanha
-- Rodar contra o banco `campanha` (NUNCA contra o banco `n8n`).
-- A tabela `contatos` já existe e não é tocada por esta migration.

BEGIN;

-- ---------------------------------------------------------------
-- Campanha
-- ---------------------------------------------------------------
CREATE TABLE campanhas (
  id              SERIAL PRIMARY KEY,
  nome            TEXT NOT NULL,
  assunto_email   TEXT NOT NULL,
  template_wa     TEXT NOT NULL,
  modo_whitelist  BOOLEAN NOT NULL DEFAULT TRUE,   -- começa TRAVADO
  pausada         BOOLEAN NOT NULL DEFAULT FALSE,
  motivo_pausa    TEXT,
  criada_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- Higienização: resultado da validação de cada contato
-- ---------------------------------------------------------------
CREATE TABLE contatos_validacao (
  contato_user_id TEXT PRIMARY KEY,
  email_norm      TEXT,
  telefone_e164   TEXT,
  email_apto      BOOLEAN NOT NULL DEFAULT FALSE,
  whatsapp_apto   BOOLEAN NOT NULL DEFAULT FALSE,
  motivo          TEXT,
  validado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_validacao_email ON contatos_validacao (email_norm)
  WHERE email_norm IS NOT NULL;
CREATE UNIQUE INDEX ux_validacao_fone  ON contatos_validacao (telefone_e164)
  WHERE telefone_e164 IS NOT NULL;

-- ---------------------------------------------------------------
-- Fila de envios (núcleo do sistema)
-- ---------------------------------------------------------------
CREATE TABLE envios (
  id                  BIGSERIAL PRIMARY KEY,
  campanha_id         INT  NOT NULL REFERENCES campanhas(id),
  contato_user_id     TEXT NOT NULL,
  canal               TEXT NOT NULL CHECK (canal IN ('email','whatsapp')),
  destino             TEXT NOT NULL,
  status              TEXT NOT NULL DEFAULT 'pendente'
                      CHECK (status IN ('pendente','enviando','enviado','entregue',
                                        'falha','suprimido')),
  tentativas          SMALLINT NOT NULL DEFAULT 0,
  provider_message_id TEXT,
  erro_tipo           TEXT CHECK (erro_tipo IN ('permanente','temporario')),
  erro_codigo         TEXT,
  erro_mensagem       TEXT,
  agendado_para       TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at           TIMESTAMPTZ,
  enviado_em          TIMESTAMPTZ,
  entregue_em         TIMESTAMPTZ,
  aberto_em           TIMESTAMPTZ,
  criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ux_envio UNIQUE (campanha_id, contato_user_id, canal)
);
CREATE INDEX ix_envios_fila ON envios (campanha_id, canal, status, agendado_para);
CREATE UNIQUE INDEX ux_envios_provider ON envios (provider_message_id)
  WHERE provider_message_id IS NOT NULL;

-- ---------------------------------------------------------------
-- Supressão permanente (vale para TODAS as campanhas, inclusive futuras)
-- ---------------------------------------------------------------
CREATE TABLE supressao (
  id         BIGSERIAL PRIMARY KEY,
  canal      TEXT NOT NULL CHECK (canal IN ('email','whatsapp')),
  destino    TEXT NOT NULL,
  motivo     TEXT NOT NULL,   -- hard_bounce | reclamacao | descadastro | invalido | manual
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ux_supressao UNIQUE (canal, destino)
);

-- ---------------------------------------------------------------
-- Whitelist de teste (trava de segurança)
-- ---------------------------------------------------------------
CREATE TABLE whitelist (
  id       BIGSERIAL PRIMARY KEY,
  canal    TEXT NOT NULL CHECK (canal IN ('email','whatsapp')),
  destino  TEXT NOT NULL,
  CONSTRAINT ux_whitelist UNIQUE (canal, destino)
);

-- ---------------------------------------------------------------
-- Cota diária (a rampa)
-- ---------------------------------------------------------------
CREATE TABLE cota_diaria (
  campanha_id INT  NOT NULL REFERENCES campanhas(id),
  canal       TEXT NOT NULL,
  dia         DATE NOT NULL,
  limite      INT  NOT NULL,
  usado       INT  NOT NULL DEFAULT 0,
  PRIMARY KEY (campanha_id, canal, dia)
);

-- ---------------------------------------------------------------
-- Log bruto de webhooks (auditoria — nunca deletar)
-- ---------------------------------------------------------------
CREATE TABLE eventos_webhook (
  id                  BIGSERIAL PRIMARY KEY,
  canal               TEXT NOT NULL,
  tipo                TEXT,
  provider_message_id TEXT,
  payload             JSONB NOT NULL,
  recebido_em         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_eventos_msgid ON eventos_webhook (provider_message_id);

COMMIT;

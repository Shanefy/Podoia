-- ══════════════════════════════════════════════════════════
-- PODOIA — SQL COMPLETO PARA SUPABASE
-- Ejecutar en orden de arriba a abajo, una sola vez.
-- Fecha: 2026-04-16
-- ══════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 1: EXTENSIONES
-- ══════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 2: TABLAS BASE
-- ══════════════════════════════════════════════════════════

-- Clientes = podólogos que contratan PodoIA
CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone_business TEXT,               -- WhatsApp Business Phone ID
  plan TEXT DEFAULT 'basico' CHECK (plan IN ('basico','medio','premium')),
  google_calendar_id TEXT,           -- ID del calendario Google del podólogo
  timezone TEXT DEFAULT 'America/Sao_Paulo',
  email TEXT,                        -- Email del podólogo (para notificaciones)
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pacientes = personas que escriben al WhatsApp del podólogo
CREATE TABLE IF NOT EXISTS public.patients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
  name TEXT,
  phone TEXT NOT NULL,
  email TEXT,
  status TEXT DEFAULT 'nuevo' CHECK (status IN ('nuevo','lead','cliente','inactivo')),
  lead_score INT DEFAULT 0,
  source TEXT DEFAULT 'whatsapp',
  notes TEXT,
  last_interaction TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_patients_phone_client ON public.patients(phone, client_id);
CREATE INDEX IF NOT EXISTS idx_patients_status ON public.patients(status);
CREATE INDEX IF NOT EXISTS idx_patients_client ON public.patients(client_id);

-- Citas
CREATE TABLE IF NOT EXISTS public.appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES patients(id) ON DELETE SET NULL,
  client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  time TIME NOT NULL,
  treatment TEXT,
  status TEXT DEFAULT 'pendiente' CHECK (status IN ('pendiente','confirmado','completado','no_show','cancelado')),
  google_event_id TEXT,              -- ID del evento en Google Calendar
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_appointments_date_status ON public.appointments(date, status);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON public.appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_client ON public.appointments(client_id);
CREATE INDEX IF NOT EXISTS idx_appointments_google ON public.appointments(google_event_id);

-- Interacciones = historial de cada mensaje (usuario y agente)
CREATE TABLE IF NOT EXISTS public.interactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES patients(id) ON DELETE SET NULL,
  message TEXT,
  role TEXT CHECK (role IN ('user','assistant')),
  intent TEXT,                       -- agendar, consultar, precios, urgencia, etc.
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_interactions_patient ON public.interactions(patient_id);
CREATE INDEX IF NOT EXISTS idx_interactions_created ON public.interactions(created_at);

-- Tags = etiquetas automáticas por paciente
CREATE TABLE IF NOT EXISTS public.tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(patient_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_tags_patient ON public.tags(patient_id);

-- Documentos RAG = base de conocimiento vectorizada
CREATE TABLE IF NOT EXISTS public.documents (
  id BIGSERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  embedding extensions.vector(1536),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS documents_embedding_idx
ON public.documents USING hnsw (embedding vector_cosine_ops);

-- Conversaciones = tabla que usa n8n Postgres Chat Memory
-- n8n la crea automáticamente, pero la definimos para tener control
CREATE TABLE IF NOT EXISTS public.conversaciones (
  id SERIAL PRIMARY KEY,
  session_id TEXT NOT NULL,
  message JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversaciones_session ON public.conversaciones(session_id);

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 3: SISTEMA DE PLANES Y LÍMITES
-- ══════════════════════════════════════════════════════════

-- Features y límites por plan
CREATE TABLE IF NOT EXISTS public.plans_features (
  plan TEXT PRIMARY KEY CHECK (plan IN ('basico','medio','premium')),
  
  -- Features habilitadas
  voice BOOLEAN DEFAULT false,
  crm BOOLEAN DEFAULT false,
  seguimiento BOOLEAN DEFAULT false,
  no_show BOOLEAN DEFAULT false,
  reactivacion BOOLEAN DEFAULT false,
  agenda BOOLEAN DEFAULT false,
  
  -- Límites por recurso
  max_interactions_mes INT DEFAULT 500,
  max_voice_minutes_mes INT DEFAULT 0,
  max_images_mes INT DEFAULT 0,
  max_videos_mes INT DEFAULT 0,
  
  -- Umbrales de advertencia (%)
  warning_threshold INT DEFAULT 80,
  critical_threshold INT DEFAULT 95,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Configuración de cada plan
INSERT INTO public.plans_features (
  plan, voice, crm, seguimiento, no_show, reactivacion, agenda,
  max_interactions_mes, max_voice_minutes_mes, max_images_mes, max_videos_mes
) VALUES
  ('basico',   false, false, false, false, false, false,  500,    0,  20,   0),
  ('medio',    true,  true,  false, false, false, true,   2000,  30, 100,  10),
  ('premium',  true,  true,  true,  true,  true,  true,   10000, 200, 500, 50)
ON CONFLICT (plan) DO UPDATE SET
  voice = EXCLUDED.voice,
  crm = EXCLUDED.crm,
  seguimiento = EXCLUDED.seguimiento,
  no_show = EXCLUDED.no_show,
  reactivacion = EXCLUDED.reactivacion,
  agenda = EXCLUDED.agenda,
  max_interactions_mes = EXCLUDED.max_interactions_mes,
  max_voice_minutes_mes = EXCLUDED.max_voice_minutes_mes,
  max_images_mes = EXCLUDED.max_images_mes,
  max_videos_mes = EXCLUDED.max_videos_mes;

-- Uso mensual por cliente
CREATE TABLE IF NOT EXISTS public.monthly_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
  month DATE NOT NULL,
  interactions_count INT DEFAULT 0,
  voice_minutes_used DECIMAL(10,2) DEFAULT 0.0,
  images_count INT DEFAULT 0,
  videos_count INT DEFAULT 0,
  last_updated TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(client_id, month)
);

CREATE INDEX IF NOT EXISTS idx_monthly_usage_client_month ON public.monthly_usage(client_id, month);

-- Alertas de uso enviadas
CREATE TABLE IF NOT EXISTS public.usage_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
  resource_type TEXT CHECK (resource_type IN ('interactions', 'voice', 'images', 'videos')),
  alert_type TEXT CHECK (alert_type IN ('warning', 'critical', 'exceeded')),
  usage_percentage INT,
  message TEXT,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  acknowledged BOOLEAN DEFAULT false
);

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 4: FUNCIONES
-- ══════════════════════════════════════════════════════════

-- Buscar documentos RAG por similitud
CREATE OR REPLACE FUNCTION public.match_documents(
  query_embedding extensions.vector(1536),
  match_count INT DEFAULT 5,
  filter JSONB DEFAULT '{}'
) RETURNS TABLE (id BIGINT, content TEXT, metadata JSONB, similarity FLOAT)
LANGUAGE sql STABLE AS $$
  SELECT d.id, d.content, d.metadata,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM public.documents d
  WHERE d.metadata @> filter
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
$$;

-- Verificar límite ANTES de usar un recurso
CREATE OR REPLACE FUNCTION public.check_resource_limit(
  p_client_id UUID,
  p_resource_type TEXT,
  p_amount DECIMAL DEFAULT 1.0
) RETURNS JSONB AS $$
DECLARE
  v_plan TEXT;
  v_limit INT;
  v_current DECIMAL;
  v_new_total DECIMAL;
  v_percentage INT;
  v_month DATE;
BEGIN
  v_month := DATE_TRUNC('month', CURRENT_DATE);
  
  SELECT c.plan,
         CASE p_resource_type
           WHEN 'interaction' THEN pf.max_interactions_mes
           WHEN 'voice' THEN pf.max_voice_minutes_mes
           WHEN 'image' THEN pf.max_images_mes
           WHEN 'video' THEN pf.max_videos_mes
         END
  INTO v_plan, v_limit
  FROM clients c
  JOIN plans_features pf ON c.plan = pf.plan
  WHERE c.id = p_client_id;
  
  IF v_limit = 0 THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'feature_not_available',
      'message', 'Esta funcionalidad no está disponible en tu plan ' || v_plan,
      'upgrade_required', true
    );
  END IF;
  
  INSERT INTO monthly_usage (client_id, month)
  VALUES (p_client_id, v_month)
  ON CONFLICT (client_id, month) DO NOTHING;
  
  SELECT 
    CASE p_resource_type
      WHEN 'interaction' THEN interactions_count
      WHEN 'voice' THEN voice_minutes_used
      WHEN 'image' THEN images_count
      WHEN 'video' THEN videos_count
    END
  INTO v_current
  FROM monthly_usage
  WHERE client_id = p_client_id AND month = v_month;
  
  v_new_total := v_current + p_amount;
  v_percentage := ROUND((v_new_total / v_limit::DECIMAL) * 100);
  
  IF v_new_total > v_limit THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'limit_exceeded',
      'message', 'Has alcanzado el límite mensual de ' || v_limit || ' para ' || p_resource_type,
      'current', v_current,
      'limit', v_limit,
      'percentage', v_percentage,
      'upgrade_required', true
    );
  END IF;
  
  RETURN jsonb_build_object(
    'allowed', true,
    'current', v_current,
    'new_total', v_new_total,
    'limit', v_limit,
    'percentage', v_percentage,
    'remaining', v_limit - v_new_total
  );
END;
$$ LANGUAGE plpgsql;

-- Registrar uso DESPUÉS de usar un recurso
CREATE OR REPLACE FUNCTION public.record_resource_usage(
  p_client_id UUID,
  p_resource_type TEXT,
  p_amount DECIMAL DEFAULT 1.0,
  p_metadata JSONB DEFAULT '{}'
) RETURNS JSONB AS $$
DECLARE
  v_month DATE;
  v_new_total DECIMAL;
  v_limit INT;
  v_percentage INT;
  v_warning_threshold INT;
  v_critical_threshold INT;
  v_should_alert BOOLEAN := false;
  v_alert_type TEXT;
BEGIN
  v_month := DATE_TRUNC('month', CURRENT_DATE);
  
  INSERT INTO monthly_usage (client_id, month)
  VALUES (p_client_id, v_month)
  ON CONFLICT (client_id, month) DO NOTHING;
  
  UPDATE monthly_usage
  SET 
    interactions_count = CASE WHEN p_resource_type = 'interaction' 
                              THEN interactions_count + p_amount::INT ELSE interactions_count END,
    voice_minutes_used = CASE WHEN p_resource_type = 'voice' 
                              THEN voice_minutes_used + p_amount ELSE voice_minutes_used END,
    images_count = CASE WHEN p_resource_type = 'image' 
                        THEN images_count + p_amount::INT ELSE images_count END,
    videos_count = CASE WHEN p_resource_type = 'video' 
                        THEN videos_count + p_amount::INT ELSE videos_count END,
    last_updated = NOW()
  WHERE client_id = p_client_id AND month = v_month
  RETURNING 
    CASE p_resource_type
      WHEN 'interaction' THEN interactions_count
      WHEN 'voice' THEN voice_minutes_used
      WHEN 'image' THEN images_count
      WHEN 'video' THEN videos_count
    END
  INTO v_new_total;
  
  SELECT 
    CASE p_resource_type
      WHEN 'interaction' THEN pf.max_interactions_mes
      WHEN 'voice' THEN pf.max_voice_minutes_mes
      WHEN 'image' THEN pf.max_images_mes
      WHEN 'video' THEN pf.max_videos_mes
    END,
    pf.warning_threshold,
    pf.critical_threshold
  INTO v_limit, v_warning_threshold, v_critical_threshold
  FROM clients c
  JOIN plans_features pf ON c.plan = pf.plan
  WHERE c.id = p_client_id;
  
  v_percentage := ROUND((v_new_total / v_limit::DECIMAL) * 100);
  
  IF v_percentage >= v_critical_threshold THEN
    v_should_alert := true;
    v_alert_type := 'critical';
  ELSIF v_percentage >= v_warning_threshold THEN
    v_should_alert := true;
    v_alert_type := 'warning';
  END IF;
  
  IF v_should_alert THEN
    INSERT INTO usage_alerts (client_id, resource_type, alert_type, usage_percentage, message)
    SELECT 
      p_client_id, p_resource_type, v_alert_type, v_percentage,
      'Has usado ' || v_percentage || '% de tu límite mensual de ' || p_resource_type
    WHERE NOT EXISTS (
      SELECT 1 FROM usage_alerts
      WHERE client_id = p_client_id
        AND resource_type = p_resource_type
        AND alert_type = v_alert_type
        AND sent_at > DATE_TRUNC('month', CURRENT_DATE)
        AND acknowledged = false
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'new_total', v_new_total,
    'limit', v_limit,
    'percentage', v_percentage,
    'alert_triggered', v_should_alert,
    'alert_type', v_alert_type
  );
END;
$$ LANGUAGE plpgsql;

-- Obtener alertas pendientes de un cliente
CREATE OR REPLACE FUNCTION public.get_pending_alerts(
  p_client_id UUID
) RETURNS TABLE (
  id UUID, resource_type TEXT, alert_type TEXT,
  usage_percentage INT, message TEXT, sent_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT a.id, a.resource_type, a.alert_type, a.usage_percentage, a.message, a.sent_at
  FROM usage_alerts a
  WHERE a.client_id = p_client_id
    AND a.acknowledged = false
    AND a.sent_at > DATE_TRUNC('month', CURRENT_DATE)
  ORDER BY a.sent_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Limpieza mensual
CREATE OR REPLACE FUNCTION public.reset_monthly_usage()
RETURNS VOID AS $$
BEGIN
  DELETE FROM usage_alerts 
  WHERE sent_at < DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month';
END;
$$ LANGUAGE plpgsql;

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 5: VISTAS
-- ══════════════════════════════════════════════════════════

-- Dashboard de uso por cliente
CREATE OR REPLACE VIEW public.usage_dashboard AS
SELECT 
  c.id AS client_id,
  c.name AS client_name,
  c.plan,
  pf.max_interactions_mes,
  pf.max_voice_minutes_mes,
  pf.max_images_mes,
  pf.max_videos_mes,
  COALESCE(mu.interactions_count, 0) AS interactions_used,
  COALESCE(mu.voice_minutes_used, 0) AS voice_minutes_used,
  COALESCE(mu.images_count, 0) AS images_used,
  COALESCE(mu.videos_count, 0) AS videos_used,
  ROUND((COALESCE(mu.interactions_count, 0)::DECIMAL / NULLIF(pf.max_interactions_mes, 0)) * 100) AS interactions_pct,
  ROUND((COALESCE(mu.voice_minutes_used, 0) / NULLIF(pf.max_voice_minutes_mes, 0)) * 100) AS voice_pct,
  ROUND((COALESCE(mu.images_count, 0)::DECIMAL / NULLIF(pf.max_images_mes, 0)) * 100) AS images_pct,
  ROUND((COALESCE(mu.videos_count, 0)::DECIMAL / NULLIF(pf.max_videos_mes, 0)) * 100) AS videos_pct,
  mu.last_updated
FROM clients c
JOIN plans_features pf ON c.plan = pf.plan
LEFT JOIN monthly_usage mu ON c.id = mu.client_id 
  AND mu.month = DATE_TRUNC('month', CURRENT_DATE)
WHERE c.active = true;

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 6: PERMISOS
-- ══════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.match_documents(extensions.vector, INT, JSONB) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_resource_limit(UUID, TEXT, DECIMAL) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_resource_usage(UUID, TEXT, DECIMAL, JSONB) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_pending_alerts(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reset_monthly_usage() TO anon, authenticated, service_role;
GRANT SELECT ON public.usage_dashboard TO anon, authenticated, service_role;

-- ══════════════════════════════════════════════════════════
-- SECCIÓN 7: DATOS INICIALES (tu primer cliente de prueba)
-- ══════════════════════════════════════════════════════════

-- Descomenta y ajusta para tu primer cliente:
--
-- INSERT INTO public.clients (name, phone_business, plan, google_calendar_id, email)
-- VALUES (
--   'Clínica Podológica Ejemplo',
--   'TU-PHONE-NUMBER-ID',
--   'medio',
--   'primary',
--   'email-del-podologo@gmail.com'
-- );
--
-- Después copia el UUID generado y pégalo en el nodo Config Cliente del workflow.


-- ══════════════════════════════════════════════════════════
-- ADICIONES ETAPA 1 — Modularización
-- Ejecutar DESPUÉS de PODOIA_supabase_completo.sql
-- ══════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────
-- TABLA: services (catálogo de servicios por podólogo)
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.services (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id        UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  description      TEXT,
  price            DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  duration_minutes INT NOT NULL DEFAULT 45,
  is_active        BOOLEAN DEFAULT true,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_client_active
  ON public.services(client_id, is_active);

-- Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_services_updated_at ON public.services;
CREATE TRIGGER trg_services_updated_at
  BEFORE UPDATE ON public.services
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─────────────────────────────────────────────────────────
-- ALTER: appointments — agregar service_id y confirmation_token
-- ─────────────────────────────────────────────────────────
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS service_id UUID REFERENCES public.services(id),
  ADD COLUMN IF NOT EXISTS confirmation_token UUID DEFAULT gen_random_uuid();

-- Índice para buscar por token (evita race conditions en apt_lifecycle)
CREATE UNIQUE INDEX IF NOT EXISTS idx_appointments_confirmation_token
  ON public.appointments(confirmation_token);

-- ─────────────────────────────────────────────────────────
-- RLS: habilitar Row Level Security en services
-- ─────────────────────────────────────────────────────────
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

CREATE POLICY "services_client_isolation" ON public.services
  USING (client_id = current_setting('app.client_id', true)::UUID);

-- ─────────────────────────────────────────────────────────
-- DATOS DE EJEMPLO: servicios para primer cliente
-- (reemplazar CAMBIAR-UUID-CLIENTE con el UUID real)
-- ─────────────────────────────────────────────────────────
/*
INSERT INTO public.services (client_id, name, description, price, duration_minutes) VALUES
  ('CAMBIAR-UUID-CLIENTE', 'Quiropodia básica',             'Corte y limado de uñas, eliminación de callosidades',        80.00, 45),
  ('CAMBIAR-UUID-CLIENTE', 'Tratamiento uña encarnada',     'Onicocriptosis: limpieza, desinfección y corrección',        120.00, 60),
  ('CAMBIAR-UUID-CLIENTE', 'Tratamiento hongos en uñas',    'Onicomicosis: aplicación de antimicóticos especializados',   100.00, 45),
  ('CAMBIAR-UUID-CLIENTE', 'Estudio biomecánico del pie',   'Análisis de pisada y biomecánica para plantillas',           200.00, 60),
  ('CAMBIAR-UUID-CLIENTE', 'Plantillas personalizadas',     'Fabricación de plantillas ortopédicas a medida',             350.00, 30),
  ('CAMBIAR-UUID-CLIENTE', 'Consulta pie diabético',        'Revisión especializada para pacientes con diabetes',         150.00, 60),
  ('CAMBIAR-UUID-CLIENTE', 'Eliminación papilomas',         'Papilomas plantares: crioterapia o ácido salicílico',        100.00, 30),
  ('CAMBIAR-UUID-CLIENTE', 'Evaluación podológica general', 'Primera consulta: evaluación completa del pie',              100.00, 45);
*/

-- ─────────────────────────────────────────────────────────
-- CHECKLIST DE ONBOARDING (comentado — ejecutar por cliente)
-- ─────────────────────────────────────────────────────────
/*
Pasos para dar de alta un cliente nuevo:

1. INSERT en public.clients:
   INSERT INTO public.clients (name, phone_business, plan, google_calendar_id, timezone)
   VALUES ('Nombre Clínica', '+55119XXXXXXXX', 'medio', 'CALENDAR_ID@group.calendar.google.com', 'America/Sao_Paulo');

2. Copiar el UUID generado → usarlo en los siguientes pasos

3. INSERT servicios (descomentar bloque de arriba con el UUID real)

4. En n8n, nodo Config Cliente:
   - client_id   = UUID del paso 2
   - client_name = nombre de la clínica
   - plan        = basico | medio | premium
   - business_phone_id = Phone Number ID de WhatsApp Business
   - google_calendar_id = Calendar ID del paso 1
   - timezone    = America/Sao_Paulo | America/Mexico_City

5. Mismo UUID en workflows de schedule:
   PODOIA_apt_lifecycle → nodo Config → client_id
   PODOIA_gestion_noshows → nodo Config → client_id
   PODOIA_seguimiento_postconsulta → nodo Config → client_id
   PODOIA_reactivacion_pacientes → nodo Config → client_id
*/

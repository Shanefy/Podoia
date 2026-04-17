# PodoIA — Documentación de Arquitectura

**Versión:** MVP v2
**Fecha:** 2026-04-16
**Autor:** Shane Medina + Claude (Anthropic)

---

## 1. ¿Qué es PodoIA?

Sistema SaaS de automatización de atención al cliente para clínicas podológicas vía WhatsApp. Multi-tenant: una instancia de n8n atiende múltiples clínicas, diferenciando funcionalidades por plan contratado.

**Mercados objetivo:** Brasil (primero), México (segundo).
**Idiomas:** Portugués y Español.

---

## 2. Planes de servicio

| Feature | Básico ($800-1200 MXN) | Medio ($1500-3000 MXN) | Premium ($3000-6000 MXN) |
|---|---|---|---|
| WhatsApp texto + IA | ✅ | ✅ | ✅ |
| FAQ + captura datos | ✅ | ✅ | ✅ |
| Voz (Fish Audio) | ❌ | ✅ | ✅ |
| Agendamiento Google Calendar | ❌ | ✅ | ✅ |
| CRM (pacientes, estados, tags) | ❌ | ✅ | ✅ |
| Seguimiento post-consulta | ❌ | ❌ | ✅ |
| Gestión no-shows | ❌ | ❌ | ✅ |
| Reactivación pacientes | ❌ | ❌ | ✅ |
| Recordatorios 24h | ❌ | ✅ | ✅ |

La diferenciación se controla desde la tabla `plans_features` en Supabase. El workflow lee dinámicamente qué features activar. Nunca se hardcodea el plan en el código.

---

## 3. Inventario de workflows

### 3.1 PODOIA_principal_v2.json (86 nodos funcionales)

Workflow principal. Recibe mensajes de WhatsApp, los procesa y responde.

**Secciones internas:**

| Sección | Nodos | Qué hace |
|---|---|---|
| Entrada WhatsApp | 3 | Recibe mensaje, splitea, clasifica tipo (audio/video/imagen/texto) |
| Media Audio | 3 | Descarga audio → Whisper (OpenAI) transcribe a texto |
| Media Video | 4 | Descarga video → Gemini 2.5 Flash analiza → extrae texto |
| Media Imagen | 4 | Descarga imagen → Gemini 2.5 Flash analiza → extrae texto |
| Media Texto | 1 | Extrae body del mensaje de texto |
| Agregación Redis | 9 | Acumula mensajes en ráfaga (3s), deduplica, consolida |
| Validación Config | 4 | Verifica phone↔client en Supabase, lee features del plan |
| Control Límites | 3 | check_resource_limit() antes de procesar, avisa si excede |
| Idioma + Intent | 5 | Detecta PT/ES, clasifica intención en 10 categorías |
| Confirmación Citas | 6 | Detecta SIM/NO/REAGENDAR, procesa sin pasar por agente |
| CRM | 10 | Busca/crea paciente, tags, actualiza interacción |
| Agente IA | 6 | GPT-4o + memoria PostgreSQL + tools (calendario, servicios) |
| Respuesta | 6 | Texto directo o Fish Audio TTS (si audio + plan con voz) |
| Post-CRM | 8 | Máquina de estados, scoring, tags, registro de uso |
| RAG | 10 | Google Drive → extract → embeddings → Supabase vector |
| Error Handling | 3 | Error Trigger → fallback paciente + email admin |

### 3.2 PODOIA_sub_calendario.json (15 nodos)

Sub-workflow llamado por el agente como herramienta.

| Acción | Qué hace |
|---|---|
| verificar_disponibilidad | Consulta eventos de Google Calendar → calcula slots libres (8:00-18:00, 45min + 15min pausa) |
| agendar_cita | Valida datos obligatorios → crea evento real en Google Calendar → guarda en Supabase con patient_id + client_id → envía email al podólogo |
| cancelar_cita | Elimina evento de Google Calendar → actualiza status en Supabase |

### 3.3 PODOIA_recordatorio_citas.json (10 nodos)

Schedule Trigger cada hora. Busca citas confirmadas para mañana. Envía recordatorio por WhatsApp. Solo activo si plans_features.agenda = true.

### 3.4 PODOIA_gestion_noshows.json (11 nodos)

Schedule Trigger diario. Busca citas de ayer con status != completado. Actualiza status → no_show. Envía mensaje de reagendamiento. Solo activo si plans_features.no_show = true.

### 3.5 PODOIA_seguimiento_postconsulta.json (10 nodos)

Schedule Trigger diario. Busca citas completadas hace 2 días. Envía mensaje de seguimiento. Solo activo si plans_features.seguimiento = true.

### 3.6 PODOIA_reactivacion_pacientes.json (11 nodos)

Schedule Trigger semanal. Busca pacientes sin interacción hace 30+ días. Actualiza status → inactivo. Envía mensaje de reactivación. Solo activo si plans_features.reactivacion = true.

---

## 4. Modelos de IA

| Tipo de entrada | Modelo | Proveedor | Costo aprox. |
|---|---|---|---|
| Texto (agente) | GPT-4o | OpenAI | ~$0.01/mensaje |
| Audio entrada | Whisper | OpenAI | ~$0.006/min |
| Audio salida | Fish Audio TTS | Fish Audio | ~$0.01/mensaje |
| Imagen | Gemini 2.5 Flash | Google | ~$0.002/imagen |
| Video | Gemini 2.5 Flash | Google | ~$0.005/video |
| Traductor | GPT-4o-mini | OpenAI | ~$0.0001/mensaje |
| Clasificador intent | GPT-4o-mini | OpenAI | ~$0.0001/mensaje |
| Limpieza texto TTS | GPT-4o-mini | OpenAI | ~$0.0001/mensaje |

---

## 5. Base de datos (Supabase)

### 5.1 Tablas

| Tabla | Propósito | Relaciones |
|---|---|---|
| clients | Podólogos que contratan PodoIA | — |
| patients | Pacientes de cada podólogo | → clients |
| appointments | Citas agendadas | → patients, → clients |
| interactions | Historial de mensajes | → patients |
| tags | Etiquetas automáticas | → patients |
| documents | Base RAG vectorizada | — |
| conversaciones | Memoria del agente (n8n) | — |
| plans_features | Features y límites por plan | — |
| monthly_usage | Contadores de uso mensual | → clients |
| usage_alerts | Alertas de límites enviadas | → clients |

### 5.2 Funciones

| Función | Cuándo se usa |
|---|---|
| match_documents() | Agente busca servicios en RAG |
| check_resource_limit() | Antes de procesar cada mensaje |
| record_resource_usage() | Después de responder cada mensaje |
| get_pending_alerts() | Dashboard consulta alertas |
| reset_monthly_usage() | Cron mensual de limpieza |

### 5.3 Vistas

| Vista | Propósito |
|---|---|
| usage_dashboard | Datos para el dashboard del podólogo |

---

## 6. Multi-tenant

Cada podólogo es un registro en la tabla `clients` con su propio `id` (UUID). Todo el sistema filtra por `client_id`:

- Pacientes: `WHERE client_id = X`
- Citas: `WHERE client_id = X`
- Uso mensual: `WHERE client_id = X`
- Alertas: `WHERE client_id = X`

El workflow principal tiene un nodo `Config Cliente` que define qué `client_id` procesa. Para desplegar un nuevo cliente: insertar en `clients`, copiar el UUID al nodo Config, configurar credenciales de WhatsApp y Calendar.

Validación: el nodo `Validar Config` verifica que `business_phone_id` corresponda al `client_id` antes de procesar mensajes.

---

## 7. CRM: Máquina de estados

### Estados del paciente

```
nuevo → lead → cliente → inactivo
                ↑           |
                └───────────┘ (reactivado)
```

### Transiciones por intención

| Intent | Score | Transición |
|---|---|---|
| agendar | +3 | → lead |
| confirmar | +5 | → cliente |
| precios | +2 | nuevo→lead |
| urgencia | +3 | → lead + tag "urgente" |
| consultar | +1 | nuevo→lead |
| cancelar | -2 | mantiene + tag "cancelo" |
| reprogramar | 0 | mantiene |
| seguimiento | +1 | mantiene |
| saludo | 0 | mantiene |
| otro | 0 | mantiene |

### Tags automáticos

nuevo, interesado, pidio_precios, urgente, cita_agendada, cancelo, reactivado

---

## 8. Flujo de confirmación de citas

Integrado en el workflow principal (no es workflow separado).

1. Paciente recibe recordatorio: "Confirme respondendo SIM ou REAGENDAR"
2. Paciente responde "SIM"
3. Workflow detecta que es respuesta corta (SIM/NO/REAGENDAR)
4. Busca si tiene cita en próximas 48h
5. Si tiene → actualiza status directamente, responde sin usar agente (sin costo OpenAI)
6. Si no tiene cita → pasa al agente normalmente

| Respuesta | Acción |
|---|---|
| SIM / SI / OK / CONFIRMO | status → confirmado |
| NO / CANCELAR | status → cancelado |
| REAGENDAR / CAMBIAR | status → cancelado, pregunta nueva fecha |

---

## 9. Manejo de errores

El nodo `Error Trigger` captura cualquier fallo en la ejecución del workflow.

Acciones paralelas:
- Al paciente: "Disculpa, tuvimos un problema técnico. Intenta en unos minutos."
- A Shane (admin): Email con nombre del nodo que falló, mensaje de error, timestamp.

---

## 10. Credenciales necesarias

| Credencial | Tipo en n8n | Para qué |
|---|---|---|
| WhatsApp Trigger | WhatsApp Trigger API | Recibir mensajes |
| WhatsApp | WhatsApp API | Enviar mensajes + descargar media |
| OpenAI | OpenAI API | GPT-4o, GPT-4o-mini, Whisper |
| Google Gemini | Google PaLM API | Análisis imagen y video |
| Redis | Redis | Agregación de mensajes |
| Supabase API | HTTP Header Auth | API REST de Supabase |
| Supabase | Supabase API | Vector Store (RAG) |
| Postgres | PostgreSQL | Memoria del agente |
| Google Calendar | Google Calendar OAuth2 | Eventos de citas |
| Google Drive | Google Drive OAuth2 | RAG: detectar archivos nuevos |
| Fish Audio | HTTP Header Auth | Text-to-Speech |
| Gmail | Gmail OAuth2 | Notificaciones (errores, citas nuevas) |

---

## 11. Orden de importación en n8n

1. `PODOIA_sub_calendario.json` — importar primero, copiar su ID
2. `PODOIA_principal_v2.json` — pegar ID del calendario en nodo "calendario"
3. `PODOIA_recordatorio_citas.json`
4. `PODOIA_gestion_noshows.json`
5. `PODOIA_seguimiento_postconsulta.json`
6. `PODOIA_reactivacion_pacientes.json`

Antes de activar: ejecutar `PODOIA_supabase_completo.sql` en Supabase.

---

## 12. Roadmap

### MVP (abril 2026) — ✅ LISTO

WhatsApp → conversación → cita → confirmación → recordatorio.

Core funcional:
- Atención multimodal (texto, audio, video, imagen)
- Agente IA con RAG + Calendar real
- CRM con máquina de estados
- Confirmación de citas (SIM/NO/REAGENDAR)
- Tracking de límites por plan
- Error handling con fallbacks
- Notificación Gmail al podólogo
- Multi-tenant con validación

### Etapa 2 (mayo 2026) — PENDIENTE

Modularización + features de crecimiento.

| Tarea | Prioridad | Descripción |
|---|---|---|
| Modularizar workflow principal | CRÍTICA | Extraer 4 bloques en sub-workflows (media, CRM, post-CRM, confirmaciones). Principal queda en ~40 nodos como orquestador. |
| Escalamiento a humano | CRÍTICA | Bot pausa + notifica podólogo. Elegir opción A/B/C. |
| Dashboard conectado | ALTA | Conectar HTML existente a Supabase via API REST. Datos reales. |
| Notificación WhatsApp citas | MEDIA | Reemplazar Gmail por WhatsApp para avisar al podólogo. |
| Encuesta NPS | MEDIA | Post-consulta: "¿Cómo calificarías tu experiencia?" |
| Reportes semanales por email | MEDIA | Resumen automático al podólogo cada lunes. |

### Etapa 3 (junio 2026+) — Post-validación

| Tarea | Prioridad | Descripción |
|---|---|---|
| Onboarding automatizado | ALTA | Landing → formulario → crea cliente en Supabase + setup automático. |
| Plan PRO | ALTA | Campañas broadcast, embudos de conversión. |
| Integración pagos | MEDIA | Mercado Pago / Stripe. |
| Dashboard avanzado | MEDIA | ROI, métricas de conversión, tendencias. |
| A/B testing mensajes | BAJA | Probar diferentes copys de reactivación. |
| Google Sheets sync | BAJA | Para podólogos que prefieren sheets. |
| Voz personalizada | BAJA | Clonación de voz como upsell. |
| Reportes PDF automáticos | BAJA | Envío mensual con métricas detalladas. |

---

## 13. Regla de oro para etapa 2+

**No se agrega ninguna feature nueva al workflow principal hasta que no se modularice.**

Primero ordenar, después crecer.

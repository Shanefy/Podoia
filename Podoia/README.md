# 🦶 PodoIA — Asistente Virtual IA para Podología

> Automatización de atención al cliente 24/7 por WhatsApp para clínicas podológicas.  
> **Stack:** n8n · Supabase · WhatsApp Business API · OpenAI · Google Calendar

---

## ¿Qué es PodoIA?

PodoIA es un sistema SaaS multi-tenant que automatiza la atención al paciente de clínicas podológicas vía WhatsApp. Una sola instancia de n8n atiende múltiples clínicas, diferenciando funcionalidades según el plan contratado.

**Mercados objetivo:** Brasil 🇧🇷 (primero) · México 🇲🇽 (segundo)  
**Idiomas soportados:** Português · Español

---

## ✨ Funcionalidades principales

| Feature | Básico | Medio | Premium |
|---|:---:|:---:|:---:|
| Atención WhatsApp texto + IA | ✅ | ✅ | ✅ |
| FAQ + captura de datos | ✅ | ✅ | ✅ |
| Respuesta por voz (Fish Audio TTS) | ❌ | ✅ | ✅ |
| Agendamiento Google Calendar | ❌ | ✅ | ✅ |
| CRM (pacientes, estados, tags) | ❌ | ✅ | ✅ |
| Recordatorios 24h antes de la cita | ❌ | ✅ | ✅ |
| Seguimiento post-consulta | ❌ | ❌ | ✅ |
| Gestión de no-shows | ❌ | ❌ | ✅ |
| Reactivación de pacientes inactivos | ❌ | ❌ | ✅ |

---

## 🗂 Estructura del repositorio

```
podoia/
├── workflows/
│   ├── PODOIA_principal_v2.json          # Workflow principal (86 nodos)
│   ├── PODOIA_sub_calendario.json        # Sub-workflow: agendar/cancelar citas
│   ├── PODOIA_recordatorio_citas.json    # Recordatorios 24h antes
│   ├── PODOIA_gestion_noshows.json       # Gestión de no-shows
│   ├── PODOIA_seguimiento_postconsulta.json
│   └── PODOIA_reactivacion_pacientes.json
├── database/
│   └── PODOIA_supabase_completo.sql      # Schema completo de Supabase
├── frontend/
│   ├── index.html                        # Landing page
│   └── podoia_dashboard_podologo.html    # Dashboard del podólogo
├── docs/
│   └── PODOIA_arquitectura.md           # Documentación técnica completa
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🚀 Instalación y configuración

### Requisitos previos

- n8n (self-hosted o cloud)
- Supabase (cuenta gratuita o Pro)
- WhatsApp Business API (Meta)
- Redis (para agregación de mensajes)
- Cuenta OpenAI (GPT-4o, Whisper)
- Google Cloud (Calendar, Drive, Gemini)
- Fish Audio (para respuestas de voz — planes Medio/Premium)

### Paso 1: Base de datos

Ejecutar el SQL completo en Supabase:

```sql
-- En el SQL Editor de Supabase:
-- Pegar y ejecutar el contenido de database/PODOIA_supabase_completo.sql
```

Esto crea: tablas, funciones, vistas y configuración de pgvector para RAG.

### Paso 2: Importar workflows en n8n

**⚠️ Respetar el orden de importación:**

1. `PODOIA_sub_calendario.json` — importar primero y **copiar su ID**
2. `PODOIA_principal_v2.json` — pegar el ID del sub-calendario en el nodo `calendario`
3. `PODOIA_recordatorio_citas.json`
4. `PODOIA_gestion_noshows.json`
5. `PODOIA_seguimiento_postconsulta.json`
6. `PODOIA_reactivacion_pacientes.json`

### Paso 3: Configurar credenciales en n8n

| Credencial | Tipo | Para qué |
|---|---|---|
| WhatsApp Trigger | WhatsApp Trigger API | Recibir mensajes |
| WhatsApp | WhatsApp API | Enviar mensajes + descargar media |
| OpenAI | OpenAI API | GPT-4o, GPT-4o-mini, Whisper |
| Google Gemini | Google PaLM API | Análisis de imágenes y videos |
| Redis | Redis | Agregación de mensajes en ráfaga |
| Supabase API | HTTP Header Auth | API REST |
| Supabase | Supabase API | Vector Store (RAG) |
| Postgres | PostgreSQL | Memoria del agente |
| Google Calendar | OAuth2 | Gestión de citas |
| Google Drive | OAuth2 | Base de conocimiento RAG |
| Fish Audio | HTTP Header Auth | Text-to-Speech |
| Gmail | OAuth2 | Notificaciones al podólogo |

### Paso 4: Configurar cliente (onboarding)

En el nodo `Config Cliente` del workflow principal, actualizar:

```json
{
  "client_name": "Nombre de la clínica",
  "client_id": "UUID del cliente en Supabase",
  "plan": "basico | medio | premium",
  "google_calendar_id": "calendario@group.calendar.google.com",
  "business_phone_id": "ID del número WhatsApp Business",
  "timezone": "America/Sao_Paulo",
  "horario_laboral": "08:00-18:00",
  "language_default": "pt | es"
}
```

---

## 🧠 Modelos de IA utilizados

| Entrada | Modelo | Proveedor | Costo aprox. |
|---|---|---|---|
| Texto (agente principal) | GPT-4o | OpenAI | ~$0.01/mensaje |
| Audio entrada | Whisper | OpenAI | ~$0.006/min |
| Audio salida (voz) | Fish Audio TTS | Fish Audio | ~$0.01/mensaje |
| Imagen | Gemini 2.5 Flash | Google | ~$0.002/imagen |
| Video | Gemini 2.5 Flash | Google | ~$0.005/video |
| Clasificación intent | GPT-4o-mini | OpenAI | ~$0.0001/msg |

---

## 🗃 Base de datos (Supabase)

| Tabla | Propósito |
|---|---|
| `clients` | Podólogos/clínicas que contratan PodoIA |
| `patients` | Pacientes de cada clínica |
| `appointments` | Citas agendadas |
| `interactions` | Historial de conversaciones |
| `tags` | Etiquetas automáticas por comportamiento |
| `documents` | Base de conocimiento vectorizada (RAG) |
| `plans_features` | Features y límites por plan |
| `monthly_usage` | Contadores de uso mensual |
| `usage_alerts` | Alertas de límites |

---

## 🔄 CRM: Máquina de estados

```
nuevo → lead → cliente → inactivo
                ↑            |
                └────────────┘ (reactivado)
```

Tags automáticos asignados por intención del paciente:  
`nuevo` · `interesado` · `pidio_precios` · `urgente` · `cita_agendada` · `cancelo` · `reactivado`

---

## 📋 Roadmap

- **MVP (Abril 2026)** ✅ — Atención completa: texto · audio · imagen · video · citas · CRM · confirmaciones
- **Etapa 2 (Mayo 2026)** 🔧 — Modularización, escalamiento a humano, dashboard en tiempo real
- **Etapa 3 (Junio 2026+)** 🚀 — Onboarding automatizado, plan PRO, integración pagos

---

## 📄 Licencia

Este proyecto está bajo licencia MIT. Ver archivo [LICENSE](LICENSE) para más detalles.

---

## 👤 Autor

**Shane Medina** — Curitiba, Brasil  
Estratega de sistemas · Constructor de negocios digitales

---

> *PodoIA es un proyecto comercial activo. Este repositorio contiene la arquitectura técnica del sistema. Las credenciales, IDs de clientes y datos sensibles no están incluidos.*

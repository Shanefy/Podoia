# 🦶 PodoIA — Asistente Virtual IA para Podología

Sistema SaaS de automatización de atención al cliente 24/7 por WhatsApp para clínicas podológicas.

**Stack:** n8n · Supabase · WhatsApp Business API · OpenAI · Google Calendar

## ¿Qué es PodoIA?

PodoIA automatiza la atención al paciente de clínicas podológicas vía WhatsApp. Una sola instancia de n8n atiende múltiples clínicas, diferenciando funcionalidades según el plan contratado.

**Mercados objetivo:** Brasil 🇧🇷 · México 🇲🇽
**Idiomas:** Português · Español

## Funcionalidades

- Atención multimodal: texto, audio, imagen y video
- Agendamiento automático con Google Calendar
- CRM con máquina de estados y tags automáticos
- Confirmación de citas (SIM / NO / REAGENDAR)
- Recordatorios 24h antes de cada cita
- Seguimiento post-consulta y reactivación de pacientes
- Tracking de límites por plan
- Multi-tenant: múltiples clínicas en una sola instancia

## Stack tecnológico

- Automatización: n8n
- Base de datos + vectores: Supabase (pgvector)
- Mensajería: WhatsApp Business API (Meta)
- IA texto: GPT-4o / GPT-4o-mini (OpenAI)
- IA audio entrada: Whisper (OpenAI)
- IA audio salida: Fish Audio TTS
- IA imagen/video: Gemini 2.5 Flash (Google)
- Caché: Redis

## Autor

Shane Medina — Curitiba, Brasil

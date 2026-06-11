# Plan senior: Fix ChatScreen reactivo + persistencia local durable en el teléfono

> **Uso:** Copiar todo el contenido de la sección "PROMPT PARA CURSOR (MODO PLAN)" y pegarlo en Cursor → modo **Plan** (no Agent).

---

## PROMPT PARA CURSOR (MODO PLAN)

```markdown
# Plan senior: Fix ChatScreen reactivo + persistencia local durable en el teléfono

## Rol y expectativa

Actúa como **senior Flutter / mobile architecture**. El objetivo es un plan ejecutable con certeza de que, si se sigue al pie de la letra, el resultado queda **100% correcto y verificable**. No propongas parches incrementales que mantengan dos paths de datos. La solución es unificar en **SQLite → Drift.watch → StreamBuilder**.

---

## Contexto confirmado (NO re-investigar backend)

- El **backend, API REST y WebSocket funcionan bien**. El bug es **100% arquitectura UI/estado local en Flutter**.
- Cada frame WS sigue este pipeline (correcto):

```
realtime_service.dart:
  1. Parse JSON → RealtimeEvent
  2. SyncEngine.handleRealtimeEvent escribe en SQLite PRIMERO
  3. _events.add(event) notifica a todos los listeners
```

**Orden garantizado:** SQLite antes que UI. Ambas pantallas reciben el mismo evento en el mismo broadcast stream. La divergencia ocurre **después** de la persistencia.

---

## Diagnóstico ya validado (partir de aquí, no redescubrir)

### ChatsListScreen — funciona bien ✅
- `StreamBuilder` en `build()` sobre `_chats.watchConversations()` (`chats_list_screen.dart` ~232)
- Drift `.watch()` en `conversation_dao.dart` reacciona cuando `SyncEngine._bumpConversationForMessage` actualiza `Conversations`
- Cuando SyncEngine persiste, Drift emite → StreamBuilder reconstruye automáticamente, sin `setState` necesario
- El handler WS `_onRealtimeEvent` (~69) hace segunda pasada y llama `setState` — **redundante** para UI de lista

### ChatScreen — raíz del problema ❌
- Usa lista local `_displayMessages` (~43) fuera del árbol reactivo
- `build()` solo lee `_displayMessages`. **No hay StreamBuilder ni `.watch()` en el árbol de widgets**
- Dos paths paralelos actualizan `_displayMessages` fuera de `build()`:

**Path A — Drift (SQLite → listener → setState condicional)**
- `_messagesSub = _messagesStream.listen(_onMessagesFromStore)` (~81)
- `_applyStoreSnapshot` (~128): `setState` solo si `_messagesSnapshotChanged` retorna true (~142)
- Stream filtrado por `conversationId` exacto en `message_dao.watchForConversation` (~12-19)

**Path B — WebSocket (directo → merge → setState)**
- `_onRealtimeEvent` case `message.new` (~310-324): merge en `_displayMessages`, `setState` incondicional
- Guardas silenciosas: `message == null` (~312), `!_messageBelongsToChat` (~314)

### 5 puntos de divergencia exactos

| # | Divergencia | ChatsListScreen | ChatScreen |
|---|-------------|-----------------|------------|
| 1 | Vínculo UI↔datos | StreamBuilder en build | Lista local `_displayMessages` + setState explícito |
| 2 | Tabla SQLite observada | `Conversations` | `Messages WHERE conversationId = X` |
| 3 | Dependencia path WS | Redundante (Drift basta) | Esencial si Path B falla → UI estancada |
| 4 | setState condicional | Ninguno | `_messagesSnapshotChanged` puede bloquear rebuild |
| 5 | Guardas silenciosas | Una, con fallback StreamBuilder | Tres+ que fallan sin avisar |

### Punto crítico de datos (capa local, no backend)
`message_dao.watchForConversation` filtra por `conversationId` exacto. Si `resolveForLocalStore` persiste con un `conversationId` distinto al del chat abierto, el mensaje **está en SQLite pero el `.watch()` del chat no emite**. ChatsListScreen no sufre esto porque observa `Conversations` y hace bump por `wa_id`.

### Dato clave para el refactor
Los mensajes optimistas **ya se escriben en SQLite** (`MessageRepository.sendMessage` → `upsertMessage(optimistic)` + `outboundQueue`). **No hace falta `_displayMessages` como caché paralela** para pending/outbound.

---

## Requisito adicional: persistencia local durable en el teléfono

El teléfono debe actuar como **archivo local durable** de conversaciones y mensajes. Si luego se borran del servidor (Twilio, backend, etc.), **el historial debe seguir disponible en el celular**.

### Estado actual del código (ya revisado)
- SQLite en `whatsbot_local.db` (`app_database.dart`) con tablas `Conversations`, `Messages`, `OutboundQueue`, `SyncCursors`
- `ChatRepository.refreshFromApi` solo hace **upsert** (sync aditivo) — no borra conversaciones locales si desaparecen del servidor ✅
- `ChatRepository.mergeWithLocal` preserva datos locales si el servidor manda timestamps viejos ✅
- `MessageRepository.retentionPerChat = 500` + `pruneOldMessages` — **sí borra mensajes viejos localmente** ⚠️
- `clearAll()` / logout (`settings_screen` → `AppServices.clearLocalData`) borra todo — solo en logout explícito ✅

### Política de persistencia a definir e implementar (senior)

**Principio:** *Server = canal de sync para datos nuevos. Local = archivo de verdad para historial ya recibido.*

El plan debe especificar:

1. **Sync aditivo, nunca destructivo por ausencia en servidor**
   - Nunca eliminar conversaciones/mensajes locales solo porque el servidor ya no los devuelve
   - Prohibir "full replace" que wipee tablas en sync normal
   - Documentar explícitamente: única forma de borrar local = logout del usuario o acción explícita "borrar datos"

2. **Retención de mensajes**
   - Evaluar si `retentionPerChat = 500` es compatible con "archivo durable"
   - Proponer política senior: p.ej. aumentar límite, retención por antigüedad configurable, o desactivar prune para chats con actividad reciente
   - El prune **no debe contradecir** el requisito de conservar historial si Twilio borra en servidor

3. **Merge local-first en repositorios**
   - Reforzar `mergeWithLocal` y `_preserveLocalConversation` como contrato explícito
   - `resolveForLocalStore` debe canonicalizar siempre al `conversationId` local antes de upsert

4. **UI lee siempre de SQLite**
   - Offline: lista de chats y mensajes visibles desde caché local sin red
   - El fix de ChatScreen (StreamBuilder) **refuerza** este requisito, no lo contradice

5. **Indicador UX opcional** (si aplica en plan)
   - Diferenciar "sin conexión" vs "dato solo local" sin alarmar al usuario

---

## Arquitectura objetivo

### Antes (ChatScreen — incorrecto)
```
WS → SyncEngine → SQLite → Drift.watch → listener manual → _displayMessages → build()
         ↓
    WS listener → merge directo → _displayMessages → build()   ← ELIMINAR
```

### Después (correcto — igual que ChatsListScreen)
```
WS → SyncEngine → SQLite (archivo durable) → Drift.watch → StreamBuilder → build()
                                                      ↑
                                              única fuente de verdad UI

WS handler ChatScreen → solo efímero (typing, órdenes) + side effects (markRead, seen)
```

**Un solo path para mensajes.** El handler WS del chat **no muta la lista de mensajes**.

---

## Alcance del plan — Fase 1: Eliminar arquitectura dual (cambio principal)

- [ ] Reemplazar `_displayMessages` + `_messagesSub` listener manual por `StreamBuilder<List<ChatMessage>>` en `build()` usando `_messageRepo.watchMessages(widget.conversation.id)`
- [ ] Eliminar Path B: quitar merge de `message.new` y `message.status` en `_onRealtimeEvent` de `ChatScreen`
- [ ] Eliminar o simplificar: `_applyStoreSnapshot`, `_reconcileWithStore`, `_mergeMessageIntoDisplay`, `_messagesSnapshotChanged`, `_mergeMessageFields` (si solo servían al dual path)
- [ ] Quitar `_refresh(silent: true, force: true)` post-WS en `message.new` / `message.status` — es un parche que enmascara fallos
- [ ] Mantener `_refresh` solo para: reconexión WS, pull-to-refresh manual, fallback timer WS caído (~364-371), apertura inicial del chat
- [ ] Extraer scroll automático y `_persistSeen` a listeners de side-effect (StreamSubscription sobre el stream de mensajes), no como estado duplicado en memoria
- [ ] Mantener en handler WS solo: `typing.start/stop`, `order.pending/updated`, side effects (`_markRead` al detectar entrante vía stream listener, no merge)

---

## Alcance del plan — Fase 2: Endurecer capa de datos + persistencia durable

- [ ] Verificar que `resolveForLocalStore` (`message_repository.dart` ~67) siempre canonicalice al `conversationId` local antes de `upsert` en `SyncEngine._handleMessageNew`
- [ ] Si no puede resolver `wa_id` → conversación local: comportamiento explícito (log/assert en debug, `syncConversationsIncremental()`, no persistir silenciosamente con `conversationId` incorrecto)
- [ ] Auditar que ningún sync path haga delete/replace de conversaciones o mensajes por ausencia en API
- [ ] Revisar y ajustar política de `pruneOldMessages` (`retentionPerChat = 500`) para alinearla con archivo durable — documentar decisión en el plan
- [ ] Confirmar que `mergeWithLocal` y `_preserveLocalConversation` no pierden historial ante respuestas vacías o parciales del servidor
- [ ] Limpiar redundancia en `ChatsListScreen`: handler WS solo para side effects (alertas, `messageAlerts`), eliminar `setState(() {})` final (~101) innecesario para UI de lista
- [ ] Verificar flujo offline: `watchConversations()` y `watchMessages()` muestran datos locales sin red

---

## Alcance del plan — Fase 3: Verificación obligatoria al 100%

El plan **debe incluir** verificación ejecutable. No basta con "revisar manualmente".

### Tests automatizados obligatorios

**Fix reactivo ChatScreen:**
- [ ] WS `message.new` → `SyncEngine` persiste → `watchMessages` emite → UI muestra mensaje **sin** handler WS de merge en ChatScreen
- [ ] Mensaje entrante con `conversationId` servidor distinto pero mismo `wa_id` → aparece en el chat abierto
- [ ] Envío optimista (`sendMessage`) → mensaje `pending` visible vía stream → ack con `clientUuid` → UI actualiza status sin duplicar
- [ ] `message.status` (delivered/read) → UI refleja cambio vía Drift, no vía WS directo en ChatScreen
- [ ] Typing indicator sigue funcionando (efímero, fuera del stream de mensajes)
- [ ] Regresión: `ChatsListScreen` sigue actualizando preview/orden al llegar mensaje nuevo

**Persistencia durable local:**
- [ ] Conversación y mensajes persisten en SQLite tras recibir WS (verificar filas en DB en test)
- [ ] Sync API que devuelve lista vacía o sin una conversación existente **no borra** la conversación local
- [ ] `mergeWithLocal` no retrocede `lastMessageAt`/preview cuando servidor manda datos más viejos
- [ ] Tras simular "conversación ausente en servidor", `watchConversations()` sigue emitiéndola
- [ ] Tras simular "mensajes ausentes en API incremental", mensajes locales siguen en `watchMessages()`
- [ ] Logout (`clearLocalData`) sí borra todo — único wipe permitido
- [ ] Política de retención/prune: test que documente el comportamiento acordado (no borrar más de lo esperado)

### Comandos de verificación a incluir en el plan
```bash
flutter test test/screens/chat_screen_test.dart
flutter test test/screens/chats_list_screen_test.dart
flutter test test/integration/realtime_e2e_test.dart
flutter test
```

### Checklist manual / integración

**Realtime UI:**
- [ ] Abrir chat A, recibir mensaje por WS → aparece sin pull-to-refresh
- [ ] Lista de chats muestra preview actualizado al mismo tiempo
- [ ] Enviar mensaje con red → aparece pending → pasa a sent sin duplicado
- [ ] Enviar sin red → queued → al reconectar se envía y UI actualiza
- [ ] Scroll: leyendo historial arriba → no auto-scroll; abajo → auto-scroll
- [ ] Marcar leído/seen al entrar y salir del chat
- [ ] Reconexión WS: mensajes durante desconexión aparecen tras sync

**Persistencia durable:**
- [ ] Cerrar y reabrir app → conversaciones y mensajes siguen visibles sin red
- [ ] Modo avión → lista de chats y chat abierto muestran historial local
- [ ] Tras sync con servidor que no devuelve una conversación antigua → sigue visible en el teléfono
- [ ] Historial de mensajes antiguos sigue accesible según política de retención definida

### Criterios de éxito — definición de "100%"

- [ ] Cero dependencia de Path B para mostrar mensajes en ChatScreen
- [ ] Cero `setState` condicional para datos que vienen de SQLite
- [ ] UI de mensajes = `StreamBuilder` sobre `watchMessages` (mismo patrón que ChatsListScreen)
- [ ] Servidor/Twilio puede perder datos; teléfono conserva historial ya sincronizado (sync aditivo)
- [ ] Todos los tests nuevos y existentes pasan: `chat_screen_test.dart`, `realtime_e2e_test.dart`, `chats_list_screen_test.dart`
- [ ] `flutter test` completo en verde

---

## Restricciones para el implementador

- **No tocar backend** ni contratos de API/WebSocket
- **No añadir** tercer path de datos (ni polling extra, ni merge híbrido WS+Drift en UI)
- **Minimizar diff**: reutilizar `MessageRepository.watchMessages`, `SyncEngine`, patrón de `ChatsListScreen`
- **No** dejar `_refresh(force: true)` como parche post-WS
- Mensajes optimistas: confiar en SQLite, no reintroducir caché en memoria
- Persistencia: no implementar "sync destructivo" para parecerse al servidor
- Solo crear commits si el usuario lo pide explícitamente
- No crear archivos de documentación (.md) no solicitados

---

## Archivos clave a revisar/modificar

| Archivo | Qué |
|---------|-----|
| `lib/screens/chat_screen.dart` | Refactor principal → StreamBuilder, eliminar dual path |
| `lib/screens/chats_list_screen.dart` | Limpiar redundancia WS/setState |
| `lib/data/sync/sync_engine.dart` | Resolución `conversationId`, persist antes de UI |
| `lib/data/repositories/message_repository.dart` | `resolveForLocalStore`, `watchMessages`, retención/prune |
| `lib/data/repositories/chat_repository.dart` | `mergeWithLocal`, sync aditivo, no-delete policy |
| `lib/data/local/daos/message_dao.dart` | Filtro `watchForConversation` |
| `lib/data/local/daos/conversation_dao.dart` | `watchForBusiness` |
| `lib/data/local/app_database.dart` | `clearAll` solo en logout |
| `test/screens/chat_screen_test.dart` | Tests reactivos + optimistic + status |
| `test/integration/realtime_e2e_test.dart` | Pipeline WS → SQLite → UI |
| `test/screens/chats_list_screen_test.dart` | Regresión lista |
| Tests nuevos si hace falta | Persistencia durable, server-absent-no-delete |

---

## Qué NO hacer (anti-patrones explícitos)

- ❌ Mantener Path B "por si acaso" o como fallback
- ❌ Arreglar solo `_messagesSnapshotChanged` sin unificar arquitectura
- ❌ Más guardas silenciosas en UI en lugar de arreglar `resolveForLocalStore`
- ❌ `_refresh(force: true)` después de cada WS event
- ❌ Borrar conversaciones/mensajes locales porque el servidor no los devuelve
- ❌ Full table replace en sync incremental
- ❌ Reintroducir `_displayMessages` como caché paralela
- ❌ Polling REST mientras WS está conectado

---

## Entregable esperado del modo Plan

Genera un plan con estas secciones, en este orden:

1. **Diagnóstico resumido** (1 párrafo: bug UI, backend OK, dual path en ChatScreen)
2. **Arquitectura objetivo** (diagrama antes/después del flujo de datos)
3. **Política de persistencia local** (sync aditivo, retención, qué se borra y cuándo)
4. **Plan por fases** (Fase 1, 2, 3) con tareas concretas, orden de ejecución y dependencias
5. **Riesgos y mitigaciones** (scroll, optimistic ack, conversationId mismatch, prune vs archivo, offline)
6. **Plan de tests detallado** (casos exactos, archivos a crear/modificar, asserts concretos)
7. **Checklist de verificación manual** paso a paso
8. **Criterios de aceptación medibles** (tests verdes + checklist manual)
9. **Qué NO hacer** (lista anti-patrones)
10. **Orden de implementación recomendado** (secuencia día 1 / día 2 si aplica)

El plan debe dar **certeza** de que, ejecutado completo, el fix es correcto, la UI es reactiva como ChatsListScreen, y el teléfono conserva el historial aunque el servidor/Twilio pierda datos.
```

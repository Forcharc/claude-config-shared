---
paths:
  - "**/*.kt"
  - "**/*.kts"
---

# Kotlin Rules

## Актуальность технологий

Использовать современные API, не legacy:

| Legacy | Актуально |
|--------|-----------|
| AsyncTask, Thread, Executors | Coroutines (`suspend`, `launch`, `async`) |
| RxJava (в новом коде) | Flow, StateFlow, SharedFlow |
| LiveData (в новых модулях) | StateFlow / compose State |
| Callback-стиль | `suspendCancellableCoroutine` |
| `Handler(Looper.getMainLooper())` | `withContext(Dispatchers.Main)` |
| Java Date/Calendar | `kotlinx.datetime` (KMP/Android), `java.time` (JVM backend) |
| Java streams | Kotlin stdlib (`map`, `filter`, `fold`) |

## Ревью: Compose / Compose Multiplatform

- **Забытые `remember`:** вычисления внутри Composable без `remember` пересоздаются при каждой рекомпозиции
- **Побочные эффекты без `LaunchedEffect`/`DisposableEffect`:** подписки, запросы, таймеры должны быть в effect-хэндлерах
- **State hoisting:** state, который используется выше по дереву, должен быть поднят
- **Лишние рекомпозиции:** передача нестабильных объектов (List, Map без @Immutable) в Composable

## Ревью: Coroutines

- **Блокирующие вызовы в suspend-функциях:** Thread.sleep, блокирующий IO без withContext(Dispatchers.IO)
- **Утечки корутин:** launch без structured concurrency (GlobalScope, незакрытые scope)
- **Пропущенный cancellation:** долгие операции без isActive/ensureActive проверок
- **Неправильный dispatcher:** CPU-работа на Dispatchers.IO, IO-работа на Main
- **Проглоченный CancellationException:** в suspend-коде / внутри `launch { ... }` нельзя ловить `CancellationException` в `catch (e: Exception)` без перебрасывания. Варианты:
  1. Использовать `launchSafely { ... }` из `ui-common:com.example.ui.common.coroutines` — он пробрасывает отмену автоматически.
  2. Явный `catch (e: CancellationException) { throw e }` перед `catch (e: Exception)`.
  3. `coroutineContext.ensureActive()` перед обработкой ошибки.
  Причина: проглоченная отмена ломает structured concurrency и показывает «CancellationException» в UI при штатном reconnect.

## Ревью: Kotlin idioms

- **`!!` (non-null assertion):** почти всегда можно заменить на `?.let`, `?:`, или `requireNotNull` с сообщением
- **`var` где можно `val`:** мутабельность без необходимости
- **Java-стиль:** ручные циклы вместо `map`/`filter`/`fold`, StringBuilder вместо `buildString`
- **Пустые catch-блоки:** проглоченные исключения без логирования

## Ревью: Ktor / Server

- **Блокирующий код в route-хэндлерах:** без withContext
- **Незакрытые ресурсы:** HttpClient, Connection без use/close

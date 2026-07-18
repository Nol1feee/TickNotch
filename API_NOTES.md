# TickTick private API — заметки (Phase 1)

Собрано из OSS-обёрток ([node-ticktick-unofficial](https://github.com/Nyrest/node-ticktick-unofficial),
[ticktick-api-v2](https://github.com/OliverStoll/ticktick-api-v2),
[ticktick-py](https://github.com/lazeroffmichael/ticktick-py)) + живой проверки формата focus-записей
через TickTick MCP на этом аккаунте. Что не подтверждено реальным трафиком — помечено «ПРОВЕРИТЬ».

## Хосты

| Хост | Назначение |
|---|---|
| `https://api.ticktick.com` | основной v2 API (`/api/v2/...`) |
| `https://ms.ticktick.com` | синк фокус-сессий (**live-состояние**) |
| `https://ticktick.com` | веб-клиент (Origin/Referer) |
| `wss://wss.ticktick.com` | push (не реверсили; поллинга хватает) |

## Аутентификация и заголовки

Cookie от залогиненной сессии ticktick.com:

- `t=<token>` — auth-токен (обязателен);
- `_csrf_token=<...>` — если есть, его значение дублируется в заголовок `x-csrftoken`.

Прочие заголовки веб-клиента (шлём как браузер):

```
Accept: application/json, text/plain, */*
Content-Type: application/json;charset=UTF-8
Origin: https://ticktick.com
Referer: https://ticktick.com/webapp/
User-Agent: Mozilla/5.0 (Macintosh; ...) Chrome/136...
x-tz: Europe/Belgrade            # таймзона пользователя
X-Device: {"platform":"web","os":"macOS","device":"Chrome 136.0.0.0","name":"","version":6310,"id":"<24 hex>","channel":"website","campaign":"","websocket":""}
```

`X-Device.id` — произвольные 24 hex, но стабильные для «устройства» (генерим раз, храним в UserDefaults).

## Live-состояние фокуса (ключевой эндпоинт)

```
POST https://ms.ticktick.com/focus/batch/focusOp
{"lastPoint": 0, "opList": []}
```

Это батч-синк фокус-операций между устройствами. Пустой `opList` = «ничего не пишу, отдай состояние».
Ответ:

```
{
  "point": <number>,   // курсор синка — сохраняем и шлём в следующем запросе
  "current": { ... },  // текущая/последняя сессия (возвращается ВСЕГДА, даже с новым point)
  "updates": [ ... ]   // операции после lastPoint; с lastPoint=0 — вся история (сотни КБ!)
}
```

**Проверено живым трафиком этого аккаунта (436 сессий в `updates`), 2026-07-18:**

| Поле | Семантика |
|---|---|
| `type` | **0 = помидор**, **1 = секундомер** (⚠️ в records-API наоборот) |
| `duration` | помидор: план в **минутах** (сессия ровно 90 мин ↔ `duration: 90`); секундомер: 0 |
| `status` | **0 = идёт**, **2 = завершён** (норм. финиш), **3 = сброшен (drop)**; **1 = пауза** (единственный оставшийся код; live-подтверждение pending) |
| `exited` | `true` = сессия закрыта/ушла с экрана фокуса — **главный фильтр** «показывать ли» |
| `valid` | флаг валидности |
| `startTime`/`endTime` | ISO `.SSS+0000`; для идущего помидора `endTime` = прогноз конца (с учётом пауз); у секундомера — кап +12ч |
| `focusTasks[]` | отрезки фокуса `{startTime, endTime, title, id, type}`; **название задачи здесь**; паузы = разрывы между отрезками; на паузе последний отрезок закрыт |
| `focusOnLogs[]` | журнал переключений задач `{time, title}` |
| `pauseLogs[]` | события пауз `{type, time}` (type 0 — пауза) |
| `focusBreak` | перерыв: `{endTime}` — конец брейка; пустой `{}` если нет |
| `pomoCount`, `autoPomoLeft` | счётчики серии помидоров |

Расчёты в `FocusParser` (FocusModels.swift):
- идущий помидор: остаток = `endTime - now` (fallback: план − Σ отрезков);
- пауза: остаток заморожен = план − Σ закрытых отрезков;
- секундомер: elapsed = Σ отрезков (+ тик от последнего старта);
- `exited=true`, `status ∈ {2 без будущего брейка, 3}`, зомби (>12ч) → скрыть.

### Осталось подтвердить live:

1. `status` во время паузы == 1 (выведено методом исключения; все терминальные коды известны).
2. Точная форма `focusBreak` во время идущего перерыва.

Если что-то поедет: меню-бар → «Скопировать последний ответ API» → сверить с таблицей.

## Подтверждено живым запросом (MCP, этот аккаунт)

Завершённая pomo-запись (`type=1`; `type=0` — секундомер):

```json
{
  "id": "6a524312310ad10328af523f",
  "type": 1,
  "tasks": [{
    "taskId": "6a50b06ef8d351252b6d8ed6",
    "title": "р - работа!)",
    "startTime": "2026-07-11T13:20:18+0000",
    "endTime": "2026-07-11T13:27:38+0000"
  }],
  "status": null,
  "startTime": "2026-07-11T13:20:18+0000",
  "endTime": "2026-07-11T13:27:39+0000",
  "pauseDuration": 0,
  "duration": 441000
}
```

Выводы: даты — ISO `+0000`, `duration` записей — **миллисекунды**, привязка к задаче —
массив `tasks[]` с `title`.

## Открыть задачу в приложении TickTick (клик по бару)

**Что РАБОТАЕТ (проверено скриншотом — деталь задачи раскрылась):**

```
open -a TickTick "https://ticktick.com/webapp/#q/all/tasks/{taskId}"
```

Форсируем приложение открыть его же веб-URL задачи — TickTick перехватывает,
переключается на задачу и **раскрывает панель детали** (редактируемую, с чеклистом).
Маршрут `#q/all/…` **проектонезависимый** — `projectId` НЕ нужен, клик без сети, мгновенный.
Форма с проектом `#p/{projectId}/tasks/{taskId}` тоже работает.
Swift: `NSWorkspace.open([url], withApplicationAt: tickTickAppURL, configuration:)` с `activates=true`.

**Что НЕ работает (важно, чтобы не наступить снова):**

- Кастомная схема `ticktick://ticktick.com/p/{pid}/tasks/{id}` и `ticktick://tasks/{id}`
  задачу **не открывают** — только активируют приложение (остаётся текущий экран).
  Роутер Crossroad; маршруты `/tasks/`, `/focus`, `/matrix`, `/create` есть, но детали задачи
  извне не раскрывают.
- ⚠️ Ранее ошибочно засчитал «родную стики над fullscreen» за результат deep-link'а —
  на деле всплывала **ранее закреплённая** пользователем стики той задачи при активации
  приложения, а не следствие ссылки. Стики (`open_as_sticky_note`) внешне не вызывается
  (приватное UI-действие `bottomActionViewDidClickOpenSticky:`, только через Accessibility — хрупко).

Бонус: TickTick.app **скриптуется** (`NSAppleScriptEnabled=true`, `TickTick.sdef` — команды
`search tasks`, `today tasks`, `start pomo`, `toggle task`, всё возвращает JSON) — запасной путь
для резолва задач без веб-API. И есть push-эндпоинт помидора `https://pull.ticktick.com/common/pomodoro/v2/`
(long-poll) — кандидат на мгновенный синк вместо опроса.

## Прочие полезные эндпоинты (api.ticktick.com, из OSS)

```
GET /api/v2/pomodoros/statistics/generalForDesktop
GET /api/v2/pomodoros/timeline[?to=...]
GET /api/v2/pomodoros/statistics/heatmap/{start}/{end}
GET /api/v2/batch/check/0          # полный синк задач/проектов
POST /api/v2/user/signon?wc=true&remember=true   # логин паролем (не используем)
```

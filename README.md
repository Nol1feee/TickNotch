# TickNotch

![TickNotch](docs/hero.png)

Фокус-таймер TickTick у выреза MacBook. Идёт помидор — время висит под чёлкой,
поверх всех окон и в полноэкранных приложениях. Кончилась сессия — бар пропал.
Больше он ничего не делает, и это весь смысл.

- 🔴 фокус · 🟢 перерыв · 🟡 пауза
- виден на всех рабочих столах и над fullscreen
- синк с сервером каждые 2 секунды, между опросами время тикает локально
- работает, даже когда само приложение TickTick закрыто

## Скачать

**[TickNotch-1.0.dmg → релизы](https://github.com/Nol1feee/TickNotch/releases/latest)** — открой DMG, перетащи в Applications.

Приложение без подписи Apple. При первом запуске: правый клик по `TickNotch.app` → «Открыть».
Если ругается «повреждено» — сними карантин:

```bash
xattr -dr com.apple.quarantine /Applications/TickNotch.app
```

Значок появится в строке меню (таймер), не в Dock. Оттуда — cookie, автозапуск, выход.

## Cookie

Официальный API TickTick таймер фокуса не отдаёт, поэтому нужен cookie сессии:

1. Залогинься на [ticktick.com](https://ticktick.com/webapp).
2. DevTools (⌥⌘I) → Application → Cookies → скопируй значение `t`.
3. Значок в строке меню → «Ввести cookie…» → вставь → «Сохранить и проверить».

Хранится локально: `~/Library/Application Support/TickNotch/cookie` (права 0600).
Токен долгий, но при разлогине протухает — тогда введи заново.

## Сборка

```bash
./build.sh
```

Или Xcode: открой `TickNotch.xcodeproj`, ⌘R. macOS 14+, без сторонних зависимостей.

---

Что за приватный API и как он устроен — в [API_NOTES.md](API_NOTES.md).
Это неофициальный веб-API TickTick, формально против их ToS — на свой страх и риск.

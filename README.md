# AuraFlow for macOS

<p align="center">
  <img src="docs/aura-ui.png" width="760" alt="AuraFlow UI preview" />
</p>

AuraFlow — живые обои для macOS: демон на Python + PyObjC и SwiftUI-интерфейс на AppKit. Панель управления скрывается при бездействии, позволяет выбирать видео, задавать скорость проигрывания и управлять автозапуском.

## 🚀 Установка

| Способ | Для кого | Что делать |
| --- | --- | --- |
| **Готовый DMG** | macOS на Apple Silicon (arm64) и Intel (x86_64) | Скачайте `dist/AuraFlow.dmg`, откройте образ и перетащите `AuraFlow.app` в `/Applications`. |
| **Сборка из исходников** | Разработчикам | Запустите `./build_app.sh`. В каталоге `dist/` появятся свежие `AuraFlow.app`, `AuraFlow.zip` и `AuraFlow.dmg`. |

*DMG содержит универсальный бинарник (arm64+x86_64), поэтому работает на обоих типах процессоров.*

## Архитектура
- `python/` – демон `wallpaper_daemon.py`, CLI `control.py`, вспомогательные модули и тесты.
- `macOSApp/` – Swift Package с GUI (SwiftUI + AppKit) и мостом `PythonBridge`.
- `scripts/build_release.sh` / `build_app.sh` – сборка `.app`, упаковка зависимостей, создание `.zip` и `.dmg`.

## Возможности интерфейса
- Клиентская декорация окна, полупрозрачный blur-интерфейс.
- Предпросмотр видео и мгновенная установка первого кадра в качестве системных обоев.
- Управление скоростью (0.25× – 2×), кнопки запуска/остановки, автозапуск через LaunchAgent.

## Тестирование
- Python: `python3 -m unittest discover -s python/tests`
- Swift: `cd macOSApp && swift test`

## Настройка автозапуска
```bash
python3 python/control.py set-autostart on
```
Создаётся LaunchAgent `~/Library/LaunchAgents/com.example.auraflow.plist`.

## Диагностика
- Логи демона – `~/Library/Application Support/AuraFlow/daemon.log`
- PID-файл – `~/Library/Application Support/AuraFlow/daemon.pid`
- Конфигурация – `~/Library/Application Support/AuraFlow/config.json`

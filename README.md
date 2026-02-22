# AuraFlow for macOS

<p align="center">
  <img src="docs/aura-ui.png" width="760" alt="AuraFlow UI preview" />
</p>

AuraFlow — живые обои для macOS: демон на Python + PyObjC и SwiftUI-интерфейс на AppKit. Панель управления скрывается при бездействии, позволяет выбирать видео, задавать скорость проигрывания и управлять автозапуском.

## 🚀 Установка

| Способ | Для кого | Что делать |
| --- | --- | --- |
| **Готовый DMG** | macOS на Apple Silicon (arm64) и Intel (x86_64) | Скачайте `dist/AuraFlow.dmg`, откройте образ и перетащите `AuraFlow.app` в `/Applications`. |
| **Сборка из исходников** | Разработчикам | Запустите `PYTHON_BUILD_PYTHON=/usr/bin/python3 ./build_app.sh`. В каталоге `dist/` появятся `AuraFlow.app`, `AuraFlow.zip` и `AuraFlow.dmg`. |

*DMG содержит универсальный бинарник (arm64+x86_64), поэтому работает на обоих типах процессоров.*

## Архитектура
- `python/` – демон `wallpaper_daemon.py`, CLI `control.py`, вспомогательные модули и тесты.
- `macOSApp/` – Swift Package с GUI (SwiftUI + AppKit) и мостом `PythonBridge`.
- `scripts/build_release.sh` / `build_app.sh` – сборка `.app`, упаковка зависимостей, создание `.zip` и `.dmg`.

## Возможности интерфейса
- Клиентская декорация окна, полупрозрачный blur-интерфейс.
- Предпросмотр видео и мгновенная установка первого кадра в качестве системных обоев.
- Управление скоростью (0.25× – 2×), кнопки запуска/остановки, автозапуск через LaunchAgent.

## Сборка `.app`

### Быстрая локальная сборка (arm64)
```bash
cd /Users/prplx/AuraFlow
BUILD_UNIVERSAL=0 PYTHON_BUILD_PYTHON=/usr/bin/python3 ./build_app.sh
```

### Universal сборка (arm64 + x86_64)
```bash
cd /Users/prplx/AuraFlow
BUILD_UNIVERSAL=1 PYTHON_BUILD_PYTHON=/usr/bin/python3 ./build_app.sh
```

Примечания:
- Для universal-сборки может понадобиться Rosetta (`arch -x86_64 ...`).
- В `dist/` всегда формируются `.app`, `.zip` и `.dmg`.
- Python-зависимости (PyObjC) вендорятся внутрь `.app` автоматически.
- Базовый запуск не требует Homebrew-зависимостей.
- `ffmpeg` нужен только для режимов, где включено software AV1-encoding.

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

## Troubleshooting сборки
- Если после `Build complete!` кажется, что сборка "зависла", обычно это шаг `Vendoring Python dependencies` (`pip install`). Это нормально и может занять время.
- Если скрипт пишет `Another build is already running`, удалите lock-файл: `rm -rf /Users/prplx/AuraFlow/.build-lock`.

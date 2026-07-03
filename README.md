<p align="center">
  <img src="AudioCore/Sources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="AudioCore icon">
</p>

<h1 align="center">AudioCore</h1>

<p align="center">
  Микшер приложений для macOS — своя громкость для каждого приложения.<br>
  Per-application volume mixer for macOS.
</p>

<p align="center">
  <a href="#-русский">Русский</a> · <a href="#-english">English</a>
</p>

---

## 🇷🇺 Русский

Менюбар-приложение для macOS, которое даёт каждому запущенному приложению свой собственный слайдер громкости — независимо от общей громкости системы. Работает через нативный Core Audio Process Tap: перехватывает звук нужного приложения, применяет к нему свою громкость/мьют и подмешивает обратно в реальный вывод.

**[Скачать готовую сборку →](https://github.com/Dev14dbq/AudioCore/releases/latest)**

### Возможности

- Отдельный слайдер громкости (0–150%) для каждого приложения, которое сейчас издаёт звук
- Мьют конкретного приложения без влияния на остальные
- Список приложений обновляется автоматически
- Управление через Siri Shortcuts / Control Center
- Настройки громкости сохраняются между запусками
- Автозапуск при входе в систему

### Установка

Скачай `AudioCore.zip` из [релизов](https://github.com/Dev14dbq/AudioCore/releases/latest), распакуй и перенеси `AudioCore.app` в `Applications`.

Сборка подписана самоподписанным сертификатом (без Apple Developer Program), поэтому при первом запуске macOS покажет предупреждение «неизвестный разработчик» — это нормально. Правый клик по `AudioCore.app` → «Открыть» (один раз), либо в терминале:

```bash
xattr -cr /Applications/AudioCore.app
```

При первом запуске приложение попросит разрешение на запись системного звука — без него звук управляемых приложений будет тихим.

> Расширение Control Center в эту сборку не входит: entitlement App Groups требует настоящий provisioning profile от Apple, который самоподписанный сертификат получить не может. Основное меню-бар приложение это не затрагивает.

### Сборка из исходников

```bash
brew install xcodegen
xcodegen generate
open AudioCore.xcodeproj
```

Требуется macOS 26+ и Xcode 17+.

---

## 🇬🇧 English

A macOS menu bar app that gives every running application its own volume slider, independent of the system-wide volume. It works through the native Core Audio Process Tap API: it captures a target app's audio, applies its own gain/mute, and mixes the result back into the real output device.

**[Download the prebuilt app →](https://github.com/Dev14dbq/AudioCore/releases/latest)**

### Features

- Per-app volume slider (0–150%) for every app currently making sound
- Mute a single app without affecting anything else
- App list updates automatically
- Control via Siri Shortcuts / Control Center
- Volume settings persist across app relaunches
- Launch at login

### Installation

Download `AudioCore.zip` from the [releases page](https://github.com/Dev14dbq/AudioCore/releases/latest), unzip it, and move `AudioCore.app` to `Applications`.

The build is signed with a self-signed certificate (no paid Apple Developer Program), so macOS will show an "unidentified developer" warning on first launch — that's expected. Right-click `AudioCore.app` → "Open" once, or in Terminal:

```bash
xattr -cr /Applications/AudioCore.app
```

On first launch the app will request permission to record system audio — without it, the audio of controlled apps stays silent.

> The Control Center extension isn't included in this build: the App Groups entitlement requires a real Apple-issued provisioning profile, which a self-signed certificate can't obtain. The main menu bar app is unaffected.

### Building from source

```bash
brew install xcodegen
xcodegen generate
open AudioCore.xcodeproj
```

Requires macOS 26+ and Xcode 17+.

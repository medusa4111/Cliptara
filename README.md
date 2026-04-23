# Cliptara

## Русский

Cliptara — приложение для macOS в строке меню, которое помогает быстро делать скриншоты, записывать экран и сжимать видеофайлы.

### Быстрый старт

1. Откройте страницу релизов: [Releases](https://github.com/medusa4111/Cliptara/releases)
2. Скачайте `Cliptara.dmg`.
3. Откройте `.dmg` и перетащите `Cliptara.app` в `Applications`.
4. Запустите приложение из `Программы` (`Applications`).
5. При первом запуске дайте нужные разрешения macOS (Запись экрана и т.д.).

### Структура

- создайте папку `~/Documents/cliptara`
- распакуйте туда исходники проекта
- итоговый путь до проекта должен быть: `~/Documents/cliptara/shot`

### Что умеет

- Скриншот области экрана по горячей клавише.
- Скриншот всего экрана с визуальной вспышкой.
- Запись видео экрана (старт/стоп одной горячей клавишей).
- Сжатие видео до целевого размера в МБ из меню приложения.
- Выбор действия для скриншота: копировать в буфер или сохранить в файл.
- Выбор формата скриншотов: `PNG`, `JPG`, `WEBP`.
- Настройка целевого битрейта видео.
- Переназначение горячих клавиш прямо в окне настроек.
- Проверка обновлений через GitHub Releases.

### Горячие клавиши по умолчанию

- `Ctrl+\`` — скриншот области
- `Ctrl+1` — скриншот экрана
- `Ctrl+2` — старт/стоп записи видео

Все горячие клавиши можно изменить в настройках.

### Папки по умолчанию

- Скриншоты: `~/Documents/cliptaramaterials/Screenshots`
- Видео: `~/Documents/cliptaramaterials/Videos`

### Сборка и запуск

```bash
cd ~/Documents/cliptara/shot
swift build -c release
.build/release/Cliptara
```

### Упаковка `.dmg`

```bash
cd ~/Documents/cliptara/shot
./package_cliptara_dmg.sh
```

Готовый файл: `dist/Cliptara.dmg`

### Обновления через GitHub

1. Загрузите новый `Cliptara.dmg` в GitHub Release.
2. Обновите `update.json` в `main` (шаблон: [update-manifest.example.json](./update-manifest.example.json)).
3. В приложении нажмите `Проверить обновления…`.

---

## English

Cliptara is a macOS menu bar app for fast screenshots, screen recording, and quick video compression.

### Quick start for regular users

1. Open the releases page: [Releases](https://github.com/medusa4111/Cliptara/releases)
2. Download `Cliptara.dmg`.
3. Open the `.dmg` and drag `Cliptara.app` to `Applications`.
4. Launch the app from `Applications`.
5. On first launch, grant required macOS permissions (Screen Recording, etc.).

### If you want to run from source

Recommended layout (to avoid confusion):

- create `~/Documents/cliptara`
- unpack the source code into that folder
- final project path should be: `~/Documents/cliptara/shot`

### Features

- Area screenshot via a global hotkey.
- Full-screen screenshot with flash feedback.
- Screen video recording (single start/stop hotkey).
- Video compression to a target size (MB) from the app menu.
- Screenshot action mode: copy to clipboard or save to file.
- Screenshot formats: `PNG`, `JPG`, `WEBP`.
- Configurable target video bitrate.
- Rebindable hotkeys in Settings.
- In-app update checks via GitHub Releases.

### Default hotkeys

- `Ctrl+\`` — area screenshot
- `Ctrl+1` — full-screen screenshot
- `Ctrl+2` — start/stop video recording

All hotkeys can be changed in Settings.

### Default folders

- Screenshots: `~/Documents/cliptaramaterials/Screenshots`
- Videos: `~/Documents/cliptaramaterials/Videos`

### Build and run

```bash
cd ~/Documents/cliptara/shot
swift build -c release
.build/release/Cliptara
```

### Build `.dmg`

```bash
cd ~/Documents/cliptara/shot
./package_cliptara_dmg.sh
```

Output file: `dist/Cliptara.dmg`

### GitHub-based updates

1. Upload a new `Cliptara.dmg` to a GitHub Release.
2. Update `update.json` in `main` (template: [update-manifest.example.json](./update-manifest.example.json)).
3. In the app menu, click `Check for updates…`.

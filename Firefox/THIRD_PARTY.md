# Upstream и лицензии

Наши новые файлы `Firefox/chrome/*`, сборщик, перенос и тесты распространяются по [MIT проекта](../LICENSE). Изменённые существующие файлы Mozilla сохраняют MPL-уведомления; новый код не меняет лицензии движка и его зависимостей.

## Mozilla Firefox / Gecko

- Версия: **160.0.1**, русская macOS-сборка.
- Исходный репозиторий из официального `application.ini`: https://hg.mozilla.org/releases/mozilla-release
- Ревизия: `b1145b0710192f716be5f59f5b2dfeed650d5294`.
- Официальная поставка и SHA-256: [upstream.lock.json](upstream.lock.json).
- Исходные тексты релиза: https://archive.mozilla.org/pub/firefox/releases/160.0.1/source/
- Сохранённые уведомления о Mozilla и сторонних компонентах доступны в установленном браузере на `about:license`.
- Движок C++ не изменялся и отдельно не компилировался. Изменения открытых ресурсов воспроизводятся [build.py](build.py); модифицированные XHTML/JS/FTL и стили также доступны в открытом виде внутри `Contents/Resources/browser/omni.ja` готового приложения. `read_jar()` в сборщике читает и исходный оптимизированный Mozilla JAR, и обычный ZIP.

Изменённые upstream-ресурсы:

1. `chrome/browser/content/browser/browser.xhtml` — подключение открытых файлов myBro.
2. `localization/*/branding/brand.ftl` — название GrayFox.
3. `defaults/preferences/firefox.js` — настройки поставки myBro.
4. `chrome/browser/content/browser/default-bookmarks.html` — пустой начальный набор закладок с сохранённым MPL-уведомлением.

Также меняются метаданные macOS, `application.ini`, политика обновления и значок; собственные ресурсы добавляются в `chrome/browser/content/browser/mybro/`. Оригинальные лицензии других файлов и компонентов сохраняются в официальной поставке.

## Проверка uBlock Origin

В одноразовом тестовом профиле проверен подписанный Mozilla Add-ons пакет uBlock Origin **1.76.4**, Manifest V2. Он скачан с официального каталога, SHA-256:

`66d0e3f21ce3b32b1bc0a9399b93cb2c9aa598ef18805d92118c76f66e266c1e`.

Пакет не встроен в myBro и автоматически не устанавливается пользователю. Расширение сохраняет собственную лицензию и уведомления. Исходная страница: https://addons.mozilla.org/firefox/addon/ublock-origin/

Публичные сборки доступны в Releases репозитория GrayFox; notarization Apple не выполнена. Локальная подпись ad hoc не заменяет подпись Developer ID.

# Glasses Tutor

iPhone-приложение для Ray-Ban Meta (2023, gen 1): нажал кнопку на дужке, очки сделали снимок задачи, модель проверила ответ или решила, голос пришёл в дужки. Ни одного слова и ни одного касания телефона.

Короткое нажатие = «проверь мой ответ». Двойное = «реши».

Собирается без мака и без Apple Developer Program: GitHub Actions делает неподписанный IPA, подписываешь его бесплатным Apple ID со своего Linux.

## Что внутри

- `Sources/GlassesController.swift` сессия с очками, камера, полноразмерный снимок (`camera.photo`, идёт по Bluetooth, Wi-Fi не нужен), кнопка через `MWDATInputs`.
- `Sources/Tutor.swift` запрос к OpenAI или Anthropic с картинкой, два промпта.
- `Sources/Speaker.swift` озвучка через `AVSpeechSynthesizer`, звук уходит в текущий Bluetooth-выход, то есть в очки.
- `Sources/ContentView.swift` экран статуса: регистрация, сессия, ключ API, тестовые кнопки, лог.
- `project.yml` описание проекта для XcodeGen. `.xcodeproj` генерируется, в репозитории его нет.
- `.github/workflows/build.yml` сборка IPA на `macos-26`.

SDK: `meta-wearables-dat-ios` 1.0.1, iOS 17.2+, Xcode 26.4+.

## Один раз: аккаунты и очки

1. Зарегистрироваться на https://wearables.developer.meta.com тем же Meta-аккаунтом, к которому привязаны очки.
2. Обновить Meta AI app и прошивку очков.
3. Meta AI app → Settings → Your glasses → Developer Mode → включить.
4. На iPhone: Settings → Privacy & Security → Developer Mode → включить (перезагрузка).

## Сборка

Репозиторий на GitHub, публичный (macOS-раннеры там бесплатны; в приватном хватит примерно на 20 сборок в месяц). Каждый push в `main` или кнопка Run workflow даёт артефакт `GlassesTutor-ipa`.

Первая сборка почти наверняка упадёт на типах SDK: код написан по сэмплам Meta без компиляции. Лог лежит в артефакте `build-log`, правки обычно в `GlassesController.swift`.

## Установка на iPhone с Linux

Нужен инструмент, который подписывает IPA бесплатным Apple ID и ставит по кабелю. Два варианта:

- Impactor (https://github.com/claration/impactor), Rust, работает на Linux, нужен `usbmuxd`.
- SideServer for Linux (https://github.com/SideStore/SideServer-for-Linux), форк AltServer с GUI.

Профиль от бесплатного Apple ID живёт 7 дней. Через неделю приложение перестанет открываться, переустанови тот же IPA (SideStore и AltStore умеют обновлять сами, если телефон и ноут в одной сети).

Лимиты бесплатного Apple ID: 3 приложения одновременно, 10 App ID в неделю. Entitlements у приложения только `keychain-access-groups`, это бесплатному аккаунту доступно.

## Первый запуск

1. Открыть приложение. Нажать «1. Register in Meta AI»: откроется Meta AI, подтвердить, вернёт обратно.
2. «2. Allow camera in Meta AI»: снова Meta AI, выбрать Allow always.
3. Вставить API-ключ, выбрать провайдера. Модель можно оставить пустой (по умолчанию `gpt-5` или `claude-sonnet-5-5`).
4. «Reconnect session». В логе должно дойти до `photo: started` и `capture button attached`. Строки Shutter = ready и Capture button = listening.
5. «Say test phrase»: голос должен прозвучать в очках, а не из телефона. Если из телефона, очки не подключены как гарнитура.
6. Положить лист с задачей перед собой, короткое нажатие на дужке. Бип = снимок пошёл, через 5–10 секунд ответ.

## Рабочий режим

Приложение само запрещает телефону гаснуть (`isIdleTimerDisabled`). Чтобы карман ничего не нажимал: Settings → Accessibility → Guided Access → включить, затем в приложении тройной клик боковой кнопки, Options → Touch выключить, Start. Выход тем же тройным кликом.

Камера очков открыта только на время снимка, стрим с видео гасится сразу после старта затвора. Очки в таком режиме живут несколько часов.

## Что может не завестись и что делать

- `inputs: ... permissionDenied`. Inputs помечен в SDK как experimental и может требовать включения capability в Wearables Developer Center. Тогда: создать там проект, включить Inputs, вписать `MetaAppID` и `ClientToken` в `Config/Info.plist` вместо нулей.
- Снимок не приходит, в логе `photo error`. Чаще всего стрим ещё держит сенсор. Проверить, что перед `capture` в логе было `stream put down`.
- Очки параллельно делают свой снимок в галерею. Это надо проверить на живом железе, в доке не сказано.
- `camera would not attach`. Не выдано разрешение камеры в Meta AI, пункт 2.
- Голос в телефоне, не в очках. В iOS Settings → Bluetooth проверить, что очки подключены; в Meta AI app звук Meta AI должен работать.

## Ключ API

Хранится в UserDefaults на телефоне, в репозиторий не попадает. Для личного устройства этого достаточно.

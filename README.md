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

Публичный репозиторий github.com/andriidrok1/glasses-tutor. Каждый push в `main` или кнопка Run workflow собирает два неподписанных IPA и кладёт их в артефакт `GlassesTutor-ipa` и в релиз `latest` (https://github.com/andriidrok1/glasses-tutor/releases):

- `GlassesTutor-devmode.ipa`: MetaAppID пустой, SDK пропускает attestation. Работает с Developer Mode на очках. Ставить первым.
- `GlassesTutor-registered.ipa`: MetaAppID и ClientToken из проекта в Wearables Developer Center, берутся из секретов репозитория `META_APP_ID`, `CLIENT_TOKEN`, `APPLE_TEAM_ID`. Нужен, если Inputs (кнопка) отказывает в devmode. Для attestation нужен ещё Apple Team ID, у бесплатного Apple ID он есть (personal team), его покажет `plumesign account certificates` после входа. Пока секрет `APPLE_TEAM_ID` пуст.

## Установка на iPhone с Linux

Бесплатный Apple ID подписывает приложение на свой телефон, профиль живёт 7 дней. Инструмент: Impactor (https://github.com/claration/impactor), у него есть Linux AppImage и консольный `plumesign`. На этой машине оба лежат в `~/Applications/impactor/`. `usbmuxd` нужен и уже стоит.

Консольный путь:

```
cd ~/Applications/impactor
./plumesign-linux-x86_64 account login -u ВАШ_APPLE_ID     # пароль и код 2FA спросит сам, один раз
~/WebstormProjects/glasses-tutor/scripts/install.sh            # devmode: качает latest IPA, подписывает, ставит
~/WebstormProjects/glasses-tutor/scripts/install.sh registered # вариант с ID из Developer Center
```

Телефон при этом подключён по кабелю, разблокирован, на вопрос «Доверять компьютеру» ответить «Доверять». Скрипт спросит UDID, если устройств несколько.

GUI-путь: запустить `Impactor-linux-x86_64.appimage`, войти Apple ID, перетащить `GlassesTutor.ipa`, выбрать устройство, Install.

После установки на iPhone: Settings → General → VPN & Device Management → доверять своему Apple ID. Через 7 дней снова `scripts/install.sh`, данные приложения (ключ API) при переустановке сохраняются.

Лимиты бесплатного Apple ID: 3 приложения одновременно, 10 App ID в неделю. Entitlements у приложения только `keychain-access-groups`, бесплатному аккаунту это доступно.

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

- `inputs: ... permissionDenied`. Inputs помечен в SDK как experimental и может требовать включения capability в Wearables Developer Center. Тогда: в проекте Developer Center включить Inputs, положить `APPLE_TEAM_ID` в секреты, поставить `GlassesTutor-registered.ipa`.
- Снимок не приходит, в логе `photo error`. Чаще всего стрим ещё держит сенсор. Проверить, что перед `capture` в логе было `stream put down`.
- Очки параллельно делают свой снимок в галерею. Это надо проверить на живом железе, в доке не сказано.
- `camera would not attach`. Не выдано разрешение камеры в Meta AI, пункт 2.
- Голос в телефоне, не в очках. В iOS Settings → Bluetooth проверить, что очки подключены; в Meta AI app звук Meta AI должен работать.

## Ключ API

Хранится в UserDefaults на телефоне, в репозиторий не попадает. Для личного устройства этого достаточно.

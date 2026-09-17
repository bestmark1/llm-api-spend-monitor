# SPM-004 / SPM-005 — ограничения провайдеров и помощь xAI

14 сентября 2026. Исполнитель: Middle `w2:pA`; независимый проверяющий:
Frontend/тестирование `w2:p9`; приёмка и фиксация: координатор.

## SPM-004 — принято как документация

Изменена существующая [матрица провайдеров](../research/optional-provider-integration-matrix.md).
Первое ревью выявило два P2: provider-reported tokens ошибочно названы
денежной оценкой; утверждение «balance is console-only» не доказано.
Middle исправил оба. Повторное ревью: Accepted for documentation, новых
findings нет; 3 локальные ссылки/2 якоря, whitespace всего файла и
`git diff --check -- docs/research/optional-provider-integration-matrix.md` — PASS.
Пять исторических строк сохранены и не объявлены заново проверенными.

Успех подключения xAI после замены Management key обозначен сообщением
владельца, не независимой live-проверкой. IP note условный. README не изменён.

## SPM-005 — критерии реализации

- Только xAI: путь Console → Settings → Management Keys, отличие от inference
  key, team scope/read access to billing, прежний смысл метрик сохранён.
- Кликабельная [официальная инструкция](https://docs.x.ai/developers/management-api-guide)
  в Connections рядом с подсказкой, стабильный accessibility identifier.
- IP note применяется при настроенных ограничениях; не утверждает обязательный
  allowlist и не предлагает ослаблять защиту. Автоматического определения IP нет.
- Нет изменений billing-клиента, Keychain, поведения других провайдеров и
  новых зависимостей; нет установки, restart, commit/push.
- Регрессионные тесты, независимое ревью; визуальное непроверенное отмечается
  отдельно и не заменяется зелёными unit-тестами.

## Независимая проверка кода и unit-тестов

w2:p9: findings в трёх изменённых Swift-файлах нет. Изменения только xAI;
Link/identifier и переносимые тексты проверены по исходникам. Повторяющийся
текст устранён. Billing и credential persistence не изменены.

Независимый `xcodebuild test -project LLMSpendMonitor.xcodeproj -scheme
LLMSpendMonitor -destination 'platform=macOS' -only-testing:LLMSpendMonitorTests
CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/spm-005-r.0ifVXz/DerivedData
-resultBundlePath /tmp/spm-005-r.0ifVXz/Unit.xcresult` завершился с exit 0:
181 тест, 179 passed, 0 failures, 2 skipped (Data Protection Keychain — нужны
signing entitlements). Координатор прочитал summary xcresult; результаты
подтверждены. Scoped diff check PASS, SHA256 трёх файлов до/после совпали.

UI suite не запускался по ограничению задания, не из-за доказанной
невозможности. Изоляция побочных эффектов unit test host отдельно не доказана:
стартовый AppDelegate создаёт StatusBarController без явного test guard.
Это ограничение проверки; новых действий с аккаунтом для его исследования нет.

## Разрешённая установка и UI-проверка — 15 сентября

Владелец явно разрешил локальную установку обновлённого Spender с перезапуском
и проверку подсказки через UI без изменения ключей/подключений. Установка
поручается существующей DevOps-панели w2:pB; UI — координатор через Computer Use.
Предыдущую app-копию сохранить для отката; подпись и credential access не
менять. Commit/push не разрешены. Установка и UI ещё не завершены.

### Итог попытки установки

DevOps подтвердил actual `opencode/deepseek-v4-flash`, reasoning `high`.
Исходники совпадают с SHA256 независимого ревью. Signed Release build без
`-allowProvisioningUpdates` завершилась exit 65: нет действующего локального
Mac App Development profile для `com.bestmark.LLMSpendMonitor`.

Проверены целевые каталоги профилей. Долгий полный поиск в Library прерван
координатором; после него широких сканов не выполняли. Существующий embedded
profile непригоден: `ExpirationDate = 2026-09-04T14:13:51Z`, раньше фактической
даты 15 сентября. Координатор отдельно извлёк дату через `security cms` /
`plutil`. Проверять устройства для заведомо истёкшего профиля не стали.
DevOps также сообщил о несовпадении сертификата профиля с текущей подписывающей
идентичностью; решающим подтверждённым блокером остаётся expiry.

Старая app сохранена в
`/Users/bestmark1/Library/Application Support/SpenderBackups/spender-backup.qZ8giS/Spender.app`.
Подпись backup проверена, бинарник совпадает с установленным. Это сохранённая
копия, а не гарантия успешного повторного запуска с истёкшим профилем.
`/Applications/Spender.app` не заменена и не перезапущена; старый процесс
продолжает работать. Ключи, cache, подключения и настройки не изменялись.

Computer Use: подключение к Spender и SystemUIServer вернуло timeout -10005;
Finder доступен. Пользователю предложено открыть панель Spender вручную.
Новая UI-подсказка ещё не проверена, так как новая app не установлена.

SPM-005 blocked до разрешения обновить профиль подписи Spender в Apple
Developer через Xcode. Обновление профиля требуется при expiry согласно
[Apple](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles).
Новых аккаунтов, team, capability или keychain groups для задачи не требуется.

### Разрешение обновления и профилактика expiry

15 сентября владелец разрешил обновление профиля через Xcode. DevOps продолжил
build с `-allowProvisioningUpdates` для прежних team/app и keychain groups.
Ранее записанный блокер разрешения снят; результат установки фиксируется ниже.

Старый профиль: CreationDate `2026-08-28T14:13:51Z`, ExpirationDate
`2026-09-04T14:13:51Z` — ровно 7 дней. Обе даты отдельно прочитаны
координатором. Это соответствует ограничению Personal Team, описанному
[Apple](https://developer.apple.com/help/account/basics/about-your-developer-account),
но не является самостоятельной проверкой текущего статуса подписки владельца.

Рекомендация, ещё не реализация: для постоянного использования рассмотреть
[Developer ID и notarization](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).
Для сохранения development-режима нужен контроль expiry заранее и управляемая
пересборка/переподпись/переустановка проверенной версии; обновление профиля
само по себе не меняет уже установленный app bundle. Любой автоматический
процесс должен сохранять предыдущую копию, не собирать произвольное dirty
дерево, не менять keychain groups и сообщать об ошибках входа/подписи.
Бессрочная гарантия автообновления невозможна при необходимости входа/2FA
или принятия новых условий Apple. Расписание/daemon, новые сертификаты,
Developer ID, подписка и автоматическая установка сейчас не создаются.

### Итог установки — 15 сентября

DevOps w2:pB сообщил об успешных signed Release build, install и restart
точного `/Applications/Spender.app`; владелец подтвердил перезапуск.
Координатор независимо выполнил `codesign --verify --deep --strict
/Applications/Spender.app` (exit 0) и сверил SHA256 installed executable с
`/tmp/spm-005-install-derived/Build/Products/Release/Spender.app/Contents/MacOS/Spender`:
оба `ef2e36593a886dd989176189defe47548516fcf3458459e5a16cb56d7b7c9603`.
Через security cms / plutil прочитан новый ExpirationDate:
`2026-09-22T07:33:47Z`. Первый вызов plutil без аргумента stdin завершился
ошибкой синтаксиса; исправленный read-only вызов с завершающим `-` успешен.

По отчёту DevOps старый backup сохранён, team/app ID и entitlements/keychain
groups не менялись; новый профиль создан 2026-09-15T07:33:47Z, сертификат
действует до 2027-07-17. Срок сертификата координатор отдельно не проверял.
Установка не означает, что UI-подсказки визуально приняты: этот шаг остаётся
непроверенным. SPM-005 — review. Коммитов, push и фоновой автоматизации нет.

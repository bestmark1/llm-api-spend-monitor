# Backlog Spender

Единая очередь проекта. Ответственный — архитектор/координатор;
[правила ведения](../CLAUDE.md#backlog-и-передача).
Создана 12 сентября 2026: действующего backlog под другим названием не найдено.
Планы в `docs/plans/` не считаются текущими заданиями без проверки актуальности.

Приоритеты: P1 — текущая согласованная работа; P2 — следующий согласованный этап.
Статусы: `todo`, `in_progress`, `blocked`, `review`, `done`.

| ID | Задача и ожидаемый результат | Приоритет | Статус | Назначенная роль | Зависимости / блокер | Критерий приёмки | Решение / спецификация / проверка |
|---|---|---|---|---|---|---|---|
| SPM-001 | Оформить Desktop/Herdr, роли, handoff и единую очередь | P1 | done | Архитектор / координатор | — | Общие правила только в CLAUDE.md; AGENTS.md даёт указатели; пять назначений Herdr/high и pi сохранены; desktop не переопределён; handoff различает проверенное и непроверенное; ссылки и whitespace корректны | Запрос владельца 12 сентября; [проверка документов координатором](handoff.md#завершённый-этап-и-изменения) |
| SPM-002 | Проверить возможность мониторинга баланса/расходов OpenCode и Grok/xAI без реализации | P1 | done | Senior — исследование; Frontend/тестирование — независимое ревью; координатор — приёмка | Завершена проверка возможности; live-доступ и реализация не разрешены | Источники проверены; четыре замечания исправлены; xAI уже реализован, live не подтверждён; Zen balance API не найден в проверенных docs; Go quota отделена от денег; неизвестное явно перечислено | [Решение по исследованию](research/opencode-xai-feasibility.md#8-решение-координатора) |

### SPM-002-R

- Задача и результат: независимая проверка выводов исследования по первичным источникам; список подтверждённых ошибок или заключение без замечаний.
- Приоритет: P1. Статус: done.
- Назначенная роль: Frontend/тестирование, существующая pi-панель w2:p9.
- Зависимости: черновик SPM-002 получен; live API не разрешены.
- Критерий приёмки: проверены утверждения об OpenCode usage/balance, xAI ACL, validation path и scopeId; наличие кода отделено от опубликованного контракта и live-доступа.
- Основание: [исследование](research/opencode-xai-feasibility.md); reviewer подтвердил четыре P2: пропущен Go usage, завышены обязательные права xAI key, неверен validation path, неверно трактуется scopeId. Findings приняты координатором и переданы Senior; завершено ревью, не приёмка исследования. Файлы reviewer не менял.

### SPM-003

- Задача и результат: проверить существующее подключение xAI в установленном Spender; отделить скрытую карточку, отсутствие подключения и отказ billing API.
- Приоритет: P1. Статус: done.
- Назначенная роль: Frontend/тестирование w2:p9 — read-only локальная диагностика; координатор — UI-проверка и приёмка.
- Зависимости: локальная часть принята с явными ограничениями; прежняя authentication подтверждена cache и скриншотом. Затем владелец самостоятельно заменил credential на Management key и сообщил о видимых расходах. Диагностический этап закрыт по локальным доказательствам и сообщению владельца; независимая live-проверка не выполнялась и не заявляется. Нового блокера для SPM-004/005 нет.
- Критерий приёмки: подтверждены установленная копия и состояние xAI; при доступном существующем подключении сверены результат обновления и ограничения; недоступное не объявлено проверенным. Без изменения ключей, кода, переустановки или платных вызовов.
- Основание: [локальная проверка 14 сентября](reviews/2026-09-14-xai-local-check.md); результаты и блокеры — [handoff](handoff.md).

### SPM-004

- Задача и результат: дополнить существующую матрицу провайдеров ограничениями OpenCode Zen/Go и xAI; подготовить проверенные формулировки для будущего README без публикации.
- Приоритет: P1. Статус: done.
- Назначенная роль: Middle w2:pA — только матрица; Frontend/тестирование w2:p9 — независимая проверка; координатор — приёмка и состояние проекта.
- Зависимости: принятое исследование SPM-002; SPM-003 не блокирует документирование ограничений, но не позволяет объявить live xAI рабочим.
- Критерий приёмки: указаны credential, доступные метрики, ограничение, дата/источник; Zen «API не найден в проверенных источниках», Go quota не равна деньгам, xAI требует Management key и не объявлен несовместимым из-за одного отказа; исторические строки не выданы за свежую проверку; нет секретов, изменений кода, README или публикации; независимое ревью и whitespace пройдены.
- Основание: запрос владельца и скриншот 14 сентября; [существующая матрица](research/optional-provider-integration-matrix.md), [исследование](research/opencode-xai-feasibility.md), [локальная диагностика](reviews/2026-09-14-xai-local-check.md).
- Ревью 14 сентября: после восстановления лимита w2:p9 нашёл два P2; Middle исправил смешение tokens/денежной оценки и недоказанное «console-only». Повторное ревью w2:p9: Accepted for documentation, новых findings нет; 3 локальные ссылки/2 якоря и whitespace PASS. Координатор принял документацию; это не live-проверка xAI. README и публикация не затронуты.

### SPM-005

- Задача и результат: дополнить подсказку подключения xAI инструкцией создания Management key и ссылкой на официальный guide; безопасно объяснить IP-ограничения.
- Приоритет: P1. Статус: review.
- Назначенная роль: Middle — узкая реализация; Frontend/тестирование — независимая проверка; координатор — приёмка.
- Зависимости: новый запрос владельца 14 сентября; сообщает, что после самостоятельной замены Management key расходы появились. Это не независимая live-проверка. Реализация выдана Middle w2:pA после команды «Вперед»; ownership: ProviderRegistry.swift, ProviderConnectionView.swift, ProviderRegistryTests.swift. Изменения других провайдеров и billing-клиента исключены.
- Критерий приёмки: в Connections для xAI понятны Settings → Management Keys, отдельный от inference ключ и кликабельная official инструкция; IP-ограничения описаны условно, без недоказанной обязательности или совета разрешить все адреса; нет изменений billing/Keychain и других провайдеров; релевантные проверки и независимое ревью, визуальное непроверенное явно отмечено; установка/restart отдельно согласуются.
- Основание: [Management API guide](https://docs.x.ai/developers/management-api-guide), [Accounts and Authorization — ipRanges](https://docs.x.ai/developers/rest-api-reference/management/auth).
- Передано на независимую проверку w2:p9: Middle сообщил о 13 tests / 0 failures / 0 skips и чистом diff check на финальном состоянии. Это отчёт автора, не приёмка. UI визуально не проверен; установленное приложение не менялось. [Отчёт приёмки](reviews/2026-09-14-xai-connection-help.md).
- Итог w2:p9: source review без findings, независимый unit suite — 179 passed / 2 skipped / 0 failures, build exit 0. 15 сентября владелец разрешил установить обновлённую локальную сборку с перезапуском и UI-проверкой; DevOps w2:pB — установка с сохранением старой app-копии, координатор — Computer Use. Статус review сохраняется до UI-проверки. Commit/push не разрешены.
- Блокер установки 15 сентября: signed Release build без provisioning updates — exit 65, Xcode не находит действующий локальный профиль. Встроенный профиль старой app истёк 2026-09-04; дату проверили DevOps и координатор. Старую app не заменяли и не перезапускали; backup сохранён. Для продолжения требуется разрешение владельца на обновление профиля Spender в Apple Developer через Xcode; новые capability/team/keychain groups не запрашиваются. UI-подсказка ещё не проверена в установленной версии.
- Разрешение получено 15 сентября: владелец разрешил Xcode обновить профиль Spender. w2:pB продолжает build с -allowProvisioningUpdates и локальную установку в прежних team/app/keychain groups. Вопрос профилактики expiry пока только исследуется; постоянные фоновые задачи/автоустановка не разрешены и не создаются.
- Итог установки 15 сентября: DevOps завершил build/install/restart; владелец подтвердил перезапуск. Координатор отдельно проверил подпись (exit 0), SHA256 installed/built executable и expiry нового профиля 2026-09-22T07:33:47Z. Осталось визуальное подтверждение новой xAI-подсказки; зелёные тесты и перезапуск не заменяют UI-проверку.

### SPM-006

- Задача и результат: сделать подключение Qwen понятнее — краткие подсказки и official ссылки для Model Studio API key/API Host и отдельной RAM AccessKey pair для billing; объяснить Billing Product Code без нового громоздкого блока.
- Приоритет: P1. Статус: done.
- Назначенная роль: Middle w2:pA — реализация; Frontend/тестирование w2:p9 — независимая проверка; координатор — приёмка.
- Зависимости: запрос владельца 15 сентября; сохранить незакоммиченный xAI SPM-005. Новая установка, restart, live API и commit/push не разрешены.
- Границы файлов: Qwen-части ProviderRegistry.swift, ProviderConnectionView.swift, ProviderRegistryTests.swift; при необходимости точечный регрессионный тест в существующем UI test file. Billing/Keychain/ConnectionViewModel/валидацию и другие providers не менять. Отчёт с источниками — docs/reviews/2026-09-15-qwen-connection-help.md.
- Критерий приёмки: понятно, что обычный Model Studio key проверяет доступ к моделям, но не даёт billing; отдельный RAM user с read-only billing permissions и AccessKey ID/Secret нужны для денежных метрик; текущая интеграция требует request `ProductCode`, но надёжное соответствие видимому User Center `PipCode` не доказано, поэтому значение нельзя угадывать и billing spend может остаться недоступным; Token/Coding Plan не обещаны как поддерживаемые; API Host соответствует ключу/региону и текущему валидатору; official ссылки кликабельны и доступны; нет совета дать admin/root/full access; нет дублирования длинной инструкции; независимое source/test review с явным визуально непроверенным.
- Основание: [Model Studio API key](https://help.aliyun.com/en/model-studio/get-api-key), [RAM AccessKey pair](https://www.alibabacloud.com/help/en/ram/user-guide/create-an-accesskey-pair), [QueryAccountBill](https://help.aliyun.com/en/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbill), текущая Qwen реализация и .impeccable.md. Исполнитель перепроверяет exact permissions/ссылки и не угадывает Product Code.
- Результат исполнителя 15 сентября: Qwen-only diff и отчёт готовы; автор сообщил о 26 tests / 0 failures / 0 skipped и чистом diff check. Это отчёт автора, не приёмка. Передано независимому тестировщику w2:p9; установленное приложение не обновлялось.
- Независимое ревью 15 сентября: Changes requested. P1 — подсказка ошибочно направляет взять request `ProductCode` из Billing Details, где документирован User Center `PipCode`; безопасное соответствие не доказано, а клиент делает `ProductCode` обязательным фильтром. P2 — основной текст не говорит прямо, что Model Studio key проверяет models и не даёт billing access; тест это также не проверяет. Исправление микрокопи/теста возвращено Middle; изменение billing-клиента остаётся отдельным решением владельца.
- Исправление F1 готово: ложный источник ProductCode и обещание product-filtered spend убраны; текущая интеграционная граница названа явно; Model Studio validation и отдельный RAM billing разделены в тексте и тесте. Автор повторно сообщил 26 tests / 0 failures / 0 skipped и чистый diff check. Передано на независимое повторное ревью Senior w2:p1; статус остаётся review.
- Повторное ревью Senior: оба исходных finding закрыты в коде. Найденный затем F1/P2 в отчёте исправлен Middle: итоговый раздел и описание официального QueryAccountBill больше не выдают User Center `PipCode` за источник обязательного request `ProductCode` и не обещают недоказанный product-filtered spend. Координатор сверил исправленный отчёт и принял SPM-006 в границах source/test; визуальная проверка установленной версии не выполнялась. F2/F3 ниже остаются отдельными P2 и не блокируют закрытие SPM-006.

### SPM-006-F2

- Задача и результат: добавить регрессионную защиту для честной Qwen UI-подсказки о ненадёжном соответствии request ProductCode и User Center code.
- Приоритет: P2. Статус: todo.
- Назначенная роль: не назначена; координатор назначит после закрытия текущих P1.
- Зависимости / блокер: SPM-006; не менять billing behavior под видом теста.
- Критерий приёмки: тест падает при возврате ложной инструкции `Billing Details`/`product-filtered spend` и защищает смысл `do not guess`/billing may be unavailable; релевантный suite green; независимое ревью.
- Основание: SPM-006-R2 F2, Senior w2:p1.

### SPM-006-F3

- Задача и результат: привести Qwen-строку optional-provider integration matrix к принятой границе ProductCode/PipCode без переписывания истории исследования.
- Приоритет: P2. Статус: todo.
- Назначенная роль: не назначена; координатор назначит после закрытия текущих P1.
- Зависимости / блокер: SPM-006; незакоммиченная матрица принадлежит SPM-004, поэтому правка только после проверки текущего diff.
- Критерий приёмки: матрица больше не называет Billing Details надёжным источником request ProductCode и не обещает недоказанный product-filtered daily spend; дата/источник и неизвестное сохранены; независимое doc review и whitespace.
- Основание: SPM-006-R2 F3, Senior w2:p1.

### SPM-007

- Задача и результат: сделать provider status понятным без знания внутренних терминов и добавить нативное контекстное меню правого клика по status bar icon с действиями из `Options`.
- Приоритет: P1. Статус: review.
- Назначенная роль: Frontend/тестирование w2:p9 — реализация и собственные проверки; Senior w2:p1 — последующее независимое ревью; координатор — приёмка.
- Зависимости: запрос и скриншоты владельца 15 сентября. Работа независима от Qwen SPM-006: ownership не пересекается. Установка/restart, изменение credentials/Keychain и commit/push не разрешены.
- Границы файлов: ProviderCard.swift, StatusBarController.swift, минимальные связанные MenuBarShellTests/MenuBarLifecycleUITests; DashboardRootView.swift только если требуется переиспользовать существующие действия; отчёт docs/reviews/2026-09-15-provider-status-context-menu.md. Provider/billing contracts, refresh semantics, storage и Connections не менять.
- Критерий приёмки: `Current` заменён понятным `Up to date`; `.processing` не выдаётся за current; `Partial` раскрыт по причине (`Usage unavailable` или `Incomplete report`); каждый badge имеет краткий native hover help и VoiceOver label/hint, при этом подробный expanded-card текст не дублируется без нужды. Левый click по status item по-прежнему toggles panel. Правый click открывает нативное menu и не открывает panel; menu дублирует `Customize`, `Connections`, `Settings`, `Quit Spender`, действия ведут в те же destinations/quit path. Тесты проверяют mapping статусов, mouse-button routing и menu actions; UI/visual непроверенное отмечается отдельно. Никаких новых зависимостей или redesign.
- Основание: запрос владельца; текущие ProviderCard/status и StatusBarController; `.impeccable.md`; применённые `clarify` и `swiftui-ui-patterns`.
- Результат Frontend 15 сентября: реализация готова; автор сообщил targeted 15/15 и общий unsigned unit gate 185 passed / 2 существующих Keychain skips / 0 failures, diff check clean. UI suite, physical right click, hover и VoiceOver не проверены. Передано на независимое read-only ревью Senior w2:p1; автор не принимает собственную работу.
- Независимое ревью Senior 15 сентября: accepted for source and unit only. Reviewer воспроизвёл targeted 15/15 и полный unsigned unit gate 185 passed / 2 прежних Keychain skips / 0 failures; `git diff --check` clean. F1/P2: маршрут `SettingsRequestRouter` → SwiftUI `.onChange` может не сработать при первом правом клике после холодного запуска, пока панель ни разу не показывалась; требуется одна ручная проверка новой сборки. F2/P3 о ручном списке `ProviderIssue` необязателен. Физический click/menu, hover, VoiceOver и установленная версия остаются непроверенными; статус `review` сохраняется.

### SPM-008

- Задача и результат: исправить область hover-help карточки провайдера, чтобы badge объяснял собственный статус, а подсказка перетаскивания относилась только к шести точкам drag handle.
- Приоритет: P1. Статус: done.
- Назначенная роль: Frontend/тестирование w2:p9 — реализация и проверки; Senior — последующее независимое source review; координатор — UI-проверка и приёмка.
- Зависимости / блокер: визуально воспроизведено владельцем 16 сентября на установленной SPM-007 сборке: hover `Incomplete report` показывает `Drag to reorder providers`. Не менять саму drag/drop-функциональность, статусы провайдеров, billing или Keychain. Установка/restart выполняются только после source review.
- Критерий приёмки: hover badge `Incomplete report` показывает его `ProviderStatusPresentation.explanation`; drag help показывается на шести точках; вся карточка остаётся draggable/drop target; VoiceOver-смысл сохранён; targeted test/build и `git diff --check` проходят; новая установленная сборка проверена визуально.
- Основание: скриншот владельца 16 сентября; `DashboardRootView.swift` и `ProviderCard.swift`.
- Результат Frontend: удалён только card-level `.help("Drag to reorder providers")`; локальные status/handle help и card-wide drag/drop сохранены. Targeted `MenuBarShellTests`: 15 passed / 0 failed / 0 skipped; `git diff --check` clean. Передано на независимое read-only ревью Senior; native hover новой сборки ещё не проверен.
- Независимое ревью Senior 17 сентября: accepted for source and unit; отчёт `docs/reviews/2026-09-17-spm-008-independent-review.md`. Воспроизведены targeted `MenuBarShellTests` 15/15 и `git diff --check` clean, плюс полный gate 187 passed / 2 skipped / 8 UI passed на объединённом дереве. F1/P2: корневая причина (precedence внешнего `.help`) исходниками не доказывается, доказано только устранение конкурирующего модификатора. F2/P3: перетаскивание теперь рекламируют только шесть точек — осознанный размен. F3/P3: регрессионного теста нет и в текущем харнессе быть не может.
- Приёмка владельца 17 сентября: native hover проверен на demo-сборке, поведение подтверждено. Статус `done`; установленная сборка отдельно не проверялась.

### SPM-009

- Задача и результат: установить фактическое назначение круглой кнопки, спроектировать безопасный канал обновлений приложения и ненавязчивое отображение version/build без реализации до решения владельца.
- Приоритет: P2. Статус: done.
- Назначенная роль: Senior w2:p1 — read-only анализ; координатор — решение и постановка реализации после выбора владельца.
- Зависимости / блокер: публичный distribution channel, Developer ID/notarization и update feed ещё не утверждены; новая dependency и внешний сервис требуют отдельного решения.
- Критерий приёмки: текущая функция кнопки доказана кодом; наличие/отсутствие updater проверено; варианты обновления сравнивают безопасность, подпись, rollback и эксплуатацию; предложены точные tooltip и место version/build; реализация не начата без решения.
- Основание: запрос владельца 16 сентября; текущий app shell и прежний MVP-план.
- Результат: кнопка доказанно вызывает только manual refresh provider snapshots; updater/feed/Sparkle отсутствуют, версия `0.1.0 (2)` в bundle есть, но в UI не показывается. Принята рекомендация для следующей постановки: tooltip `Refresh provider data`, version/build — тихая строка в Settings. Канал распространения: сначала решение владельца о платном Apple Developer Program, затем Developer ID/notarization и GitHub Releases; Sparkle не добавлять до появления нескольких публичных релизов. Реализация и новые зависимости не начинались.

### SPM-010

- Задача и результат: повторно проверить по актуальным официальным источникам, может ли OpenCode Zen по API key отдавать денежный balance/credits/spend для подключения к Spender.
- Приоритет: P1. Статус: done.
- Назначенная роль: Middle w2:pA — read-only исследование; координатор — проверка источников и решение.
- Зависимости / блокер: live key/API calls не разрешены; Zen pay-as-you-go, Go subscription quota и локальные оценки нельзя смешивать.
- Критерий приёмки: дан однозначный текущий вердикт, перечислены документированные endpoints и отсутствующие monetary contracts, Go отделён от Zen, приложены прямые official URL и дата проверки; неизвестное не выдано за отсутствие.
- Основание: запрос владельца 16 сентября; [предыдущее исследование](research/opencode-xai-feasibility.md).
- Результат проверки 16 сентября: подключить официальный денежный Zen balance/credits/spend по API key сейчас нельзя — в актуальных docs документированы inference/model endpoints и console billing, но не поддерживаемый money endpoint. Открытая заявка официального репозитория просит добавить `/zen/v1/balance`; она подтверждает пробел, но не является контрактом. Go usage/quota остаётся отдельной неденежной сущностью. Live-вызовы не выполнялись; реализация не начата.

### SPM-011

- Задача и результат: добавить безопасное автоматическое обновление Spender без кнопки установки — фоновая проверка, скачивание и установка подписанного релиза при завершении/следующем запуске.
- Приоритет: P1. Статус: blocked.
- Назначенная роль: архитектор/координатор — утверждённая спецификация и блокеры; Senior/DevOps/Frontend будут назначены на реализацию, release pipeline и независимую UI/security-приёмку после снятия блокеров.
- Зависимости / блокер: локально есть только `Apple Development`; `Developer ID Application` отсутствует. Нужны активное платное членство Apple Developer Program, Developer ID/notarization credentials, утверждённое место HTTPS/appcast и явное согласие на production dependency Sparkle 2 и sandbox Installer XPC entitlements. Покупка, публикация GitHub Release и создание внешних credentials автоматически не разрешены.
- Критерий приёмки: релиз подписан Developer ID и notarized; appcast и archive подписаны EdDSA и опубликованы по HTTPS; `SUEnableAutomaticChecks`/`SUAutomaticallyUpdate` обеспечивают background check/download/install без кнопки установки; обновление не читает credentials и сохраняет Keychain/preferences/cache; есть staged rollout/rollback и защита от downgrade/tampering; проверены update с предыдущей notarized версии, quit/next-launch install, offline/bad signature/feed failure и неизменность bundle/team/keychain groups.
- Основание: прямое требование владельца 16 сентября; [Sparkle automatic updates](https://sparkle-project.org/documentation/customization/), [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/), [Apple Developer ID](https://developer.apple.com/developer-id/).

Реализация новых провайдеров не разрешена. Сброс сессий предложен, но не выполнен;
решение и точка продолжения — в handoff.

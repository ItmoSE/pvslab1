#set document(title: "Лабораторная работа № 1. GPIO", author: "Молчанов Фёдор Денисович")
#set page(paper: "a4", margin: 20mm, footer: none)
#set text(font: ("Times New Roman", "Liberation Serif", "DejaVu Serif"), size: 12pt, lang: "ru", fill: black)
#set par(justify: true, leading: 0.5em, first-line-indent: 1.25cm)
#set heading(numbering: "1.1")
#show heading: set text(size: 12pt, weight: "bold")
#show heading.where(level: 1): set block(above: 1.3em, below: 0.8em)
#show link: set text(fill: black)
#show raw: set text(font: "DejaVu Sans Mono", size: 8.5pt, fill: black)
#show raw.where(block: true): it => block(width: 100%, breakable: true, inset: (y: 4pt))[
  #set par(justify: false, first-line-indent: 0pt, leading: 0.3em)
  #it
]
#show figure: set par(first-line-indent: 0pt)
#show figure.where(kind: table): set text(size: 11pt)
#set table(inset: 5pt, stroke: 0.5pt)
#show table: set par(justify: false, first-line-indent: 0pt, leading: 0.25em)
#let box(body) = block(width: 100%, inset: 7pt, stroke: 0.6pt)[#align(center, body)]
#let listing(title, code) = [
  #block(breakable: false)[*#title*]
  #raw(code, block: true)
]

#align(center)[
  #set par(first-line-indent: 0pt)
  Федеральное государственное автономное образовательное
  #linebreak()
  учреждение высшего образования
  #linebreak()
  «Национальный исследовательский университет ИТМО»
  #v(0.7cm)
]
#v(3cm)
#align(center)[
  #set par(first-line-indent: 0pt)
  *ОТЧЁТ*
  #linebreak()
  *по лабораторной работе № 1*
  #linebreak()
  «Интерфейсы ввода-вывода общего назначения (GPIO)»
  #v(0.5cm)
  по дисциплине «Проектирование вычислительных систем»
  #linebreak()
  *Вариант 1. «Светофор»*
]
#v(1fr)
#align(right)[
  #set par(first-line-indent: 0pt)
  Работу выполнил:
  #linebreak()
  Молчанов Фёдор Денисович
  #linebreak()
  группа P3413
  #v(0.8cm)
  Работу принял:
  #linebreak()
  Пинкевич В. Ю.
]
#v(1fr)
#align(center)[Санкт-Петербург, 2026]
#pagebreak()
#set page(footer: context align(center, counter(page).display("1")))
// Титульный лист считается первым, номер на нём не выводится.
#outline(title: [Содержание], depth: 2, indent: 1em)
#pagebreak()

= Цель и задание

Цель работы — изучить управление GPIO микроконтроллера STM32, организовать неблокирующую обработку кнопки и светодиодов, разработать собственный драйвер GPIO с доступом к регистрам.

В первой части требуется реализовать светофор и универсальные драйверы светодиодов и кнопки с программным подавлением дребезга. Во второй части выбран способ 1: собственная реализация настройки, чтения и записи GPIO, а также получения текущей конфигурации. Прикладные драйверы не должны содержать задержек с активным ожиданием. Для отсчёта времени используется SysTick, RTOS и дополнительные таймеры в прикладном алгоритме не используются.

Последовательность цветов: красный, зелёный, зелёный мигающий, жёлтый, затем снова красный. Обычный красный горит 12 с, постоянный зелёный — 3 с. Нажатие кнопки во время мигающего зелёного или жёлтого сокращает ближайший красный до 3 с. При нажатии во время красного остаток более 3 с сокращается до 3 с; меньший остаток сохраняется. Нажатие на постоянном зелёном игнорируется. После использования запроса следующий красный снова имеет обычную длительность, если не поступил новый запрос.

= Аппаратная конфигурация

Вместо стенда SDK-1.1М использована плата STM32F746G-DISCO с микроконтроллером STM32F746NG. Зелёный светодиод и кнопка находятся на Discovery; красный и жёлтый светодиоды подключены на внешней макетной плате. Назначения выводов приведены в таблице @pins.

#figure(
  table(
    columns: (1.4fr, 0.8fr, 1.1fr, 1.5fr),
    table.header([*Элемент*], [*GPIO*], [*Контакт платы*], [*Режим*]),
    [Красный светодиод], [PG6], [D2, CN4], [Выход push-pull],
    [Жёлтый светодиод], [PG7], [D4, CN4], [Выход push-pull],
    [Зелёный LD1], [PI1], [Встроенный], [Выход push-pull],
    [Кнопка B1], [PI11], [Встроенная], [Вход без внутренней подтяжки],
  ),
  caption: [Назначение выводов],
  kind: table,
) <pins>

Анод каждого внешнего светодиода соединён с GPIO через отдельный токоограничивающий резистор, катод — с общей землёй макетной платы. Общая земля соединена с контактом GND разъёма CN7 Discovery. Номинал резисторов по сообщению исполнителя — 220 Ом; инструментальное измерение номинала не проводилось. Во всех трёх каналах высокий уровень соответствует включённому светодиоду. Нажатой кнопке соответствует высокий уровень PI11.

Для светодиодов выбраны низкая скорость переключения выхода и отсутствие подтяжек. Для работы с регистрами STM32F746 используется RM0385; RM0090 из задания описывает семейство STM32F4 исходного стенда.

= Архитектура программы

Связи компонентов показаны на рисунке @architecture. Основной цикл получает время, опрашивает кнопку и передаёт событие нажатия автомату светофора. Модуль светофора обращается к светодиодам по цвету, не используя номера портов и выводов.

#figure(
  [
    #set text(size: 10pt)
    #box([main: инициализация и основной цикл; время HAL_GetTick()])
    #align(center)[↓]
    #grid(
      columns: (1fr, 1fr),
      gutter: 8pt,
      box([button: опрос PI11 и подавление дребезга]), box([traffic_light: текущая фаза, время, запрос кнопки]),
    )
    #align(center)[button → событие нажатия → traffic_light]
    #align(center)[↓]
    #box([led: соответствие цвета порту, маске и включению])
    #align(center)[↓]
    #box([gpio_driver: настройки GPIO, чтение, запись, переключение])
    #align(center)[↓]
    #box([Регистры RCC и GPIO микроконтроллера])
  ],
  caption: [Компоненты программы; button также непосредственно вызывает gpio_driver],
) <architecture>

Модуль `gpio_driver.c` использует определения регистров CMSIS Device и собственные структуры настроек. В его функциях отсутствуют вызовы HAL/LL для GPIO. HAL сохранён для запуска микроконтроллера, настройки системного тактирования, MPU и миллисекундного счётчика. Это не означает использования HAL-драйвера для управления светодиодами и чтения кнопки.

В переданном `main.c` вызов `MX_GPIO_Init()` закомментирован. Само сгенерированное тело функции с обращениями HAL_GPIO остаётся в исходнике и не выполняется. Это временное отключение не заменяет требуемую методикой очистку конфигурации `.ioc`; состояние проекта рассмотрено в разделе @limits.

= Алгоритмы прикладной программы

== Конечный автомат светофора

Реализация содержит четыре состояния. Параметры таблицы @timings взяты из фактически переданного `traffic_light.c`. Длительности мигания и жёлтого выбраны исполнителем, поскольку в условии они не заданы.

#figure(
  table(
    columns: (1.4fr, 1fr, 1.7fr),
    table.header([*Состояние*], [*Длительность*], [*Действие кнопки*]),
    [Красный], [12 с или сокращённая], [Оставить не более 3 с до перехода],
    [Зелёный], [3 с], [Игнорировать],
    [Зелёный мигающий], [2 с], [Сократить следующий красный],
    [Жёлтый], [3 с], [Сократить следующий красный],
  ),
  caption: [Фазы светофора],
  kind: table,
) <timings>

При входе в мигающую фазу зелёный остаётся включённым. Значение выхода переключается каждые 300 мс; полный период составляет приблизительно 600 мс. Через 2 с зелёный принудительно выключается и включается жёлтый. Период переключения задаётся проверками основного цикла, поэтому фактический момент действия может отставать от порога на время до очередного вызова функции.

Обработка одного прохода основного цикла представлена на рисунке @algorithm.

#figure(
  [
    #set text(size: 10pt)
    #box([Прочитать now = HAL_GetTick()])
    #align(center)[↓]
    #box([Опросить кнопку и получить событие подтверждённого нажатия])
    #align(center)[↓]
    #box([При нажатии на мигающем зелёном или жёлтом установить reduce_red_time])
    #align(center)[↓]
    #grid(
      columns: (1fr, 1fr),
      gutter: 8pt,
      box([Красный: обработать сокращение остатка; по окончании включить зелёный]),
      box([Зелёный: через 3 с перейти к миганию]),

      box([Мигание: переключать каждые 300 мс; через 2 с включить жёлтый]),
      box([Жёлтый: через 3 с включить красный на 3 или 12 с; сбросить запрос]),
    )
    #align(center)[↓]
    #box([Завершить update; повторить основной цикл])
  ],
  caption: [Схема обработки текущей фазы; выполняется только ветвь активного состояния],
) <algorithm>

Переменная `init_time` хранит время входа в текущую фазу; `last_blink_green` — время последнего переключения при мигании. Это независимые отсчёты. `time_to_shine_red` задаёт общую длительность текущего красного от начала фазы, а `reduce_red_time` хранит запрос на сокращение будущего красного.

Если красный уже горит 5 с, нажатие устанавливает его общую длительность в 8 с. Повторное нажатие не продлевает фазу, поскольку остаток уже не превышает 3 с. Проверка «прошедшее время меньше длительности» выполняется перед вычитанием остатка и предотвращает беззнаковое переполнение при завершившейся фазе.

Вычитание двух значений `uint32_t` позволяет корректно отсчитывать короткие интервалы при переходе миллисекундного счётчика через ноль. Это предполагает регулярный вызов обработки без пропуска полного оборота счётчика. Блокирующие задержки в прикладном цикле отсутствуют.

== Подавление дребезга

Кнопка опрашивается на каждом проходе цикла. Хранятся последнее считанное состояние, подтверждённое состояние и время последнего замеченного изменения. Если очередное чтение отличается от предыдущего, время начала проверки обновляется. Новое состояние принимается после 20 мс без замеченных изменений.

Подтверждённый переход в нажатое состояние возвращает `true` ровно один раз. При удержании функция возвращает `false`; подтверждённое отпускание подготавливает следующее нажатие. Значение `true` обозначает событие, а не непрерывное состояние контакта. При запуске подтверждённое состояние считается отпущенным. Повторный вызов `button_init()` сам по себе не сбрасывает локальные статические переменные фильтра; в данной программе инициализация выполняется один раз.

= Реализация драйвера GPIO

== Настройка и доступ к регистрам

Функция `gpio_enable_clock()` определяет порт по таблице GPIOA–GPIOK, устанавливает соответствующий бит `RCC->AHB1ENR` и выполняет чтение регистра обратно. `gpio_init()` проверяет параметры и аппаратную блокировку выбранных выводов. Для выходного режима значение ODR заранее подготавливается записью в BSRR. Затем для каждого выбранного вывода настраиваются тип выхода, скорость, подтяжка и при необходимости альтернативная функция. Поле MODER записывается последним.

Поля MODER, OSPEEDR и PUPDR занимают по два бита на вывод; OTYPER — по одному; AFR — по четыре. Маска позволяет изменять настройки выбранного вывода, сохраняя остальные. Выражение очистки поля и установки нового значения формирует одну итоговую запись регистра.

Программные регистры представлены структурой `GPIO_TypeDef`, но сама структура не создаёт периферию: указатель адресует аппаратный блок. Квалификатор `volatile` обеспечивает необходимые обращения компилятора к аппаратуре; атомарность составных операций он не гарантирует.

== Операции чтения и записи

Назначения функций приведены в таблице @api.

#figure(
  table(
    columns: (1.1fr, 1.8fr),
    table.header([*Функция*], [*Назначение*]),
    [gpio_init], [Настройка выбранных маской выводов],
    [gpio_write], [Установка одинакового уровня для выбранных выводов],
    [gpio_read], [Проверка наличия высокого уровня хотя бы на одном выбранном входе],
    [gpio_toggle], [Инверсия выбранных выходных значений],
    [gpio_read_mask], [Чтение входных значений с сохранением позиций битов],
    [gpio_write_mask], [Установка разных уровней выбранных выводов одной записью BSRR],
    [gpio_get_config], [Чтение настроек одного вывода и его выходной защёлки],
  ),
  caption: [Интерфейс собственного драйвера],
  kind: table,
) <api>

BSRR разделён на две половины: единицы в младшей половине устанавливают соответствующие биты ODR, в старшей — сбрасывают. Нули не изменяют выходы. В `gpio_write_mask()` формируются непересекающиеся маски установки и сброса, поэтому выбранные выходы изменяются одной записью.

`gpio_toggle()` сначала читает ODR, затем формирует команду BSRR. Последняя запись атомарна относительно изменения выбранных битов, но вся последовательность чтения и переключения не является атомарной. В данной программе обработчики прерываний не управляют светодиодами, поэтому конкурирующих изменений нет.

`gpio_get_config()` возвращает режим, тип выхода, скорость, подтяжку, номер альтернативной функции и выходное значение ODR. Последнее не следует путать с фактическим уровнем IDR. Перед чтением функция включает тактирование порта, если оно ещё не включено. Быстрые функции чтения и записи предполагают корректный указатель порта и предварительную инициализацию.

== Отличия от HAL и LL

HAL предоставляет типовой интерфейс STM32 и интеграцию с другими средствами библиотеки. LL предоставляет операции более низкого уровня, часто в виде встраиваемых функций над регистрами. Собственный драйвер также обращается к регистрам, но использует свои типы, проверки и интерфейс; вызовы HAL/LL для GPIO в его реализации отсутствуют.

Драйвер поддерживает маски выводов, получение текущей конфигурации и подготовку начального выходного уровня. EXTI, обработчики GPIO-прерываний и установка аппаратной блокировки не реализованы. Прикладные модули не зависят от внутреннего способа доступа к GPIO, поэтому замена HAL не потребовала изменения автомата светофора или алгоритма дребезга.

= Проверка программы

== Проверка на плате

Исполнитель подтвердил работоспособность светодиодов, опроса кнопки, подавления повторных событий при удержании и полного алгоритма светофора. После замены доступа к GPIO собственным драйвером подтверждена работа полного цикла и сокращение красного кнопкой. Осциллограммы и измерения фактических интервалов не предоставлены; численные интервалы в отчёте являются программными уставками.

== Проверка логики на компьютере

Переданный файл `traffic_light.c` без изменения алгоритма дополнительно скомпилирован GCC с тестовыми реализациями `led_set()` и `led_toggle()`. Вместо физической платы они сохраняли состояния трёх светодиодов в массиве. Время и события задавались явно; результаты проверялись утверждениями `assert`. Восемь групп сценариев завершились без ошибок (таблица @tests). Это проверка автомата, а не электрических характеристик GPIO.

#figure(
  table(
    columns: (0.4fr, 2.3fr, 0.7fr),
    table.header([*№*], [*Сценарий*], [*Результат*]),
    [1], [Полный цикл без кнопки, начало мигания и переключения через 300 мс], [Пройден],
    [2], [Нажатие на 5-й секунде красного и повторное на 6-й: переход на 8-й], [Пройден],
    [3], [Нажатие на 10-й секунде: обычное завершение на 12-й], [Пройден],
    [4], [Запрос на жёлтом: следующий красный 3 с; последующий 12 с], [Пройден],
    [5], [Запрос на мигающем зелёном сокращает следующий красный], [Пройден],
    [6], [Нажатие на постоянном зелёном не сокращает следующий красный], [Пройден],
    [7], [Отсчёт красного при переполнении uint32_t], [Пройден],
    [8], [Нажатие после истечения 12 с не продлевает завершившуюся фазу], [Пройден],
  ),
  caption: [Результаты программной проверки автомата],
  kind: table,
) <tests>

== Границы проверки и замечания к переданной версии <limits>

Работа прикладной части подтверждена, однако окончательное соответствие всем требованиям второй части требует следующих действий.

+ В переданном `main.c` осталось тело `MX_GPIO_Init()` с HAL_GPIO и только закомментирован его вызов. Требуется отключить настройку соответствующих выводов в `.ioc` и удалить неиспользуемую сгенерированную GPIO-инициализацию. Файл `.ioc` не предоставлен, поэтому его состояние не проверялось.
+ Предварительная запись BSRR и запись MODER последней предотвращают выдачу старого значения защёлки при обычном переходе вход → выход. Универсальная гарантия отсутствия кратковременных импульсов при произвольной смене режимов текущей реализацией не обеспечена. Например, при смене open-drain → push-pull изменение ODR до OTYPER может временно освободить линию; результат зависит от внешних подтяжек. Для таких переходов нужны отдельные правила порядка операций и проверка осциллографом.
+ В `main()` при ошибке инициализации используется `return 1`. Для автономной прошивки предпочтительнее вызвать имеющийся `Error_Handler()`, чтобы поведение при отказе было определено.
+ `button.c` сохраняет включение общего заголовка HAL и использует `GPIO_PIN_11`, `GPIO_PIN_SET`. Функций HAL GPIO при чтении нет. Заголовок и сравнение можно упростить до `gpio_read(GPIOI, 1u << 11)`; используемые константы сами по себе не означают вызова HAL-драйвера.

Чтение конфигурации, масочные операции и обработка блокировки изучены по исходному коду; отдельные аппаратные протоколы их испытаний отсутствуют. Заголовочные файлы, полный проект сборки и содержимое обработчиков прерываний не переданы. Полная повторная сборка прошивки из предоставленного набора не выполнялась.

= Выводы

Реализован светофор на основе конечного автомата с независимыми отсчётами времени, сокращением красной фазы по кнопке и программным подавлением дребезга. Прикладные модули отделены от аппаратных адресов и не используют блокирующие задержки.

Разработаны собственные операции GPIO: настройка выводов, чтение и запись одиночных и групповых сигналов, переключение и получение конфигурации. Разобраны различия IDR, ODR и BSRR, назначение тактирования RCC и ограничения атомарности операций. Проверка автомата на компьютере и подтверждённая исполнителем работа на плате показывают корректность прикладной логики. Для завершения формальных требований остаются очистка `.ioc` и подтверждение безопасной перенастройки в заявленном диапазоне режимов.

= Использованные материалы

+ Методические указания: «Лабораторная работа 1. Интерфейсы ввода-вывода общего назначения (GPIO)», страницы 72–77 предоставленных файлов `lab1_stm.pdf` и `lab1_stm(1).pdf`.
+ STMicroelectronics. RM0385. STM32F75xxx and STM32F74xxx advanced Arm-based 32-bit MCUs. Разделы GPIO и RCC. #link("https://www.st.com/resource/en/reference_manual/DM00124865-.pdf")[Reference manual RM0385].
+ STMicroelectronics. UM1907. Discovery kit with STM32F746NG MCU. Назначение светодиода, кнопки и разъёмов. #link("https://www.st.com/resource/en/user_manual/dm00190424.pdf")[Руководство платы].
+ Переданные авторские файлы: `main.c`, `traffic_light.c`, `led.c`, `button.c`, `gpio_driver.c`.

#pagebreak()
= Исходные коды собственной разработки

Ниже приведены четыре переданных авторских модуля без изменения алгоритмов и существенный фрагмент `main()`. Сгенерированные функции системной инициализации, неиспользуемая `MX_GPIO_Init()` и исходники библиотек не включены. Заголовочные файлы в переданный набор не входили. Все листинги встроены в этот документ в текстовом виде.

== Основной цикл

#listing(
  "Фрагмент main.c после системной инициализации",
  "  if (!led_init() || !button_init()) {\n    return 1;\n  }\n  uint32_t now = HAL_GetTick();\n  traffic_light_init(now);\n\n\n\n\n  while (1) {\n\n    now = HAL_GetTick();\n    bool pressed_event = button_update(now);\n    traffic_light_update(now, pressed_event);\n\n\n\n  }\n",
)

== Автомат светофора

#listing(
  "traffic_light.c",
  "#include \"traffic_light.h\"\n#include \"led.h\"\n\ntypedef enum {\n  TRAFFIC_RED,\n  TRAFFIC_YELLOW,\n  TRAFFIC_GREEN,\n  TRAFFIC_BLINK_GREEN\n} traffic_state_t;\n\nstatic uint32_t init_time;\nstatic uint32_t last_blink_green;\nstatic traffic_state_t current_state;\nstatic uint32_t time_to_shine_red;\nstatic bool reduce_red_time = false;\n\nvoid traffic_light_init(uint32_t now) {\n  init_time = now;\n  current_state = TRAFFIC_RED;\n  time_to_shine_red = 12000u;\n  reduce_red_time = false;\n\n  led_set(LED_GREEN, false);\n  led_set(LED_YELLOW, false);\n  led_set(LED_RED, true);\n}\n\nvoid traffic_light_update(uint32_t now, bool button_pressed_event) {\n\n  if (button_pressed_event && (current_state == TRAFFIC_BLINK_GREEN ||\n                               current_state == TRAFFIC_YELLOW)) {\n    reduce_red_time = true;\n  }\n\n  switch (current_state) {\n\n  case TRAFFIC_RED:\n    if (button_pressed_event && (now - init_time) < time_to_shine_red &&\n        time_to_shine_red - (now - init_time) > 3000u) {\n      time_to_shine_red = (now - init_time) + 3000u;\n    }\n\n    if ((now - init_time) >= time_to_shine_red) {\n      led_set(LED_RED, false);\n      led_set(LED_GREEN, true);\n\n      current_state = TRAFFIC_GREEN;\n      init_time = now;\n    }\n    break;\n\n  case TRAFFIC_GREEN:\n    if ((now - init_time) >= 3000u) {\n      // green is already on, let it shine\n      current_state = TRAFFIC_BLINK_GREEN;\n      init_time = now;\n      last_blink_green = now;\n    }\n    break;\n\n  case TRAFFIC_BLINK_GREEN:\n    if ((now - init_time) < 2000u && (now - last_blink_green) >= 300u) {\n      led_toggle(LED_GREEN);\n      last_blink_green = now;\n    }\n    if ((now - init_time) >= 2000u) {\n      led_set(LED_GREEN, false);\n      led_set(LED_YELLOW, true);\n      current_state = TRAFFIC_YELLOW;\n      init_time = now;\n    }\n    break;\n\n  case TRAFFIC_YELLOW:\n    if ((now - init_time) >= 3000u) {\n      led_set(LED_YELLOW, false);\n      led_set(LED_RED, true);\n\n      time_to_shine_red = reduce_red_time ? 12000u / 4 : 12000u;\n      reduce_red_time = false;\n      current_state = TRAFFIC_RED;\n      init_time = now;\n    }\n    break;\n\n  default:\n    break;\n  }\n}\n",
)

== Драйвер светодиодов

#listing(
  "led.c",
  "#include \"led.h\"\n#include \"gpio_driver.h\"\n#include \"stm32f746xx.h\"\n\ntypedef struct {\n  GPIO_TypeDef *port;\n  uint16_t pin;\n} led_config_t;\n\nstatic const led_config_t leds[LED_COUNT] = {\n    [LED_RED] = {GPIOG, 1u << 6},\n    [LED_YELLOW] = {GPIOG, 1u << 7},\n    [LED_GREEN] = {GPIOI, 1u << 1},\n};\n\nvoid led_set(led_t led, bool enabled) {\n  if ((unsigned)led >= LED_COUNT) {\n    return;\n  }\n  gpio_write(leds[led].port, leds[led].pin, enabled ? 1 : 0);\n}\n\nvoid led_toggle(led_t led) {\n\n  if ((unsigned)led >= LED_COUNT) {\n    return;\n  }\n  gpio_toggle(leds[led].port, leds[led].pin);\n}\n\nbool led_init(void) {\n  const gpio_config_t config = {.mode = GPIO_MODE_OUT,\n                                .output_type = GPIO_OUTPUT_PUSH_PULL,\n                                .speed = GPIO_SPEED_LOW,\n                                .pull = GPIO_PULL_NONE,\n                                .alternate = 0u,\n                                .initial_high = false};\n\n  for (unsigned i = 0u; i < LED_COUNT; ++i) {\n    if (!gpio_init(leds[i].port, leds[i].pin, &config)) {\n      return false;\n    }\n  }\n\n  return true;\n}\n",
)

== Драйвер кнопки

#listing(
  "button.c",
  "#include \"button.h\"\n#include \"gpio_driver.h\"\n\n#include \"stm32f7xx_hal.h\" // IWYU pragma: keep\n\nbool button_is_pressed(void) {\n  return gpio_read(GPIOI, GPIO_PIN_11) == GPIO_PIN_SET;\n}\n\nbool button_update(uint32_t now) {\n  static bool last_read_pressed = false;\n  static bool confirmed_pressed = false;\n  static uint32_t last_change_time = 0;\n\n  bool pressed_now = button_is_pressed();\n\n  if (pressed_now != last_read_pressed) {\n    last_read_pressed = pressed_now;\n    last_change_time = now;\n  }\n\n  if (last_read_pressed != confirmed_pressed &&\n      (uint32_t)(now - last_change_time) >= 20u) {\n    confirmed_pressed = last_read_pressed;\n    return confirmed_pressed;\n  }\n\n  return false;\n}\n\nbool button_init(void) {\n  const gpio_config_t config = {.mode = GPIO_MODE_IN,\n                                .output_type = GPIO_OUTPUT_PUSH_PULL,\n                                .speed = GPIO_SPEED_LOW,\n                                .pull = GPIO_PULL_NONE,\n                                .alternate = 0u,\n                                .initial_high = false};\n\n  return gpio_init(GPIOI, 1u << 11, &config);\n}\n",
)

== Драйвер GPIO

#listing(
  "gpio_driver.c",
  "#include \"gpio_driver.h\"\n#include <stddef.h>\n\nvoid gpio_write(GPIO_TypeDef *port, uint16_t pins, bool high) {\n  if (high) {\n    port->BSRR = (uint32_t)pins;\n  } else {\n    port->BSRR = (uint32_t)pins << 16u;\n  }\n}\n\nbool gpio_read(GPIO_TypeDef *port, uint16_t pins) {\n  return (port->IDR & pins) != 0u;\n}\n\nvoid gpio_toggle(GPIO_TypeDef *port, uint16_t pins) {\n\n  uint32_t current = port->ODR;\n  uint32_t set_mask = (~current) & pins;\n  uint32_t reset_mask = current & pins;\n  port->BSRR = set_mask | (reset_mask << 16u);\n}\n\nstatic bool gpio_enable_clock(GPIO_TypeDef *port) {\n  GPIO_TypeDef *const ports[] = {GPIOA, GPIOB, GPIOC, GPIOD, GPIOE, GPIOF,\n                                 GPIOG, GPIOH, GPIOI, GPIOJ, GPIOK};\n\n  for (uint32_t i = 0u; i < 11u; ++i) {\n    if (port == ports[i]) {\n      RCC->AHB1ENR |= 1u << i;\n      (void)RCC->AHB1ENR;\n      return true;\n    }\n  }\n\n  return false;\n}\n\nbool gpio_init(GPIO_TypeDef *port, uint16_t pins, const gpio_config_t *config) {\n  if (config == NULL || pins == 0u) {\n    return false;\n  }\n\n  if ((unsigned)config->mode > 3u || (unsigned)config->output_type > 1u ||\n      (unsigned)config->speed > 3u || (unsigned)config->pull > 2u ||\n      config->alternate > 15u) {\n    return false;\n  }\n\n  if (!gpio_enable_clock(port)) {\n    return false;\n  }\n\n  // Не пытаемся изменить аппаратно заблокированные настройки.\n  if ((port->LCKR & (1u << 16)) != 0u && (port->LCKR & pins) != 0u) {\n    return false;\n  }\n\n  // Подготовить выходное значение до включения режима выхода.\n  if (config->mode == GPIO_MODE_OUT) {\n    gpio_write(port, pins, config->initial_high);\n  }\n\n  for (uint32_t pin = 0u; pin < 16u; ++pin) {\n    uint32_t pin_mask = 1u << pin;\n\n    if ((pins & pin_mask) == 0u) {\n      continue;\n    }\n\n    uint32_t shift = pin * 2u;\n    uint32_t field_mask = 3u << shift;\n\n    port->OTYPER =\n        (port->OTYPER & ~pin_mask) | ((uint32_t)config->output_type << pin);\n\n    port->OSPEEDR =\n        (port->OSPEEDR & ~field_mask) | ((uint32_t)config->speed << shift);\n\n    port->PUPDR =\n        (port->PUPDR & ~field_mask) | ((uint32_t)config->pull << shift);\n\n    if (config->mode == GPIO_MODE_AF) {\n      uint32_t index = pin / 8u;\n      uint32_t af_shift = (pin % 8u) * 4u;\n\n      port->AFR[index] = (port->AFR[index] & ~(15u << af_shift)) |\n                         ((uint32_t)config->alternate << af_shift);\n    }\n\n    // Режим меняем после подготовки остальных настроек.\n    port->MODER =\n        (port->MODER & ~field_mask) | ((uint32_t)config->mode << shift);\n  }\n\n  return true;\n}\n\nuint16_t gpio_read_mask(GPIO_TypeDef *port, uint16_t pins) {\n  return (uint16_t)(port->IDR & pins);\n}\n\nvoid gpio_write_mask(GPIO_TypeDef *port, uint16_t pins, uint16_t values) {\n  uint32_t set_mask = (uint32_t)pins & values;\n  uint32_t reset_mask = (uint32_t)pins & ~(uint32_t)values;\n\n  port->BSRR = set_mask | (reset_mask << 16u);\n}\n\nbool gpio_get_config(GPIO_TypeDef *port, uint8_t pin,\n                     gpio_pin_state_t *result) {\n  if (result == NULL || pin > 15u) {\n    return false;\n  }\n\n  if (!gpio_enable_clock(port)) {\n    return false;\n  }\n\n  uint32_t shift = (uint32_t)pin * 2u;\n\n  result->mode = (gpio_mode_t)((port->MODER >> shift) & 3u);\n\n  result->output_type = (gpio_output_type_t)((port->OTYPER >> pin) & 1u);\n\n  result->speed = (gpio_speed_t)((port->OSPEEDR >> shift) & 3u);\n\n  result->pull = (gpio_pull_t)((port->PUPDR >> shift) & 3u);\n\n  uint32_t index = pin / 8u;\n  uint32_t af_shift = (pin % 8u) * 4u;\n\n  result->alternate = (uint8_t)((port->AFR[index] >> af_shift) & 15u);\n\n  result->output_high = ((port->ODR >> pin) & 1u) != 0u;\n\n  return true;\n}\n",
)

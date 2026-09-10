# zimbra2mailcow

Набор скриптов для миграции почтовых ящиков и списков рассылки с **Zimbra** на **Mailcow**.

Скрипты рассчитаны на миграцию пользователей на основании единого CSV-файла (mailcow_full_YYYYMMDD.csv) с данными вида:

email|password|displayName|aliases|quota|active|attributes

В процессе миграции используются два набора скриптов:

* `zimbra/` — подготовка и экспорт данных на Zimbra;
* `mailcow/` — импорт и управление учётными записями на Mailcow;
* `migrate_imap.pl` — перенос содержимого почтовых ящиков по IMAP.

---

## Структура

```text
.
├── mailcow/
│   ├── disable_mailcow_users.sh
│   ├── enable_mailcow_users.sh
│   ├── import_lists.sh
│   ├── import_single_user.sh
│   ├── import_to_mailcow.sh
│   ├── update_passwords.pl
│   └── validate_import.sh
│
├── migrate_imap.pl
│
└── zimbra/
    ├── disable_users.sh
    ├── enable_users.sh
    ├── export_accnt.sh
    └── export_ml.sh
```

---

# Zimbra

Скрипты из каталога `zimbra/` необходимо выполнять **на Zimbra-сервере от имени пользователя `zimbra`**.

## `export_accnt.sh`

Экспортирует учётные записи Zimbra в основной CSV-файл:

```text
mailcow_full_YYYYMMDD.csv
```

При экспорте для учётных записей генерируются **новые пароли**, которые будут использоваться на Mailcow.

> Пароли пользователей на Zimbra при этом **не изменяются**.

Пример:

```bash
./export_accnt.sh
```

Результатом работы является файл с данными, необходимыми для последующего импорта пользователей в Mailcow.

---

## `export_ml.sh`

Экспортирует списки рассылки Zimbra.

Полученные данные используются скриптом:

```text
mailcow/import_lists.sh
```

для создания соответствующих списков рассылки в Mailcow.

---

## `enable_users.sh`

Подготавливает отключённые учётные записи Zimbra к миграции.

На основании:

```text
mailcow_full_YYYYMMDD.csv
```

скрипт:

1. устанавливает отключённым пользователям новые пароли;
2. включает эти учётные записи;

Это необходимо, чтобы IMAP-миграция могла авторизоваться в ящиках.

---

## `disable_users.sh`

После завершения синхронизации с Mailcow отключает на Zimbra учётные записи, которые **были неактивны до начала миграции**.

Использует тот же CSV-файл:

```text
mailcow_full_YYYYMMDD.csv
```

Скрипт предназначен для финального восстановления исходного состояния учётных записей после завершения миграции.

---

# Mailcow

Скрипты из каталога `mailcow/` предназначены для выполнения на сервере Mailcow.

## `import_to_mailcow.sh`

Основной скрипт импорта учётных записей из Zimbra в Mailcow.

Источником данных является:

```text
mailcow_full_YYYYMMDD.csv
```

Скрипт создаёт/импортирует почтовые учётные записи в Mailcow на основании данных из CSV.

---

## `import_single_user.sh`

Импортирует **один почтовый ящик** в Mailcow.

Основное назначение — отладка проблем с импортом конкретной учётной записи. Для этого выполняем его в режиме отладки
```text
 bash -x ./import_single_user.sh oem@example.com mailcow_full_YYYYMMDD.csv
```

Например, если массовый импорт сообщает об ошибке для одного пользователя, этот скрипт позволяет повторить импорт отдельно и получить более подробную информацию.

Наиболее распространённые причины ошибки:

* пароль не соответствует требованиям сложности Mailcow;
* превышена квота домена;

---

## `enable_mailcow_users.sh`

Включает отключённые учётные записи Mailcow на основании:

```text
mailcow_full_YYYYMMDD.csv
```

Используется перед миграцией почты, чтобы необходимые пользователи могли принимать/авторизовываться в Mailcow.

---

## `disable_mailcow_users.sh`

Отключает учётные записи Mailcow, которые согласно исходным данным **должны оставаться неактивными после завершения миграции**.

Источник данных:

```text
mailcow_full_YYYYMMDD.csv
```

Этот скрипт следует выполнять после завершения миграции и синхронизации данных.

---

## `import_lists.sh`

Импортирует в Mailcow списки рассылки, ранее экспортированные с Zimbra с помощью:

```text
zimbra/export_ml.sh
```

---

## `validate_import.sh`

Проверяет результаты импорта пользователей и показывает учётные записи, которые не были импортированы.

Используется для контроля результатов:

```text
mailcow_full_YYYYMMDD.csv
        ↓
import_to_mailcow.sh
        ↓
validate_import.sh
```

---

## `update_passwords.pl`

Заменяет пароли в CSV-файле mailcow_full_YYYYMMDD.csv на значения из отдельного файла с паролями.

Использование:

```bash
./update_passwords.pl <исходный_CSV> <файл_паролей> <выходной_файл>
```

Пример:

```bash
./update_passwords.pl \
    mailcow_full_20260909.csv \
    mailcow_passwords_20260909.txt \
    result.txt
```

Используется, если необходимо заменить пароли в уже подготовленном CSV-файле на известные старые пароли пользователей

---

# Перенос содержимого почтовых ящиков

## `migrate_imap.pl`

Переносит содержимое почтовых ящиков с исходного IMAP-сервера на целевой.

Список пользователей берётся из:

```text
mailcow_full_YYYYMMDD.csv
```

Использование:

```text
migrate_imap.pl \
    --source <src_host> \
    --dest <dst_host> \
    --file <users_file> \
    [--age <days>] \
    [--dest-domain <domain.com>] \
    [--src-domain <domain.com>] \
    [--nossl]
```

### Параметры

| Параметр        | Описание                                                |
| --------------- | ------------------------------------------------------- |
| `--source`      | Адрес исходного IMAP-сервера (Zimbra)                   |
| `--dest`        | Адрес целевого IMAP-сервера (Mailcow)                   |
| `--file`        | CSV-файл со списком пользователей                       |
| `--age`         | Ограничение по возрасту писем в днях                    |
| `--dest-domain` | Домен, используемый для авторизации на целевом сервере  |
| `--src-domain`  | Домен, используемый для авторизации на исходном сервере |
| `--nossl`       | Отключить использование SSL                             |

### Замена домена

Параметры `--dest-domain` и `--src-domain` предназначены для ситуации, когда домен пользователя меняется во время миграции.

Например:

```text
Zimbra:
user@zimbra-domain.com

Mailcow:
user@mailcow-domain.com
```

При этом в `mailcow_full_YYYYMMDD.csv` уже может находиться **новый домен**.

В таком случае:

```bash
migrate_imap.pl \
    --source zimbra.example.com \
    --dest mailcow.example.com \
    --file mailcow_full_20260909.csv \
    --src-domain zimbra-domain.com \
    --dest-domain mailcow-domain.com
```

`--src-domain` используется для восстановления адреса пользователя на исходном сервере, если в CSV уже указан новый домен.

`--dest-domain` определяет адрес пользователя, который используется для авторизации на целевом Mailcow.

---

# Рекомендуемый порядок миграции

Типовой порядок выполнения скриптов:

```text
                         ZIMBRA
                           │
                           │
                  export_accnt.sh
                           │
                           ▼
             mailcow_full_YYYYMMDD.csv
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
       MAILCOW                      ZIMBRA
             │                           │
   import_to_mailcow.sh          enable_users.sh
             │                           │
             ▼                           │
   validate_import.sh                    │
             │                           │
             └─────────────┬─────────────┘
                           │
                           ▼
                    migrate_imap.pl
                           │
                           ▼
                    MAILCOW MAILBOXES
                           │
                           │
                    Проверка миграции
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
       disable_mailcow_users.sh   disable_users.sh
```

Для списков рассылки:

```text
Zimbra
  │
  └── export_ml.sh
          │
          ▼
    экспорт списков
          │
          ▼
    Mailcow
          │
          └── import_lists.sh
```


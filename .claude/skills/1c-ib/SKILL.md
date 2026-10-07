---
name: 1c-ib
description: Создание, копии, дампы и восстановление баз 1С (информационных баз) на кластерах v8dock — headless, без конфигуратора: rac + ibcmd + pg_dump/pg_restore, всё через docker. Использовать, когда просят «создай базу 1С», «покажи базы», «сделай копию базы», «сделай дамп», «выгрузи dt», «разверни дамп/копию(dt/dump) обратно», «загрузи dt», «удали базу», а также «открой/запусти базу», «база не открывается / падает при запуске», «прочитай ошибки базы». Кластеры, версии платформы и пароль СУБД автоопределяются из структуры репо и запущенных контейнеров — одни и те же команды работают на любом сервере с этим compose-стеком.
---

# 1C infobases: create / copy / dump / restore (headless)

Операции с серверными ИБ кластеров v8dock без конфигуратора и GUI-консоли.
Все команды ниже проверены на живом стенде (8.3 и 8.5, 2026-10-07). Ничего
не хардкодится: версия контейнеров, порты и пароль СУБД определяются на месте.

## НАСТРОЙКА стенда (repo-копия держит этот раздел ПУСТЫМ)

Ниже - места, зависящие от конкретной установки. Пустое значение = при
первом использовании СПРОСИ пользователя и запиши ответ в ЛОКАЛЬНУЮ копию
скилла. Что считать локальной копией: работаешь в СВОЁМ клоне на своём
стенде - сам файл скилла в клоне (не коммить заполненный раздел: форк/PR
держат его пустым); отдельная копия ~/.claude/skills/1c-ib - правила в
разделе ПЕРЕНОС ниже.

- каталог шаблонов конфигураций (ConfigurationTemplatesLocation):
- имена/адреса машин стенда (сервер, клиенты):
- соглашения об именах баз (префиксы контуров):

## ПЕРЕНОС между локальной и репо-копией (правила)

- мастер логики - репо-копия (.claude/skills/1c-ib в репо v8dock);
  локальная копия (~/.claude/skills/1c-ib) = репо + заполненная НАСТРОЙКА.
- СИМЛИНКИ ЗАПРЕЩЕНЫ: локальный скилл - всегда отдельная копия (cp -R),
  иначе приватные ответы уезжают в публичный репозиторий.
- правишь логику - правь репо-копию, потом скопируй в локаль, сохранив
  секцию НАСТРОЙКА. В репо-копию НИКОГДА не попадают: имена машин, IP,
  пути /Users/<кто-то>, названия рабочих баз/конфигураций, креды.

## Шаг 0 — автоопределение (каждый раз, перед операцией)

```sh
# 1) корень репо: каталог с docker-compose.yml и src/scripts/rac.sh
#    (если cwd внутри репо — git rev-parse --show-toplevel; иначе спросить путь у юзера)
cd <repo>

# 2) запущенные кластеры: каждый контейнер server1c-* = один кластер,
#    версия платформы видна в имени. Нет ни одного — поднять:
#    docker compose --profile with-server up -d
docker ps --format '{{.Names}}' | grep '^server1c-'     # напр. server1c-8.3.27.2325

# 3) СУБД: контейнер pg1c (compose-сервис; переименован — grep по образу pg).
#    Креды читать ТОЛЬКО из env контейнера, не из головы:
docker exec pg1c printenv POSTGRES_USER POSTGRES_PASSWORD   # postgres / <пароль>
PGPWD=$(docker exec pg1c printenv POSTGRES_PASSWORD)
PGUSER=$(docker exec pg1c printenv POSTGRES_USER); PGUSER=${PGUSER:-postgres}

# 4) проверка связки: сервер должен резолвить СУБД по docker-имени (pg1c в
#    общей сети). Если getent пуст — pg не в сети кластера, чинить compose,
#    не подменять адрес:
docker exec <ct> getent hosts pg1c

# 5) ibcmd в контейнере кластера (путь зависит от версии, ищем):
IBDIR=$(docker exec <ct> sh -c 'dirname "$(find /opt/1cv8 -maxdepth 3 -name ibcmd | head -1)"')
```

Если кластеров несколько — выбрать по смыслу просьбы (8.3/8.5/версия из
имени контейнера); неоднозначно — спросить. rac ходит всегда в
`localhost:1545` ВНУТРИ контейнера (ras поднимает entrypoint) — порты хоста
не нужны. Обёртка `src/scripts/rac.sh` сама подставляет cluster uuid;
дефолтный контейнер у неё зашит под 8.3, поэтому при нескольких кластерах
ВСЕГДА передавать `RAC_CONTAINER=<ct>`.

## Переменные в примерах ниже

`<ct>` — контейнер кластера · `<name>` — имя ИБ (= имя БД PG) · `$PGPWD`,
`$PGUSER`, `$IBDIR` — из шага 0. Команды — из корня репо.

## Список баз / сеансов

```sh
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase summary list   # ИБ кластера
RAC_CONTAINER=<ct> ./src/scripts/rac.sh session list            # сеансы (hibernate тоже)
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase info --name=<name>   # одна ИБ
docker exec pg1c sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" psql -U "${POSTGRES_USER:-postgres}" -Atc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1"'
```

## lazy1c (lz1c) — CLI без docker/rac

[**lazy1c**](https://github.com/0x3654/lazy1c) (публичный, один статический
Go-бинарник): говорит с кластерами нативно (RAS :1545 для 8.3/8.5, реверс
MMC :1540 для 8.2), без rac, docker и платформы. Вся работа с сеансами и
регламентными заданиями доступна сразу; кластеры дописываются в список
(lazy1c.toml) по мере появления. Удобен для быстрых проверок сеансов и
точечного terminate, в т.ч. «спящих» хвостовых сеансов (частая грабля
клиентских автозапусков: убитый клиент остаётся hibernate-сеансом и ест
слот лицензии ИБ). Каталог клона спросить у пользователя / взять из НАСТРОЙКИ.

```sh
cd <клон-lazy1c> && ./lazy1c ctl clusters                     # кластеры из lazy1c.toml
./lazy1c ctl sessions -cluster 8.3.27                         # сеансы; спящие помечены «спит»
./lazy1c ctl terminate -cluster 8.3.27 -session <uuid> -yes   # точечно
./lazy1c ctl terminate -cluster 8.3.27 -sleeping -yes         # все спящие
```

Выход таб-разделённый; мутации требуют явного `-yes`. Прецедент (07.10.2026,
живая рабочая база): после аварийных запусков оставался спящий 1CV8-сеанс,
«Превышено ограничение лицензии для разработчиков на количество клиентов
информационной базы» — убран через `ctl terminate -session … -yes`.

## Сеансы: проверить / дождаться / завершить

Эксклюзивные операции (drop, restore поверх, dt-restore, config apply)
блокируются живыми сеансами. Перед такой операцией:

**1. Показать сеансы базы** (кто мешает: user-name / app-id / host /
last-active-at / hibernate):

```sh
IBUUID=$(RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase info --name=<name> | awk '/^infobase/{print $3}')
RAC_CONTAINER=<ct> ./src/scripts/rac.sh session list --infobase=$IBUUID
```

**2. Решение с юзером**: hibernate-сеансы сами не исчезнут (убитый клиент
спит до суток) — только terminate; живые — попросить людей закрыть базу
и ждать, либо terminate с явного разрешения (это чужие сеансы).

**3a. Завершить** (все сеансы ИБ разом, по явному разрешению юзера;
сеанс может исчезнуть между list и terminate — «ошибка разбора/не найден»
на конкретный uuid = уже ушёл, не страшно):

```sh
RAC_CONTAINER=<ct> ./src/scripts/rac.sh session list --infobase=$IBUUID \
  | awk '/^session/{print $3}' | while read s; do \
    RAC_CONTAINER=<ct> ./src/scripts/rac.sh session terminate --session="$s"; done
```

**3b. Дождаться, пока закроют сами** — ТОЛЬКО фоновой задачей (run_in_background
в Bash; чат не блокировать — по завершении задачи харнесс разбудит сам, и
операция продолжается). Шаг 15 с, лимит 30 мин, по таймауту — кто остался:

```sh
CT=<ct>; IBUUID=<uuid>
for i in $(seq 1 120); do
  n=$(RAC_CONTAINER=$CT ./src/scripts/rac.sh session list --infobase=$IBUUID | grep -c '^session')
  [ "$n" -eq 0 ] && { echo "OK: все сеансы завершены ($((i*15)) c)"; exit 0; }
  sleep 15
done
echo "TIMEOUT: ещё сеансов — $n:"; RAC_CONTAINER=$CT ./src/scripts/rac.sh session list --infobase=$IBUUID; exit 2
```

После ожидания/терминации сразу выполнять операцию; hangover PG-соединений
пула rphost лечится граблёй 55006 (см. «Удалить базу»).

## Открыть базу / проверить запуск

Правильный путь — скрипт репо (сам находит кластер-владелец базы, версию
клиента и собирает строку подключения; окно открывается НА ДЕСКТОПЕ юзера —
предупредить перед запуском):

```sh
./src/scripts/ib-run.sh <name>                    # толстый клиент (умолчание:
                                                  # большинство баз стенда — 8.2-происхождение, обычные формы)
./src/scripts/ib-run.sh <name> -m thin|designer   # тонкий / конфигуратор
./src/scripts/ib-run.sh <name> -n <логин> -p <пароль> -s 30   # креды ИБ + скрин через 30 c
                                                  # -> data/runs/<name>_<HHMMSS>.png
```

Проверка «база открылась» без глаз: `rac.sh session list` — сеанс с
`app-id: 1CV8`, который живёт и наращивает `calls-all`, = вход прошёл.
Конфигурация может сама запретить вход (`Отказ = Истина` в
ПередНачаломРаботыСистемы — проверки входа в коде конфигурации) — сеанс
появился и тут же умер = смотреть ошибки (раздел ниже).

Грабли запуска (проверено 07.10):
- `open -a <app> --args /RunEnterprise /S "server1c#base"` НЕ работает —
  клиент игнорирует строку и открывает список баз. Рабочий ручной вариант:
  `/opt/1cv8/<версия>/1cv8.app/Contents/MacOS/1cv8 ENTERPRISE /S server1c#<name>`
  (но лучше ib-run.sh).
- `ping server1c` режется (ICMP закрыт) при живых портах — доступ проверять
  `nc -z server1c 1541`, не пингом.
- Клиент из стороннего контейнера (не мак) берёт лицензию с сервера: для ИБ
  включить `rac.sh infobase update --name=<name> --license-distribution=allow`,
  иначе «Не найден лицензионный ключ».

## Автозапуск внешней обработки (/Execute) без человека

Проверено 07.10 на живой базе 8.3.27 (обыные формы): толстый
клиент мак + epf, которая в ПриОткрытии по параметру запуска делает работу
и вызывает ЗавершитьРаботуСистемы(Ложь) — окно открывается и закрывается само.

```sh
T0=$(date -u +%Y-%m-%dT%H:%M:%S)          # метка ДО запуска — для ЖР
EPF=</полный/путь/обработки.epf>
/opt/1cv8/8.3.27.2325/1cv8.app/Contents/MacOS/1cv8 ENTERPRISE \
  /S server1c/<name> /Execute "$EPF" /C "<каталог-результат>" &
# /S через СЛЭШ (server1c/name); /C <строка> доступна коду как ПараметрЗапуска
```

Обязательные условия и контроль:

1. **Защита от опасных действий** иначе роняет обработку («Действие прервано
   системой защиты», видно в ЖР): `DisableUnsafeActionProtection=.*` в
   `~/.1cv8/1C/1cv8/conf/conf.cfg`. Ключа командной строки НЕТ (только
   conf.cfg или галка у пользователя ИБ).
2. **Лицензия**: комьюнити-лицензия ограничивает клиентов ИБ; убитый клиент
   остаётся спящим сеансом и ест слот. Перед прогоном:
   `lazy1c ctl sessions` → terminate спящих; свой клиент после kill тоже
   оставить чистым (см. раздел lazy1c).
3. **Результат без глаз**: ЖР от метки T0 (раздел «Ошибки базы»):
   `Сеанс. Начало` + нет `Level:Error` = прошло; интерактивные ветки
   (обработка без /C) проверять так же — клиент остаётся живым, через 60-90 с
   читать ЖР и убивать процесс, спящий сеанс снять.
4. Сторонний контейнер вместо мака (amd64/Rosetta) для 8.3-базы не взлетел
   (500 с без подключения) — мак-клиент заведомо рабочий путь.

## Ошибки базы: прочитать

**1. Журнал регистрации headless** (серверные ИБ пишут ЖР в контейнер
кластера; проверено 07.10, ошибки старта видны дословно):

```sh
# uuid ИБ -> каталог ЖР
IBUUID=$(RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase info --name=<name> | awk '/^infobase/{print $3}')
LOGDIR=/home/usr1cv8/.1cv8/1C/1cv8/reg_1541/$IBUUID/1Cv8Log

# события с времени Т в json; ошибки = поле "Level":"Error"
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd eventlog export --format=json \
  --from=<YYYY-MM-DDThh:mm:ss> $LOGDIR 2>/dev/null" \
  | grep '"Level":"Error"' | grep -o '"Date":"[^"]*"\|"EventPresentation":"[^"]*"\|"Comment":"[^"]*"'
```

Ошибки старта сеанса/конфигурации («Пользователь ... не был найден»,
«Ошибка инициализации модуля», падения фоновых заданий) лежат именно там —
читать ДО гадания по коду.

**2. Диалоги клиента** — скрин `ib-run.sh -s N` (ошибки всплывают поверх)
+ чтение картинки ассистентом.

## Создать базу

```sh
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase create \
  --name=<name> --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --locale=ru --db-user=$PGUSER --db-pwd="$PGPWD" \
  --create-database --descr="<описание>"
# для демо/копий под тяжёлые регламентные задания добавлять --scheduled-jobs-deny=on
```

**Имя = латиница, нижний регистр, без пробелов** (пробел в конце однажды дал
«фантомную» ИБ и битую базу). Проверка: появилась в `summary list` И И в
списке БД PG. Чтобы база сразу была видна клиентам — добавить в
`ibases.v8i` (раздел ниже).

## Список баз у клиентов (`ibases.v8i`)

Клиентский список баз (окно выбора ИБ). Точек ДВЕ, и они могут разойтись
(проверено живьём 07.10: клиент показывает одну, правка другой — «базы нет»):

- `~/.1C/1cestart/ibases.v8i` — список лаунчера, **его реально показывает
  мак-клиент** (точка 1CEStart; на винде аналог `%APPDATA%\1C\1CEStart\`);
- `~/.1cv8/1C/1cv8/ibases.v8i` → симлинк на мастер-склад `~/.1c-storage/ibases.v8i`
  (классическая точка; винда — `%APPDATA%\1C\1cv8\`, симлинки на шару `\\Mac\1C`).

Перед правкой — найти ЖИВОЙ список: сравнить mtime обеих точек (клиент
перезаписывает свою при старте) и искать запись в обеих. Править живую;
имена папок брать ТОЛЬКО из неё (в разных точках разные). Клиент закрыть —
лаунчер перезаписывает список из памяти. Разошлись точки — слить всё в
мастер-склад и пересимлинкнуть 1cestart-точку на него (ремонт стенда,
клиент обязан быть закрыт).

Формат: **UTF-8 с BOM, переводы строк CRLF — не ломать**. Запись базы =
секция `[Отображаемое имя]` (может быть русским, ≠ Ref) с
`Connect=Srvr="server1c";Ref="<имя_ИБ>";` (кластеры 8.3 — без порта; 8.5 —
порт обязателен, это хост-маппинг кластерного порта 1541 из `docker ps
<ct>:` первой строки диапазона: 8.5.1.1522 → `server1c:2541`,
8.5.4.1878 → `server1c:3541`; проверено по живому списку 08.10),
`ID=<uuid>`, `Folder=`, `External=0`; файловые ИБ — `Connect=File="<путь>"`.
**Папка — тоже секция, но без `Connect=`**; база попадает в неё через
`Folder=/<имя папки>`, корень — `Folder=/`. Порядок полей внутри секции не
важен, `OrderInList/OrderInTree` необязательны — клиент пересчитает их при
следующем сохранении сам.

```sh
IB=~/.1C/1cestart/ibases.v8i                # живая точка (см. выше), не склад!
cp "$IB" "$IB.bak-$(date +%Y%m%d)"          # бэкап перед любой правкой

# показать: имя в списке -> кластер/Ref -> папка
tr -d '\r' < "$IB" | awk '/^\[/{n=$0} /^Connect=/{c=$0} /^Folder=/{print n" | "c" | "$0}'
# папки в выводе не имеют Connect — это секции-папки

# добавить (идемпотентно по Ref; <папка> без слэша, пустая строка = корень):
name=<имя_ИБ>
grep -q "Ref=\"$name\";" "$IB" || printf '[%s]\r\nConnect=Srvr="server1c";Ref="%s";\r\nID=%s\r\nFolder=/%s\r\nExternal=0\r\nClientConnectionSpeed=Normal\r\nApp=Auto\r\nWA=1\r\nVersion=8.3\r\n' \
  '<Имя в списке>' "$name" "$(uuidgen | tr 'A-Z' 'a-z')" '<папка>' >> "$IB"

# удалить запись (секцию целиком по Ref; остальное остаётся байт-в-байт):
awk -v ref="Ref=\"$name\"" '
  /^\[/ { if (buf != "" && !del) printf "%s", buf; buf = $0 "\n"; del = 0; next }
  { buf = buf $0 "\n"; if (index($0, ref)) del = 1 }
  END { if (buf != "" && !del) printf "%s", buf }
' "$IB" > "$IB.tmp" && mv "$IB.tmp" "$IB"
```

Грабли списка: клиенты подхватывают правки при следующем старте; открывать
список в двух клиентах одновременно нельзя — перезапишет последний; 1С при
сохранении может заменить симлинк обычным файлом (проверять `ls -la` и
пересоздавать); записи на несуществующие ИБ безвредны — клиент ругнётся
только при подключении (сверка с реальностью — `summary list` кластера).

## Дамп базы → dt (переносимый формат)

```sh
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd infobase dump \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' /tmp/<name>.dt"
mkdir -p data/dumps && docker cp <ct>:/tmp/<name>.dt "data/dumps/<name>_$(date +%F).dt"
docker exec <ct> rm -f /tmp/<name>.dt
```

dt переносятся между стендами и версиями (платформа-приёмник ≥ платформы
источника). Лицензия для dump/restore не нужна. Если в базе заведены
пользователи ИБ — добавить `--user=<ИБ-логин> --password=<пароль>`.

## Развернуть dt

**В новую базу** (создаёт БД + грузит данные, затем регистрирует в кластере):

```sh
docker cp файл.dt <ct>:/tmp/in.dt
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd infobase create \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' --locale=ru --create-database --restore=/tmp/in.dt"
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase create \      # attach БЕЗ --create-database
  --name=<name> --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --locale=ru --db-user=$PGUSER --db-pwd="$PGPWD" --descr="..."
docker exec <ct> rm -f /tmp/in.dt
```

**Поверх существующей** (данные заменяются, `-F` принудительно роняет сеансы):

```sh
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd infobase restore \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' -F --session-terminate-message='restore from dt' /tmp/in.dt"
```

## Копия базы X → Y

**Быстрый путь — на уровне PG** (один стенд, идентичная копия до внутренностей;
на больших базах на порядок быстрее dt):

```sh
docker exec pg1c sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" pg_dump -U "${POSTGRES_USER:-postgres}" -Fc -d <X> -f /tmp/<X>.dump'
docker exec pg1c sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" createdb -U "${POSTGRES_USER:-postgres}" <Y>'
docker exec pg1c sh -c 'PGPASSWORD="${POSTGRES_PASSWORD:-$PGPASSWORD}" pg_restore -U "${POSTGRES_USER:-postgres}" -d <Y> /tmp/<X>.dump'
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase create \
  --name=<Y> --dbms=PostgreSQL --db-server=pg1c --db-name=<Y> \
  --locale=ru --db-user=$PGUSER --db-pwd="$PGPWD" --descr="copy of <X>"
docker exec pg1c rm -f /tmp/<X>.dump
```

**Портативный путь** — дамп в dt (выше) + развертка в новую базу (выше);
для переноса между стендами/версиями платформы.

## Создать базу из шаблона 1С (каталог tmplts)

«Шаблон 1С» = поставка конфигурации в каталоге шаблонов лаунчера; создание из
шаблона НЕ трогает соседние базы (никаких dt-дампов из живых ИБ). Адрес каталога
— в настройке 1С: `~/.1C/1cestart/1cestart.cfg`, ключ
`ConfigurationTemplatesLocation` (путь спросить у пользователя при первом
запуске и записать в НАСТРОЙКУ выше; в repo-копии остаётся пустым).

Структура: `<tmplts>/1c/<конфигурация>/<версия>/` (Enterprise20/2_5_27_70,
trade/11_6_1_59, Conversion/2_1_8_2, MDLP, acc ...), внутри:
- `1cv8.dt` — база с ДЕМО-данными (для демо-базы разворачивается как dt);
- `1cv8.cf` — чистая конфигурация (для пустой базы под доработку);
- `1cv8.cfu` — обновление, `1cv8upd*.htm` — описание релиза.

**Демо-база из шаблона** (dt → новая ИБ; платформа-приёмник ≥ версии шаблона;
ERP-класс ~2 ГБ dt льётся заметное время — фоном):

```sh
docker cp "<tmplts>/1c/<конф>/<версия>/1cv8.dt" <ct>:/tmp/tpl.dt
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd infobase create \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' --locale=ru --create-database --restore=/tmp/tpl.dt"
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase create ... --name=<name> ...   # attach, БЕЗ --create-database
docker exec <ct> rm -f /tmp/tpl.dt
# затем: ibases.v8i + контроль (summary list + PG)
```

**Пустая база из cf шаблона**: cf сначала в XML (скилл 1c-pack: ibcmd,
база-пустышка), затем `config import` + `apply --force` (раздел ниже) — или
`ibcmd infobase config load --file=<cf>`, если версия ibcmd его поддерживает.

## Создать dev-копию с фиксами DEVPATCH

Dev-копия = новая база из донора одним прогоном: конфигурация (копия PG
с данными ИЛИ import конфигурации из дерева XML — см. раздел про шаблоны
tmplts выше) + набор dev-фиксов + запись в ibases.v8i + проверка запуска.
Проверено 07.10 (копия живой базы → dev-конфигурация + набор фиксов).

**Набор фиксов** — две вещи в репо v8dock:
- `data/cfg/<имя>_dump/` — источник конфигурации: готовое дерево XML
  (распакованный cf/дамп из любого внешнего каталога) или пусто,
  если база делается PG-копией донора с данными;
- `data/cfg/<имя>_patch/` — файлы поверх дерева (фиксы). Каждый кодовый
  фикс несёт РОВНО ОДНУ метку `// DEVPATCH: <суть>` — все фиксы базы/набора
  находятся одним `grep -rn DEVPATCH`. Пример шаблона «ут-дев» (фиксы входа
  УТ 10.3 в локальных копиях, файлы от 07.10):
  - `ObjectModule.bsl` → Catalogs/Пользователи/Ext/ — NULL+1 в ПередЗаписью
    на пустом справочнике (`?(Выборка.х = Null, 0, х)`);
  - `OrdinaryApplicationModule.bsl` / `ManagedApplicationModule.bsl` → Ext/ —
    закомментирован Отказ по пустому паролю ИБ;
  - `Form.xml` → Documents/<Документ>/Forms/.../ — вычищены
    InputField с RegisterRecords-путями на ресурсы (без метки: правка
    сериализации, не код; см. раздел «Конфигурация живой базы»).

Порядок (копия с данными → шаг 1; чистая из дампа → шаг 2):

```sh
# 1) база-копия донора с данными: раздел «Копия базы X → Y» (PG pg_dump/restore + rac create)
# 2) чистая база с конфигурацией из дампа-шаблона:
#    rac infobase create (раздел «Создать базу»), затем доставить дерево и патчи:
docker cp "<путь к дереву-дампу>/." <ct>:/tmp/cfg_tpl
for f in <шаблон>_patch/*; do docker cp "$f" "<ct>:/tmp/cfg_tpl/<путь назначения>"; done   # по карте шаблона
# 3) import + apply --force (раздел «Конфигурация живой базы»; перед apply — сеансы!)
# 4) ibases.v8i (раздел выше; порт кластера см. там же)
# 5) контроль: контрольный export → grep -rn DEVPATCH (метки все на месте) +
#    запуск (ib-run.sh / session list)
```

Обновление шаблонной базы на новую конфигурацию = шаг 2 с новым деревом
(фиксы патч-папки накатываются поверх нового дампа; контексты в новой версии
могли уехать — перед накатом сверять grep-ом исходные строки фиксов).

## Восстановиться из ночного дампа

Ночной pg_dump кладёт `<db>.dump` в `$PG_BACKUP_DIR` (по умолчанию `data/backups`,
в контейнере смонтирован как `/backups`), дерево: `pg1c/<дата>/<db>.dump`.

```sh
docker exec pg1c sh -c 'PGPASSWORD=... createdb -U postgres <name>'   # как в копии
docker exec pg1c sh -c 'PGPASSWORD=... pg_restore -U postgres -d <name> /backups/pg1c/<дата>/<db>.dump'
# затем rac attach (create без --create-database), как выше
```

## Конфигурация живой базы: посмотреть / поправить (без конфигуратора)

ibcmd ходит прямо в серверную базу — выгрузка XML, правка, загрузка обратно
с обновлением конфигурации БД. Проверено на живой базе (07.10): export →
правка синонима в XML → import → apply (создано новое поколение КБД) →
повторный export содержит правку.

```sh
# выгрузить (дерево XML как из конфигуратора; ERP-класс ~600 МБ):
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd config export \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' /tmp/cfg_xml"
mkdir -p data/cfg && docker cp <ct>:/tmp/cfg_xml "data/cfg/<name>"   # на хост

# правка на хосте: модули .bsl, формы, метаданные — правила скилла 1c-pack

# загрузить обратно + обновить конфигурацию БД (apply ВСЕГДА с --force):
docker cp "data/cfg/<name>" <ct>:/tmp/cfg_xml
docker exec <ct> sh -c "cd $IBDIR && ./ibcmd config import \
  --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD' /tmp/cfg_xml && \
  ./ibcmd config apply --force --dbms=PostgreSQL --db-server=pg1c --db-name=<name> \
  --db-user=$PGUSER --db-pwd='$PGPWD'"
docker exec <ct> rm -rf /tmp/cfg_xml
```

Предупреждения:
- import — **замена конфигурации всем деревом**, не сравнение/объединение;
  дерево = полная выгрузка. Правки живых баз — только на dev-копиях.
- apply без `--force` виснет на интерактивном «Принять изменения [y/n]»;
  подсунуть y через пайп нельзя («Invalid seek» — ibcmd делает seek по stdin).
- import может упасть на «Неверный путь к данным: Объект.RegisterRecords.<Регистр>.<Поле>»:
  форма ссылается на РЕСУРСЫ регистров через RegisterRecords (конфигуратор это
  исторически прощал, валидатор XML — нет). Лечение: из Form.xml вычистить
  <InputField>-блоки с такими DataPath (пути уровня регистра и стандартные
  Active/LineNumber — валидны, не трогать):
  `perl -0777 -i -pe 's{[ \t]*<InputField\b[^>]*>(?:(?!</?InputField).)*?RegisterRecords\.<Регистр>\.(?:(?!</?InputField).)*?</InputField>\r?\n}{}gs' Form.xml`
  (паттерн регистра подставить свой). Правленую форму держать копией в
  data/cfg/<name>_patch/ — при следующем export она снова придёт битой.
- При правке модулей .bsl помечать правку комментарием `// dev-патч` и хранить
  патченные файлы в data/cfg/<name>_patch/ как воспроизводимый след.
- XDTO строг: языковые свойства имеют свой формат — синоним это
  `v8:item/v8:lang/v8:content`, не голый `v8:content`; «Ошибка XDTO при
  чтении свойства» = неверный формат вложенности, смотреть соседние объекты.
- Перед apply — раздел «Сеансы»: показать мешающих, terminate или дождаться
  закрытия.
- После config-операций drop ИБ может упасть на `55006 database is being
  accessed` — idle-соединение пула rphost; смотрим
  `pg_stat_activity WHERE datname=...`, `pg_terminate_backend(<pid>)`, и
  дропаем повторно (учесть: rac drop при первой неудаче уже снимает ИБ с
  регистрации — БД добивать `DROP DATABASE` в PG).

## Удалить базу

```sh
RAC_CONTAINER=<ct> ./src/scripts/rac.sh infobase drop --name=<name> --drop-database
```

`drop`, не remove. Без `--drop-database` ИБ только снимается с регистрации —
БД остаётся в PG (чистить отдельно). Перед удалением/перезаписью — прогнать
раздел «Сеансы» (показать мешающих, terminate или дождаться закрытия).
После drop — убрать запись из `ibases.v8i` (раздел выше).

## Грабли

- rac на кривые аргументы **молча печатает help** вместо ошибки — сверять
  синтаксис: `docker exec <ct> rac localhost:1545 infobase help --cluster=<uuid>`
  (uuid — из `rac.sh cluster list`).
- ibcmd требует версию платформы ≥ версии данных; ibcmd соседнего кластера
  новее — взять его контейнер, кластер-владелец не важен (ходит прямо в PG).
- pg_dump/pg_restore — только внутри одного мажора PG.
- Остановка фоновой задачи (TaskStop/убийство bash) НЕ убивает процесс,
  запущенный через `docker exec` — хост-клиент умирает, а ibcmd/pg_dump внутри
  контейнера продолжает работать (поймано 08.10: dt-дамп жил в контейнере
  после «остановки»). Проверять и добивать внутри:
  `docker exec <ct> sh -c 'for p in /proc/[0-9]*; do tr "\0" " " < $p/cmdline | grep -q ibcmd && kill $(basename $p); done'`
  (kill даётся с задержкой на завершение, при необходимости повторить).
- Рестарт контейнера-кластера убивает затянутый в /tmp файл (dt для restore)
  и оставляет битую наполовину созданную БД: перед повтором — DROP DATABASE,
  временные файлы копировать заново.
- В pg1c может отсутствовать POSTGRES_USER: `printenv POSTGRES_USER` вернёт
  пусто с rc=1 и МОЛЧА оборвёт `&&`-цепочку (симптом: «Exit code 1» без единой
  строки вывода). Читать из env только POSTGRES_PASSWORD; PGUSER = postgres.
- Патч модулей .bsl: ЕСТЬNULL — функция ТОЛЬКО языка запросов; в коде модуля
  не компилируется («Процедура или функция не определена»). Скриптовый
  эквивалент: `?(х = Null, 0, х)`; NULL-арифметика на пустых таблицах
  (МАКСИМУМ/СУММА без строк = NULL) — классика краха ПередЗаписью на
  пустых dev-копиях (первые же объекты с автонумерацией).
- Профиль rev82 (pg82/server1c82, ветка dev/82) — вне скилла: сеансов там нет.
- rac/ibcmd-операции лицензии не требуют; клиентские сеансы требуют живой .lic
  (healthcheck зелёный ≠ лицензия живая).

## Правила

1. Деструктивное (drop, restore поверх) — только по явной команде юзера, с
   подтверждением: показать список затрагиваемых баз и спросить.
2. Креды СУБД не выносить из машины; дампы рабочих баз конфиденциальны —
   не загружать в наружные сервисы.
3. Всё в контейнерах; на хосте — только `data/dumps/`. Временные файлы
   (`/tmp/*.dt`, `/tmp/*.dump`) в контейнерах удалять за собой.
4. После каждой операции — контрольная сверка (`summary list` + список БД PG).

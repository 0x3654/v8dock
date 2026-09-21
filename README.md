<div align="center">

# 🐘 v8dock

**1C:Enterprise dev stack in Docker on Apple Silicon**

PostgreSQL (1C build) + 1C:Enterprise 8.3 / 8.5 / 8.2 clusters + a fully
automated community-license activation stand — native arm64 containers on a Mac.

[What's inside](#-whats-inside) · [Quick start](#-quick-start) · [License](#-license-community--developers) · [Gotchas](#-gotchas-verified) · [Roadmap](#-roadmap) · [Русская версия](#русская-версия)

![Platform](https://img.shields.io/badge/platform-Apple%20Silicon%20%2B%20Docker-blue)
![1C](https://img.shields.io/badge/1C-8.3%20%7C%208.5%20%7C%208.2-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18.4--1.1C%20(1C%20build)-blue)
![Languages](https://img.shields.io/badge/languages-Shell%20%2B%20Python-yellowgreen)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

```
mac client ──┐                        ┌─ pg1c        PostgreSQL 18.4-1.1C arm64      :5432
              ├─ Docker on the Mac ───┼─ server1c83  1C cluster 8.3.27.2325 arm64    :1540-1591
win client ───┘                       ├─ server1c85  2nd cluster 8.5.1.1522 arm64    :2540-2591
   (Parallels,                        ├─ server1c82  8.2 playground (Rosetta)        :3540-3564
    optional)                         ├─ lic1c       license stand: thick client + epf  VNC :5900
                                      └─ pg82        PostgreSQL 9.1.9-1.1C (8.2 era)  :5433
```

> [!IMPORTANT]
> **Nothing 1C is bundled here.** The platform debs and the 1C-patched
> PostgreSQL build must be downloaded from [releases.1c.ru](https://releases.1c.ru/)
> (a free [developer.1c.ru](https://developer.1c.ru/) account) into `dists/`.
> Vanilla PostgreSQL is **not supported** by 1C — the 1C build is required.
> The free community license covers development only (≤ 3 sessions, 7-day
> validity, auto-renewal included).

> [!NOTE]
> Everything below was verified on Apple Silicon (macOS 26, Docker Desktop
> with Rosetta enabled). x86_64 Macs are untested; most of the stack has no
> Intel build anyway (1C server arm64 debs exist since 2026).

> [!IMPORTANT]
> **This branch carries the 8.2-era playground (rev82) — read before use.**
> There is **no license path for platform 8.2**: the free community license
> (the ПолучениеЛицензий API) only exists from platform 8.3.20, and the 8.2
> era was HASP-only. Real infobase sessions on this cluster are impossible —
> the playground exists purely for reverse-engineering the old MMC admin
> protocol (license-free admin operations). Besides, ragent 8.2 does not
> survive Rosetta/qemu in a container (documented dead end): only rmngr
> runs here; a fully working 8.2 agent lives on a Windows VM.

## 📦 What's inside

| Container | Image / compose profile | Purpose |
|---|---|---|
| `pg1c` | `pg1c:18.4-1.1C` | central DBMS for all infobases (native arm64 1C build) |
| `server1c-8.3.27.2325` | `server1c:8.3.27.2325` / `with-server` | 1C 8.3 cluster: ragent/rmngr/rphost/ras; hostname `server1c`, MAC pinned; **native arm64 + fake-cpuinfo** (Rosetta x86 fingerprint for the license, [see gotchas](#-gotchas-verified)); Rosetta fallback image `:8.3.27.2325-amd64` |
| `server1c-8.5.1.1522` | `server1c:8.5.1.1522` / `with-server` | second cluster (platform 8.5): same hostname/MAC and shared license volume, its own bridge network; host ports shifted to 2540/2541/2560-2591, clients use `Srvr="server1c:2540"` |
| `lic1c` | `lic1c:8.3.27.2325-amd64` / `license` | license activation stand: **thick client only** (amd64/Rosetta — the x86 fingerprint is consistent with the server license), its own network so it runs **while the server is up**; disposable container. Opens a file infobase directly (`/F`, no ibsrv) and runs an epf automaton — or the classic Configurator wizard over VNC `vnc://localhost:5900` |
| `lic1c85` | `lic1c85:8.5.1.1522` / `license` | the same stand built on platform 8.5 (VNC :5901) — for a no-CPU-binding license valid on 8.3 as well |
| `server1c82` + `pg82` | `server1c82:8.2.19-130`, `pg82:9.1.9-1.1C` / `rev82` | the 8.2-era playground (old admin protocol reverse engineering): Rosetta, squeeze; 8.2 agent in a container is a dead end (ragent daemonizes → dies under emulation), rmngr lives |

Repo layout: the root holds what the running stand needs (`docker-compose.yml`,
`.env`, `bootstrap.sh`, `dists/`); everything build/dev-only lives in `src/`
(Dockerfiles, entrypoints, build scripts, the epf sources, mac/win client
helpers — see the tree in the [Russian version](#русская-версия)).

The **base images live on [Docker Hub](https://hub.docker.com/u/0x3654)**:
`docker.io/0x3654/1c-base:latest` (arm64) and `docker.io/0x3654/lic1c-base:latest`
(multi-arch arm64+amd64 — the Rosetta license stand gets the amd64 variant
from the same tag, no suffix). The version Dockerfiles reference them
directly in `FROM`, so a plain `docker compose build` works out of the box.
Bases contain debian packages only, no 1C binaries; CI rebuilds them only
when `src/Dockerfile.base` changes. Local override — build under the same
tag (docker prefers a local image): `./src/scripts/build.sh --bases`.
Everything embedding 1C distributions (pg1c, server1c, lic1c*) is always
built locally from your `dists/` and never published.

## 🚀 Quick start

Prerequisites: Docker Desktop (Rosetta enabled) and a developer.1c.ru account.

```bash
git clone https://github.com/0x3654/v8dock && cd v8dock
./bootstrap.sh                # pg1c + 8.3 server + license stand (the default set)
# extra flags: --with-85 (2nd cluster) · --with-82 (8.2 playground) · --no-server (DB only)
```

`bootstrap.sh` does four things and stops at the first problem:

1. **`.env`** — creates it from `.env.example`, generating a random
   `POSTGRES_PASSWORD`. Two credentials live there:
   | Variable | What it is |
   |---|---|
   | `POSTGRES_PASSWORD` | DB superuser password (used by 1C infobases and `psql`) |
   | `DEV_LICENSE_LOGIN` / `DEV_LICENSE_PASSWORD` | developer.1c.ru account — needed **only** for the first license activation; renewal is automatic and needs no login |
2. **`dists/` check** — verifies the downloaded 1C distributions (see the
   table below) and prints exact download links for anything missing;
3. **build** — base stub images + version images;
4. **up** — `pg1c` first (waits for healthy), then the server cluster.

### What to download into `dists/`

Everything comes from [releases.1c.ru](https://releases.1c.ru/) (login with
the developer.1c.ru account); unpack archives so the files land in `dists/`:

| Page | Version | Files |
|---|---|---|
| [PostgreSQL для 1С](https://releases.1c.ru/project/AddCompPostgre) | 18.4-1.1C, Debian 12 ARM — **the 1C build is mandatory** | `postgresql_18.4_1_debian_12.11_aarch64_package.tar.bz2` |
| [Platform83](https://releases.1c.ru/project/Platform83) → «Сервер 1С:Предприятия (64-bit ARM)» | 8.3.27.2325, section «Linux (arm64)» | `1c-enterprise-8.3.27.2325-common_8.3.27-2325_arm64.deb` + `…-server_…_arm64.deb` (both inside the server zip; there is no separate common archive for arm) |
| [Platform83](https://releases.1c.ru/project/Platform83) → «Клиент 1С:Предприятия» x64 | 8.3.27.2325 (for the license stand) | `…-client_…_amd64.deb`; the amd64 common+server debs come from the x64 server zip — the stand needs server libs too (see gotchas) |
| [Platform85](https://releases.1c.ru/project/Platform85) | 8.5.1.1522 (`--with-85`) | common + server arm64 debs, same naming scheme |
| [Platform82](https://releases.1c.ru/project/Platform82) + [AddCompPostgre](https://releases.1c.ru/project/AddCompPostgre) 9.1.9-1.1C | 8.2.19-130 (`--with-82`) | `1c-enterprise82-{common,server}_8.2.19-130_amd64.deb` + `postgresql_9_1_9_1_1C_x86_64_deb_tar.bz2` (**not** 9.2.4-1.1C — that one is already 8.3.3+) |

### After bootstrap: three manual steps

```bash
# 1. hosts entries (clients resolve the cluster name themselves):
#      mac:     192.0.2.10 server1c    <- then install the pf daemon (README "Mac networking")
#      Windows: 10.211.55.2 server1c
# 2. first license activation (free, ≤3 sessions per infobase):
#      put DEV_LICENSE_LOGIN/PASSWORD into .env, then:
./src/scripts/license-renew.sh first
# 3. install a 1C client on your machine (see "Clients" in the Russian version)
#    and create an infobase: Srvr="server1c", DB server pg1c, user postgres
```

### Running another platform version

Versions are parameterized; a commented **NEW PLATFORM VERSION TEMPLATE**
block sits right in `docker-compose.yml` (4 steps: download debs → uncomment →
declare the volume/network → `SERVER_VERSION=… docker compose --profile
with-server up -d`). One version at a time on the same bridge (MAC pinned),
or several with the port-offset pattern of `server1c85`.

```bash
./src/scripts/build-server.sh 8.3.27.2340     # any version, debs in dists/
SERVER_VERSION=8.3.27.2340 docker compose --profile with-server up -d
```

## 🔑 License (community / for developers)

Free, covers **client and server**, ≤ 3 sessions per infobase, development only, 7-day
validity. Slot state: [developer.1c.ru console](https://developer.1c.ru/applications/Console?state=community).
Renewal does not take a new slot — it renews the existing one, and it works
**without any login** (machine-bound).

- `./src/scripts/license-renew.sh` — renewal (the epf automaton; the default);
- `./src/scripts/license-renew.sh first` — first activation with
  `DEV_LICENSE_*` creds from `.env`; needs a free account slot;
- fallback: the official Configurator wizard over VNC
  (`vnc://localhost:5900`, password `1clicens`) — commands in the Russian version.

The mac thick client renews its own license **at every start** (machine-bound,
no login); a launchd timer (`src/mac/com.user.1c-license-renew.plist`, Mon/Thu
03:37) starts it hidden at night — see `src/mac/install-client.sh`.
The client license requires `/var/1C/licenses` to exist on the mac — a
one-time `sudo mkdir` (the macOS installer never creates it; details in
[Gotchas](#-gotchas-verified)).

## 🪜 Gotchas (verified)

The full war-stories list with diagnostics lives in the
[Russian version](#русская-версия) — read it before debugging anything
license- or network-related. The short list:

- **License fingerprint**: a software license binds to CPU+RAM+disk+container
  MAC (not the account login). On Apple Silicon the x86 fingerprint is only
  visible under Rosetta → native arm64 servers validate the license via a
  bind-mounted fake `/proc/cpuinfo` (`src/conf/cpuinfo-virtualapple`,
  privileged container). Platform 8.5 computes its fingerprint differently
  (no CPU fields) — hence the separate 8.5 license stand.
- **`/var/1C/licenses` on the mac must be created by hand once** — otherwise
  the client says "license received" and silently saves nothing.
- **`nethasp.ini` with `NH_TCPIP = Disabled` is mandatory** in client conf
  dirs — without it the platform scans the network for HASP keys while
  collecting the machine fingerprint and license requests loop.
- **epf rebuilds go only through `src/scripts/build-epf.py`**: only the
  xDrivenDevelopment/v8unpack 3.0.1 fork packs working containers; the form
  module's **byte length must not change**; a module compile error is a
  *silent* `/Execute` skip.
- **Healthcheck ≠ sessions**: a green container says nothing about the license
  being alive — open an infobase to verify.
- **Thick client cannot connect to ibsrv directly** (only the thin client can).
- Don't publish the full 1560-1591 range — the Configurator debugger on the
  mac binds ports from it ("Address already in use").
- The license stand needs the **server deb** too (common+client+server):
  in `/F` mode the thick client loads server context from server libs,
  without them it segfaults under Xvfb.
- The mac client resolves `server1c` via hosts to a black-hole IP
  (192.0.2.10) + route + pf redirect — see "Сеть на маке" in the Russian
  version; "same computer" detection kills the client otherwise.

> [!IMPORTANT]
> **Known limitation — 8.5 client connections.** The 8.5 cluster itself is
> healthy and rac-administered, but thick/thin clients currently reject it
> ("not a cluster server address"): 8.5 answers in a new wire protocol the
> released clients do not accept yet. 8.3 is fully usable end-to-end; 8.5
> is cluster-side only for now (details in the Russian gotchas).

## 🗺 Roadmap

- [x] automated first activation (epf automaton) — only account slots limit it
- [x] license stand without server downtime (separate lic-net)
- [x] 8.5 as a separate container (port-offset second cluster)
- [x] shared infobase list between mac/win clients
- [ ] backup retention policy
- [ ] ansible role: template-driven version builds + compose generation on
  deploy (versions/volumes/ports as role parameters); remote hosts without
  the mac pf dance
- [ ] a second Mac as a client over Tailscale

---

## Русская версия

# 🐘 v8dock — весь дев-стек 1С в Docker на Apple Silicon

> **Ветка dev/82: здесь живёт 8.2-полигон (profile rev82).**
> **Комьюнити-лицензия на 8.2 работать не будет** — API «Получение лицензии»
> появился только в 8.3.20, эпоха 8.2 — чистый HASP. Реальные сеансы ИБ на
> этом кластере невозможны: полигон существует только для реверса старого
> админ-протокола MMC (админ-операции лицензии не требуют). К тому же
> ragent 8.2 не выживает под Rosetta/qemu в контейнере (документированный
> тупик) — здесь живёт только rmngr; полностью рабочий 8.2-агент — на
> Windows-вирталке. Основная ветка (`main`) 8.2 не содержит.

PostgreSQL 18 (сборка 1С) + серверы 1С:Предприятия 8.3 / 8.5 / стенд активации
комьюнити-лицензии — нативные arm64-контейнеры на маке. Клиенты — мак и
Windows (Parallels, опционально; без него тоже работает). Полигон 8.2 — под
Rosetta.

```
мак-клиент ──┐                       ┌─ pg1c      PostgreSQL 18.4-1.1C arm64 :5432
             ├─ Docker на маке ──────┼─ server1c83 кластер 1С 8.3.27.2325 arm64 :1540-1591
винда ───────┘                       ├─ server1c85 кластер 8.5.1.1522 arm64    :2540-2591
(Parallels,                          ├─ server1c82 полигон 8.2 (Rosetta)       :3540-3564
 опционально)                        ├─ lic1c     стенд лицензии: толстый клиент + epf (только клиент), VNC :5900
                                     └─ pg82      PostgreSQL 9.1.9-1.1C, эпоха 8.2 :5433
```

[Навигация](#структура-репо) · [Быстрый старт](#быстрый-старт) · [Лицензия](#лицензия-комьюнити--для-разработчиков) · [Грабли](#грабли-проверено) · [Roadmap](#roadmap-1)

## Структура репо

В корне — то, чем работающий стенд живёт; в `src/` — всё, что нужно только
при сборке болванок и для «разработки» (правки образов, epf, клиенты):

```
docker-compose.yml     # pg1c + server1c83/85 (версии = env) + lic1c/85 (profile license) + rev82
bootstrap.sh           # онбординг одной командой: .env → проверка dists/ → сборка → подъём
.env / .env.example    # секреты (POSTGRES_PASSWORD, DEV_LICENSE_*) — .env в гитигноре
dists/                 # скачанные дистрибутивы (гитигнор; что качать — выше в англ. версии)
src/
  Dockerfile           # pg1c (PG 18.4-1.1C arm64)
  Dockerfile.base      # ОСНОВЫ: docker.io/0x3654/{1c-base,lic1c-base} (без 1С, публикуемые)
  Dockerfile.server    # сервер 1С: добавка к 1c-base, версия параметром
  Dockerfile.license   # стенд лицензии: arm-клиент (ЭКСПЕРИМЕНТАЛЬНЫЙ — клиент
                       # сегфолтится под Docker Desktop 4.89, см. грабли)
  Dockerfile.license.amd64 # стенд лицензии: РАБОЧИЙ вариант (Rosetta, x86-отпечаток
                       # консистентен серверной лицензии)
  Dockerfile.server.amd64 # запасной Rosetta-вариант сервера
  Dockerfile.server82  # полигон 8.2 (wheezy/Rosetta)
  Dockerfile.pg82      # pg82: PostgreSQL 9.1.9-1.1C, эпоха 8.2 (squeeze/Rosetta)
  conf/                # тюнинг postgresql для 1С + эталон cpuinfo (fake-cpuinfo)
  entrypoints/         # entrypoint-скрипты образов
  scripts/             # bootstrap-хелперы: build.sh, build-pg.sh / build-server.sh
                       # <версия>, build-epf.py, license-renew.sh [first], rac.sh
  backup/              # pg-backup.sh — ночной дамп PG (launchd)
  license-epf/         # epf-автомат: Форма.bsl (исходник) + license.epf (сборка)
  mac/ win/            # клиентские настройки мака (LaunchDaemon) и винды (symLink)
```

## Состав

| Контейнер | Образ / profile | Назначение |
|---|---|---|
| `pg1c` | `pg1c:18.4-1.1C` | центральная СУБД всех ИБ (нативная arm64-сборка 1С) |
| `server1c-8.3.27.2325` | `server1c:8.3.27.2325` / `with-server` | ragent/rmngr/rphost/ras, hostname `server1c`, MAC закреплён; **нативный arm64 + fake-cpuinfo** (отпечаток Rosetta для x86-лицензии, см. грабли); Rosetta-запас — образ `:8.3.27.2325-amd64` |
| `server1c-8.5.1.1522` | `server1c:8.5.1.1522` / `with-server` | второй кластер (8.5): те же hostname/MAC и общий том лицензий, отдельная сеть `srv85-net`; свой диапазон портов 2540/2541/2560:2591, клиент пишет `Srvr="server1c:2540"` |
| `lic1c` | `lic1c:8.3.27.2325-amd64` / `license` | стенд лицензии: **только клиент** (amd64/Rosetta — отпечаток x86 консистентен серверной лицензии), отдельная сеть `lic-net` — поднимается при работающем сервере, контейнер разовый; толстый клиент открывает файловую ИБ напрямую (`/F`, без ibsrv) и исполняет epf-автомат; arm-вариант образа (`src/Dockerfile.license`) — экспериментальный (arm-клиент сегфолтится, рабочий — amd64) |
| `lic1c85` | `lic1c85:8.5.1.1522` / `license` | тот же стенд на платформе 8.5 (VNC :5901): 8.5 считает отпечаток иначе (CPU-поля пустые), лицензия с него — без привязки к CPU |
| `server1c82` + `pg82` | `server1c82:8.2.19-130`, `pg82:9.1.9-1.1C` / `rev82` | полигон реверса старого админ-протокола: 8.2-агент в контейнере — тупик (ragent демонизируется и умирает под эмуляцией), rmngr жив; СУБД эпохи — PostgreSQL 9.1.9-1.1C (последняя сборка 1С под платформы ниже 8.3.3; 9.2.4-1.1C — уже 8.3.3+, на 8.2 «timestamp out of range»), squeeze + Rosetta, md5 |

Слои образов — ОСНОВА + тонкие добавки версий (deb идут через bind-mount
и в слоях не остаются; рост платформы 1С раздувает только добавку, основа общая).

Основы живут на [Docker Hub](https://hub.docker.com/u/0x3654):
`docker.io/0x3654/1c-base:latest` (arm64) и `docker.io/0x3654/lic1c-base:latest`
(мульти-арх arm64+amd64 — Rosetta-стенд лицензий получает amd64-вариант из
того же тега, без суффиксов). Dockerfile'ы версий ссылаются на них прямо
в `FROM` — обычный `docker compose build` работает из коробки. Внутри основ
только debian-пакеты, без бинарников 1С; CI пересобирает их только при
изменении `src/Dockerfile.base`. Локальный оверрайд — собрать под тем же
тегом (docker предпочитает локальный образ): `./src/scripts/build.sh --bases`.
Всё, что встраивает дистрибутивы 1С (pg1c, server1c, lic1c*), всегда
собирается локально из `dists/` и никогда не публикуется.
lic1c НЕ наращивается на server1c — ветки параллельные, общие слои
(debian + 1c-base) на диске хранятся один раз.

**Проверено на** (09.2026): мак Apple Silicon (arm64), Docker Desktop
(containerd-хранилище, overlayfs; Rosetta включена — для запасного
`src/Dockerfile.server.amd64`). Живой стенд: `pg1c` и оба кластера healthy,
лицензия получается/продлевается epf-автоматом и launchd-таймерами (сервер
и клиент), ночной бэкап PG работает.

Сборка всего: `./src/scripts/build.sh` (основы + версии; `--no-base` — только
версии). Основа собирается из `src/Dockerfile.base` и не зависит от версий
платформы — публикуема (внутри только debian-пакеты).

### Конкретная версия платформы

В `docker-compose.yml` есть закомментированный блок-шаблон **NEW PLATFORM
VERSION TEMPLATE** (4 шага: скачать deb → раскомментировать → объявить том и
сеть → поднять с `SERVER_VERSION=…`). То же руками:

```bash
# 1. deb нужной версии в dists/ (архив с releases.1c.ru, см. «What to download»)
# 2. собрать образ (имена deb вычислятся сами, основа переиспользуется):
./src/scripts/build-server.sh 8.3.27.2340          # или 8.5.1.1343 — любая
# 3. для новой версии добавить том "srv1c-<версия>-data:" в volumes compose
# 4. поднять:
SERVER_VERSION=8.3.27.2340 docker compose --profile with-server up -d
```

PostgreSQL — той же схемой (архив 1С-сборки в `dists/`, имя вычислится
по маске, дебиан-минорник в имени архива между релизами плавает):

```bash
./src/scripts/build-pg.sh 17.10-1.1C
PG_VERSION=17.10-1.1C docker compose up -d pg1c
```

Смена мажора PG — отдельный том: кластер в `pg1c-data` лежит по пути
`/var/lib/postgresql/<мажор>/main`, под другим мажором поднимется
**пустая** база.

Второй кластер 8.5 живёт отдельным сервисом `server1c85` (env `SERVER85_*`,
том `srv1c-8.5.1.1522-data` объявлен). Как в обычном мире: второй кластер
на той же машине — **свой диапазон портов** при общем hostname
(`ragent -port 2540 -regport 2541 -range 2560:2591` в `command:` сервиса);
клиент выбирает кластер портом в адресе записи ИБ: `Srvr="server1c:2540"`.
MAC общий с 8.3 (лицензия одна на оба) → серверы в разных L2 (`srv85-net`),
одновременно работать могут. Грабля: порты зашиваются в реестре кластера
(srvinfo) при его создании — смена `command:` у живого кластера НЕ переезжает,
нужно пересоздавать том (у пустого тестового — дёшево).

Одновременно на одном мосту — только одна версия (MAC закреплён, привязка
лицензии); несколько версий — паттерн `server1c85` (своя сеть + сдвиг портов).
Data-том у каждой версии свой (srvinfo несовместим между ветками),
лицензионный том `srv1c-lic` — общий: серверная лицензия без привязки к CPU
действительна на всех arm-кластерах.

Тома: `pg1c-data` (данные СУБД), `srv1c-<версия>-data` (srvinfo кластера,
переживает пересоздание контейнера), `srv1c-lic` (`/var/1C/licenses`, один
на все версии). **MAC контейнера зашит в compose** — программная лицензия 1С
привязана к нему.

Порты: `5432` (PG), `1540-1541, 1545, 1560-1564` (кластер 8.3; остальной
диапазон 1560-1591 на хосте оставлен отладчику Конфигуратора),
`2540-2541, 2545, 2560-2564` (кластер 8.5 — свой диапазон, зеркально 8.3;
клиент: `Srvr="server1c:2540"`), `3540-3541, 3560-3564` (полигон 8.2),
`5433` (pg82; винда: `10.211.55.2:5433`), `127.0.0.1:5900/5901` (VNC стендов
лицензий).

## Быстрый старт

```bash
git clone https://github.com/0x3654/v8dock && cd v8dock
./bootstrap.sh        # .env → проверка dists/ → сборка → подъём; флаги: --with-85 --with-82 --no-server
```

Что делает bootstrap: создаёт `.env` (пароль PG генерируется; креды
`DEV_LICENSE_*` для первой активации — дописать руками), проверяет
`dists/` на недостающие файлы и печатает ссылки на releases.1c.ru, собирает
основы и версии, поднимает `pg1c` (ждёт healthy), затем кластер. Дальше три
ручных шага (hosts + pf-демон, первая активация лицензии, установка клиента) —
см. англ. Quick start и разделы ниже.

## Установка (руками, без bootstrap)

```bash
# 1. пароль СУБД
cp .env.example .env 2>/dev/null || echo 'POSTGRES_PASSWORD=меняй' > .env

# 2. собрать и поднять (шрифты MS Core Fonts и зависимости уже в образах)
docker compose --profile with-server up -d --build
docker compose ps   # ждём pg1c healthy

# 3. hosts-записи (править руками)
#    мак:    192.0.2.10 server1c     <- см. «Сеть на маке» ниже, обязательно
#    винда (если Parallels): 10.211.55.2 server1c

# 4. мак: сетевой демон (роут + pf-редирект, автозапуск)
sudo cp src/mac/server1c-net.sh /usr/local/bin/
sudo cp src/mac/com.user.server1c-net.plist /Library/LaunchDaemons/
sudo launchctl bootstrap system /Library/LaunchDaemons/com.user.server1c-net.plist

# 5. лицензия — см. следующий раздел
```

## Лицензия (комьюнити / для разработчиков)

Бесплатная, покрывает клиент **и сервер**, ≤3 сеансов **на ИБ**, только
разработка и отладка, срок 7 дней. Слоты аккаунта (лимит 3) и их состояние:
[developer.1c.ru/applications/Console?state=community](https://developer.1c.ru/applications/Console?state=community).
Продление не занимает новый слот — продлевает существующий, и работает
**без учётных данных** (машинное).

### Автоматика: `./src/scripts/license-renew.sh [first]`

Раннер поднимает lic1c (сервер не останавливается) и запускает толстый клиент
на файловой ИБ `license-ib` напрямую (`/F`, ibsrv не нужен) с внешней
обработкой `src/license-epf/license.epf` — она штатным API платформы
(`ПолучениеЛицензий`, есть с 8.3.20) получает/продлевает лицензию и пишет лог
хода в `license-result.txt`. Гасит всё за собой.

- `./src/scripts/license-renew.sh` — **продление** (без учётных данных);
- `./src/scripts/license-renew.sh first` — **первичная активация**: креды
  `DEV_LICENSE_LOGIN/PASSWORD` из `.env`; нужен свободный слот аккаунта;
- клиент в lic1c — без вопросов безопасности
  (`DisableUnsafeActionProtection=.*license.*`, значение — регэксп, рецепт
  [habr 928572](https://habr.com/ru/articles/928572/)).

Правка обработки: исходник `src/license-epf/Форма.bsl`, сборка без
Конфигуратора: `python3 src/scripts/build-epf.py` (v8unpack -BUILD; о трёх
граблях epf — ниже и в docstring скрипта).

### Клиент мак-а: автопродление + обязательный каталог

Клиентская лицензия продлевается **при каждом старте клиента** (машинное,
без логина). launchd-таймер пн/чт 03:37 (`src/mac/com.user.1c-license-renew.plist`)
запускает клиента скрытно (`open -g -j` — окно не появляется) и гасит через
90 сек. Установка: `sh src/mac/install-client.sh` (он же создаёт
`/var/1C/licenses` — см. грабли, без них лицензия «получается» и молча
не сохраняется).

### Запасной выход: VNC-мастер (первичная активация с нуля)

Если слоты заняты/epf не вариант — официальный способ: мастер в Конфигураторе
на «машине сервера»:

```bash
docker compose --profile license up -d lic1c
docker exec -d lic1c setpriv --reuid=999 --regid=1000 --clear-groups \
  env HOME=/home/usr1cv8 DISPLAY=:0 LANG=ru_RU.UTF-8 \
  /opt/1cv8/x86_64/8.3.27.2325/1cv8 DESIGNER /F /home/usr1cv8/license-ib
open vnc://localhost:5900     # пароль: 1clicens; Сервис → Получение лицензии
docker compose --profile license rm -sf lic1c
```

## Создание информационной базы из 1С

Клиент → «Добавить» → «Создание новой информационной базы» → «без
конфигурации» → клиент-серверный вариант. Поля страницы параметров, в порядке
мастера:

| Поле | Значение |
|---|---|
| Сервер 1С:Предприятия | `server1c` |
| Имя информационной базы | `erp_demo` |
| Тип СУБД | `PostgreSQL` |
| Сервер баз данных | `pg1c` |
| Имя базы данных | `erp_demo` |
| Пользователь базы данных | `postgres` |
| Пароль базы данных | `<POSTGRES_PASSWORD из .env>` |
| Создавать базу данных в случае её отсутствия | включить |
| Язык (страна) | `Русский` |

Отдельных полей «порт» в мастере нет (1540 и 5432 — стандартные).
Адрес СУБД резолвит сам сервер в docker-сети, поэтому `pg1c`, а не IP мака.

То же одной командой:

```bash
docker exec server1c-8.3.27.2325 rac localhost:1545 infobase create \
  --cluster=$(docker exec server1c-8.3.27.2325 rac localhost:1545 cluster list | awk '/^cluster/{print $3}') \
  --create-database --name=erp_demo --dbms=PostgreSQL \
  --db-server=pg1c --db-name=erp_demo --locale=ru \
  --db-user=postgres --db-pwd=<POSTGRES_PASSWORD>
```

**Имя ИБ = имя БД в PG: латиница, нижний регистр, без пробелов в конце.**
Пробел в конце имени однажды дал вторую «фантомную» ИБ и невосстановимую
ошибку «запрещенная комбинация текущей области и указанного поколения».

## Клиенты 1С на рабочие машины

| Машина | Что ставить | Ссылка |
|---|---|---|
| macOS | «1С:Предприятие 8.3.27 macOS» — сборка **x86_64** (ARM-сборки клиента 8.3 не существует), на Apple Silicon работает через Rosetta 2 | [releases.1c.ru · 8.3.27.2325](https://releases.1c.ru/version_files?nick=Platform83&ver=8.3.27.2325) |
| Windows | «1С:Предприятие 8.3.27 x64» | [та же страница](https://releases.1c.ru/version_files?nick=Platform83&ver=8.3.27.2325) |
| любой | тонкий клиент бесплатно | [online.1c.ru/catalog/free](https://online.1c.ru/catalog/free/) |

## Общие файлы клиентов мак/винда (`~/.1c-storage`)

Список баз (`ibases.v8i`), `conf.cfg` и шаблоны конфигураций — одна копия на
оба клиента, склад на маке (скрытый `~/.1c-storage`; имя `~/.1C` занято
платформой — там `1cestart/`, и APFS регистронезависима). Путь шаблонов
в настройке — `~/.1C/1cestart/1cestart.cfg`,
`ConfigurationTemplatesLocation=<домой>/.1c-storage/tmplts`.

| Файл в `~/.1c-storage/` | Мак (симлинки из `~/.1cv8/1C/1cv8/`) | Винда |
|---|---|---|
| `ibases.v8i` | `ibases.v8i` | `%APPDATA%\1C\1CEStart\ibases.v8i` **+** `%APPDATA%\1C\1cv8\ibases.v8i` (обе точки — см. грабли) |
| `conf.cfg` | `conf/conf.cfg` | `%APPDATA%\1C\1cv8\conf\conf.cfg` |
| `tmplts/` | `tmplts` (дефолтный каталог шаблонов) | `%APPDATA%\1C\1cv8\tmplts` (подтверждено `1CEStart\1cestart.cfg`) |

### `conf.cfg` — язык интерфейса клиента

Мак-клиент при старте выбирает язык интерфейса по локали macOS. Файл
`~/.1c-storage/conf.cfg` с одной строкой задаёт язык принудительно, независимо
от локали:

```ini
SystemLanguage=RU
```

Действует на оба клиента через симлинки из таблицы выше. Другие известные
опции — `Options=DisableUnfoldedWorkstations`, `UseHardwareEncryption=0` — при
необходимости дописывать в тот же файл.

Мак-клиент использует linux-раскладку `~/.1cv8` (не `~/Library`!). На винде
симлинки ставит повторяемый `src/win/link-1c-shared.cmd` (админ; **склад —
мастер-копия**, локальные файлы уходят в `.bak`). Формат `ibases.v8i`
кроссплатформенный: винда пишет UTF-8 BOM + CRLF, мак читает; правки с любой
стороны летят в один файл — одновременно оба клиента не открывать (последний
запись выигрывает). Установку шаблонов на винде направлять в шару
`\\Mac\1C\tmplts` (Parallels Sharing, диск `X:`, соответствует `~/.1c-storage`
мака). Клиент-серверные записи `Srvr="server1c"` кроссплатформы (hosts
настроен с обеих сторон); недостижимые записи в списке просто лежат, клиент
ругается только при попытке подключения.

## Эксплуатация

```bash
docker exec -it pg1c psql -U postgres -h 127.0.0.1 -c '\l'    # базы
docker exec pg1c pg_dump -U postgres -h 127.0.0.1 -Fc erp_demo > erp_demo.dump

docker exec server1c-8.3.27.2325 rac localhost:1545 infobase summary list \
  --cluster=<uuid>          # список ИБ кластера
docker exec server1c-8.3.27.2325 rac localhost:1545 cluster list   # uuid кластера
```

Администрирование кластера с мака — обёртка `src/scripts/rac.sh` (uuid кластера
подставляется сам; GUI-консоли 1С под macOS не существует, rac — штатный
инструмент для Linux-кластеров). Для повседневной работы удобнее TUI: наша
[**lazy1c**](https://github.com/0x3654/lazy1c) — консоль кластеров 1С в духе lazydocker (свой транспорт RAS, без
веб-сервера и зависимостей кластера):

```bash
src/scripts/rac.sh session list          # сеансы; cluster/infobase/lock/... — так же
RAC_CONTAINER=server1c-8.5.1.1522 src/scripts/rac.sh session list   # кластер 8.5
```

### Консоль администрирования (GUI) на винде: 32-битная схема

Винда (Parallels) — **ARM64**, а консоль 1С — x64-DLL в ARM64-mmc: не грузится
в принципе (err 193; известная болячка Win11 ARM 23H2+). Рабочая схема —
32-битная оснастка из win32-дистрибутива (реализовано, см. `src/win/`):

- `C:\Program Files (x86)\1cv8\<версия>\bin\` — x86 radmin.dll + полный набор
  x86-DLL (вытащены `expand.exe`-ом из `Data1.cab` win32-дистрибутива;
  bsdtar на маке каб InstallShield не читает); msc — в `...\common\`
- лаунчеры `C:\Windows\console83.cmd` / `console85.cmd` (копии в `src/win/`):
  следят, чтобы 32-битная регистрация указывала на их версию (переключение
  требует прав администратора — при нехватке лаунчер честно ругнётся, а не
  откроет консоль с чужой оснасткой), и стартуют `SysWOW64\mmc.exe`. Две
  консоли можно держать открытыми одновременно: версия фиксируется в памяти
  mmc при запуске, регистрация нужна только следующему запуску
- ярлыки «Консоль администрирования 8.3/8.5 (32-бит)» — в Пуске, в папке
  «1C Enterprise 8 (x86-64)», рядом с официальными

Первый запуск: в консоли «Центральные серверы 1С:Предприятия 8.3» → ПКМ →
Создать → имя `server1c`, порт `1540` (8.5-консоль — `2540`, и она
администрирует только 8.5-кластер: версии консоли/сервера обязаны совпадать).

Подключение к PG: мак — `localhost:5432`, винда — `10.211.55.2:5432`,
контейнеры — `pg1c:5432`. Всегда пользователь `postgres`.

## Сеть на маке (почему 192.0.2.10)

Кластер отдаёт клиентам своё имя `server1c`, каждый клиент резолвит его сам.
Если мак резолвит его в свой адрес — клиент решает «сервер на этом же
компьютере» и падает. Поэтому: hosts ведут на `192.0.2.10` (никому не
принадлежит), роут заворачивает его на loopback, pf (`src/mac/server1c-net.sh`)
редиректит на `127.0.0.1`, где слушает докер-прокси. Оба диапазона кластеров
покрыты rdr-правилами: `1540:1591` (8.3) и `2540:2591` (8.5). Всё это поднимает
LaunchDaemon `com.user.server1c-net`. **`/etc/pf.conf` не редактировать** —
правило вставляется на лету.

Диагностика, если клиент висит на `server1c:1541 timeout`:

```bash
nc -z -G 3 192.0.2.10 1540     # FAIL -> sudo /usr/local/bin/server1c-net.sh
tail /var/log/server1c-net.log
```

## Грабли (проверено)

- `nc -z` с мака на опубликованный порт докера даёт ложный позитив — проверять
  `/proc/net/tcp` внутри контейнера (1541 = `0605`).
- lic1c — только debian:11: клиенту нужен webkit 4.0/libsoup2, в debian:12
  только 4.1/libsoup3 («libsoup2 symbols detected»).
- `rac` при ошибке в аргументах молча печатает help; правильное: `infobase
  summary list`, `infobase drop` (не remove).
- Винда-клиент, запущенный через лаунчер «1C:Предприятие» (ярлык из
  Parallels/тонкого клиента), держит список баз в `%APPDATA%\1C\1CEStart\`
  — классический `1cv8\ibases.v8i` он не читает. Отсюда «список не
  синхронизируется»: линковать надо **обе** точки, что `src/win/link-1c-shared.cmd`
  и делает. Профиль платформы (`.pfl`, `conf.cfg`, `tmplts`) при этом
  как лежал, так и лежит в `1cv8\`.
- Склад на винде — только через шару `\\Mac\1C` (Parallels Sharing, диск
  `X:`, соответствует `~/.1c-storage` мака — шара настраивается правилом
  `prlctl set <имя-ВМ> --shf-host-add 1C --path <домой>/.1c-storage`).
  Путь `\\Mac\Home\...` **не работает**:
  `\\Mac\Home` расшаривает лишь профильные папки (Desktop/Documents/…),
  остальных путей там просто нет. Симлинк на такую «мёртвую» цель роняет
  лаунчер: процесс молча умирает секунд через 5 после запуска, без ошибок
  и без записей в журнале.
- Пересоздание контейнера (up без --build) откатывает живые правки apt — всё
  постоянное должно быть в Dockerfile.
- **Толстый клиент (1cv8) не умеет прямое подключение к ibsrv** («Адрес
  tcp://…:9541 не является адресом кластера серверов») — только тонкий (1cv8c;
  он входит в пакет `client`, отдельный thin-client deb с ним конфликтует).
- Дебаггер Конфигуратора на маке биндит порт из 1560-1591: не публиковать
  весь диапазон из докера (у нас 1560-1564), иначе «Ошибка загрузки сетевой
  инфраструктуры отладчика / Address already in use».
- `ТекущаяДатаСеанса` — только серверный контекст; на клиенте компилятор
  требует `ТекущаяДата()`.
- Клиент 1С под Linux ARM существует с 08.2026 (`client.arm.deb64_*`) —
  раньше «клиент только x86» было правдой, теперь нет.
- **Отпечаток лицензии**: программная лицензия 1С привязана к CPU+RAM+диску+MAC
  контейнера (НЕ к логину аккаунта). На Apple Silicon x86-отпечаток виден
  только под Rosetta (CPU «VirtualApple Family 6 Model 142» — Docker Desktop
  патчит для них /proc/cpuinfo в amd64-контейнерах). Отсюда два рабочих
  варианта сервера: **нативный arm64 + fake-cpuinfo** (bind-mount поверх
  `/proc/cpuinfo` в privileged-контейнере, эталон `src/conf/cpuinfo-virtualapple`
  — РАБОЧЕЕ РЕШЕНИЕ, подтверждено живым сеансом) и аварийный запас —
  Rosetta-образ `src/Dockerfile.server.amd64` (тег `server1c:8.3.27.2325-amd64`,
  отпечаток совпадает «пиксель в пиксель»). Нативная arm64-сборка БЕЗ
  fake-cpuinfo ломает валидацию: «Ошибка привязки... После получения лицензии
  удалены CPU VirtualApple...» — сеансы падают «нет лицензии» на всех клиентах.
- **8.5 считает отпечаток иначе** (CPU-поля в лицензии пустые): x86-лицензия
  8.3 к нему не подходит; лицензия, полученная со стенда `lic1c85`, — без
  привязки к CPU и ожидаемо действительна и на 8.3.
- **`/var/1C/licenses` на маке — ОБЯЗАТЕЛЬНЫЙ каталог, создать руками один раз**.
  Маковский толстый клиент 1С — это linux-клиент по устройству данных
  (`~/.1cv8`, а не `~/Library`), и лицензию «для всех пользователей» он
  сохраняет в linux-овый системный путь `/var/1C/licenses`. На Linux его
  создаёт установщик deb-пакета; установщик `.app` для macOS его НЕ создаёт
  никогда. Без каталога: «Лицензия успешно получена» → файл молча не
  сохраняется → «Файл программной лицензии не найден». Диалог на маке выбора
  «для текущего/для всех» не предлагает. Лечение (разово после установки
  платформы или чистой macOS):
  ```bash
  sudo mkdir -p /var/1C/licenses && sudo chown -R $(id -un):staff /var/1C
  ```
  Клиентская лицензия после этого живёт в `/var/1C/licenses` (системная),
  conf остаётся пустым — это норма. Каталог не чистить; после переустановки
  macOS — пересоздать (автопродление `src/mac/1c-license-autorenew.sh` пишет
  в лог, если каталога нет).
- **Семейство «петель лицензий» клиента (мак)** — три разных корня, похожие
  симптомы «запрос лицензии по кругу»: (1) нет `nethasp.ini` → таймаут сбора
  информации о компьютере (см. ниже); (2) устаревшая копия epf-модуля →
  молчаливый отказ /Execute; (3) **две копии одного серийника в conf** —
  клиент при старте авто-продлевает лицензию и кладёт свежий файл рядом со
  старым → «используются две копии одного и того же файла программной
  лицензии» → круг. Лечение (3): в `~/.1cv8/1C/1cv8/conf/` должен
  быть ровно один `.lic` (продление само пересоздаёт файл).
- **epf-конвейер: пересборка только через build-epf.py** (двухдневный bisect):
  (1) v8unpack — ТОЛЬКО форк xDrivenDevelopment/v8unpack 3.0.1
  (e8tools 3.0.43 пакует нерабочие контейнеры — «непредвиденная ошибка» при
  /Execute); (2) байтовая длина модуля формы НЕ изменяема — любое её
  изменение = платформа молча не исполняет /Execute; build-epf.py ужимает
  комментарии и паддит до ровно исходных байт; (3) compile-ошибка модуля —
  такой же тихий скип; после правок Форма.bsl проверять прогоном с
  params=DUMP (маркер в license-result.txt). DUMP-режим встроен: печатает
  тип объекта параметров привязки (сам объект не итерируется, XMLСтрока не
  берёт; полный список параметров проще смотреть в диалоге ошибки привязки
  — трюк: положить чужой .lic в conf клиента).
- **`nethasp.ini` обязателен** (`NH_TCPIP = Disabled`) в conf клиентов и
  стенда лицензий: без него платформа сканирует сеть в поисках сетевых
  HASP при сборе отпечатка — «Сбор информации о компьютере выполняется
  длительное время», лицензия не получается, клиент циклично перезапрашивает
  (выглядит как загадочный «луп полученных лицензий»).
- **Семантика центра лицензирования** (проверено epf-раннером): пустые
  учётки → «Пинкод не входит в комплект» (центр ждёт пин купленной);
  креды при занятых слотах → «Превышено допустимое количество активных
  лицензий» (слоты считаются ВМЕСТЕ с заблокированными); продление —
  только в окне истечения (~последний день 7-дневного срока), раннер тот же
  `license-renew.sh`, учётные данные не нужны.
- **Healthcheck ≠ сеанс**: `rac cluster list` не трогает лицензии; после
  пересборки/миграции контейнеров healthcheck горит зелёным при мёртвой
  лицензии — проверять открытием ИБ вручную.
- **Стенду лицензий нужен СЕРВЕРНЫЙ deb** (в образе common+client+server):
  толстый клиент в `/F`-режиме поднимает серверный контекст из серверных
  библиотек; без них он сегфолтится при старте под Xvfb (выглядело как
  «клиенты падают из-за Docker», Docker был невиновен).
- **Клиентское подключение к кластеру 8.5 — открытый вопрос**: ragent:2540
  отвечает (в новом протоколе — `{#base64:...}` envelope), но 8.5-клиент
  отвергает: «не является адресом кластера» (по tcpdump: клиент кладёт
  трубку сразу после ответа ragent, до 2541 даже не доходит). 8.3-клиент к
  8.5-кластеру тем более не подключится (несовместимость веток).
- **pg82 (PostgreSQL 9.1.9-1.1C) под Rosetta — работает**: postmaster жив,
  форк-бэкенды живы (15/15 параллельных сессий), CREATE DATABASE в стиле 1С,
  md5-коннект снаружи — всё ок. ragent 8.2 убивала именно демонизация
  (fork+setsid), postgres в контейнере стартует foreground — этот паттерн
  эмуляция переваривает.
- **9.1 не знает многого из «позднего» — и делает это МОЛЧА**:
  `include_if_exists` в postgresql.conf → постмастер умирает с exit(1) без
  единого сообщения (перед смертью только WARNING «нераспознанный параметр»);
  у initdb нет `--auth-local/--auth-host` (только общий `--auth`); нет
  `pg_isready` (healthcheck — psql по сокету). Правильно: `include`,
  `--auth=md5` + sed local→trust в pg_hba.
- **deb'ы 9.1.9-1.1C требуют libssl0.9.8** (сборка под Ubuntu lucid) — база
  squeeze (glibc 2.11, ровесник), в wheezy libssl0.9.8 уже нет. А
  postgresql-common из тара (140~lucid) падает в postinst без lsb_release —
  лечится подсунутым /etc/lsb-release с идентификацией Ubuntu 10.04.
- **8.2 в контейнере — ragent мёртв, диагноз установлен**: ragent ВСЕГДА
  демонизируется (fork+setsid даже без `-daemon`); родитель честно выходит 0,
  а настоящий сервер — форкнутый ребёнок. Под Rosetta ребёнок умирает от
  порчи ABI (по strace: `read(fd=1, ~SIZE_MAX)`, мусорные номера сисколлов,
  указатели как размеры); под qemu-user 5.2 и 7.2 ребёнок тоже не выживает
  (ограничения эмуляции fork+threads). rmngr (не демонизируется) живёт везде.
  Проверены: wheezy/jessie/bullseye/bookworm, все флаги, seccomp, права,
  /var/log/1C, pidfile, qemu 1.1/5.2/7.2. Рабочий 8.2-агент — Windows VM;
  контейнер server1c82 оставлен с rmngr:1541→host:3541 как запасной полигон.

## Roadmap

- [x] ~~полная автоматика первичной активации~~ — epf-автомат (`first`-режим); ограничение только в слотах аккаунта, VNC-мастер остался ABS
- [x] ~~стенд лицензии без даунтайма~~ — отдельная сеть lic-net, нативный arm64
- [x] ~~сервер 8.5 отдельным контейнером~~ — `server1c85` (8.5.1.1522 arm64): та же схема слоёв, отдельная сеть, порты-сдвиг на хосте; MAC/лицензия общие с 8.3
- [x] ~~автопродление сервера и клиента~~ — epf-раннер по расписанию; клиент — скрытый ночной запуск (launchd, пн/чт 03:37)
- [x] ~~синхронизация списка баз~~ — единый `ibases.v8i` (см. «Общие файлы клиентов»)
- [x] ~~вариант «Parallels нет»~~ — винда опциональна, шаги просто пропускаются
- [ ] бэкапы PG: политика хранения (расписание уже есть)
- [ ] ansible-роль для развёртывания всего комплекта: сборка нужных версий по шаблону + генерация/патч compose при развёртывании на хосте (версии, тома, порты — параметры роли; ручное «добавь том в volumes» — не путь); мак: hosts/демон; удалённые хосты без pf-танцев
- [ ] второй мак как клиент через Tailscale: hosts `100.x.y.z server1c`, тонкий клиент с online.1c.ru; при желании `license-distribution=allow` на ИБ

## Лицензия проекта

MIT — см. [LICENSE](LICENSE). Дистрибутивы 1С и сборки PostgreSQL от 1С
не входят в репозиторий и скачиваются с releases.1c.ru по правилам 1С.

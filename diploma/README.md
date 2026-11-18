# SpMV на RISC-V RVV в gem5: префетчеры и латентности векторных операций


```
diploma/
  src/spmv_bench.c          бенчмарк: 4 ядра SpMV (+2 старых, по запросу)
  tools/gen_bench_header.py .mtx -> заголовок с CSR, SELL-C-σ и эталонным y
  tools/parse_stats.py      stats.txt + simout.txt -> CSV (строка = ядро)
  tools/plot_results.py     графики по CSV
  gem5/spmv_run.py          конфиг gem5 = binary_run.py + параметры
  scripts/build.sh          сборка бинарника под матрицу
  scripts/run_one.sh        один запуск gem5
  scripts/run_prefetchers.sh серия «префетчеры»
  scripts/run_latency.sh    серия «латентности RVV»
  scripts/dump_kernels.sh   машинный код ядер из бинарника
  scripts/find_objdump.sh   ищет objdump для RISC-V 
  scripts/parse_all.sh      пересобрать все CSV из папок запусков
  gem5_patches/             патч gem5 для префетчеров BOP и IMP (по желанию)
  docs/reference_check.md   что проверено при разработке набора
  results/                  CSV, графики, машинный код ядер;
```

Матрицы берутся из SuiteSparse Matrix Collection (https://sparse.tamu.edu),
файлы `.mtx` кладутся в `../matrices/`. В репозитории лежит только
`nasa2910.mtx`; остальные (например, `crystm03`) нужно скачать.

## Что поменялось по сравнению с main.cpp и почему

| Было (main.cpp, лето) | Стало | Зачем |
|---|---|---|
| `-O0` | `-O2 -fno-tree-vectorize` | при `-O0` около 84 млн операций из прошлого запуска — это сохранение векторных регистров на стек и обратная загрузка; латентности самих RVV-операций в таком коде почти не видны. `-fno-tree-vectorize` оставляет скалярное ядро скалярным, на интринсики флаг не влияет |
| 10 матриц в одном бинарнике, копирование в `std::vector`, SELL-C-σ строится в симуляторе | одна матрица на бинарник, данные `const` в `.rodata`, SELL-C-σ строится заранее на компьютере | прошлый запуск: 9,75 млрд инструкций за 4,5 суток (≈25 тыс. инструкций в секунду на модели O3) |
| время через `std::chrono` по одному прогону | маркеры `m5_dump_reset_stats` вокруг каждого ядра: отдельный блок статистики (такты, промахи, префетчер) на прогрев и на замер | точнее и даёт причины, а не только время |
| CSR RVV: `vslidedown`+`vfmv.f.s` на каждый элемент | CSR RVV с `vfredosum` на порцию (как в прошлом семестре) и CSR RVV с накоплением в регистре | старый вариант выполнял 2 операции класса SimdMisc (12 тактов, одно устройство) на каждый ненулевой элемент |
| SELL-C-σ: `vle32 y / vfadd / vse32` на каждом шаге j, отдельный проход перестановки | накопление в регистре (`vfmacc`), запись по перестановке одной `vsuxei32` (как Listing 1 у Gómez et al.) | меньше обращений к памяти; старый вариант давал неверный результат при VLEN < 256 (проверено в QEMU) |
| проверка `|ref-got| <= 1e-2*|ref|` | допуск по каждой строке `(nnz_i+4)·2⁻²³·Σ|a_ij·x_j|`, эталон посчитан в double | стандартная оценка ошибки округления суммы; прежний допуск был подобран вручную |

Старые ядра оставлены: `csr_rvv_slide` и `sellcs_rvv_mem` (запускаются, если
указать их в `--args`), чтобы при необходимости воспроизвести летние замеры.

Конфигурация процессора не менялась: `gem5/spmv_run.py` без параметров
строит ту же систему, что `gem5_board/binary_run.py`.

## Шаг 0. Окружение (каждый раз после открытия терминала WSL)

```bash
cd ~/projects/RVV-cross-ext
source compiler_vars.sh            # добавляет toolchain/bin в PATH
rvv-gcc --version | head -1        # должно быть 13.2.0
ls gem5/build/RISCV/gem5.opt       # gem5 уже собран
cd diploma
```

## Шаг 1. Сборка бинарников

```bash
scripts/build.sh nasa2910
```

Скрипт создаёт `gen/nasa2910.h`  и `build/spmv_nasa2910`.
Он также проверяет, что в скалярном ядре нет векторных инструкций.
Для других матриц из `../matrices/` укажите их имена через пробел.

## Шаг 2. Пробный запуск (обязательно перед сериями)

```bash
scripts/run_one.sh results/smoke/nasa2910/lab build/spmv_nasa2910
python3 tools/parse_stats.py results/smoke/nasa2910/lab
```

В `results/smoke/nasa2910/lab/simout.txt` должны быть 8 строк `VERIFY OK` и `@DONE`.
`wall.txt` показывает, сколько длился запуск. По этому числу можно оценить время серий.


## Шаг 3. Серия «префетчеры»

```bash
scripts/run_prefetchers.sh nasa2910          # префетчер в L1D, L2 без префетчера
scripts/run_prefetchers.sh nasa2910 l2       # префетчер в L2, L1D без префетчера
```

Конфигурации: `none` (без префетчеров), 7 префетчеров
`tagged, stride, ampm, dcpt, sms, spp, isb` и `lab` (лабораторная: SMS в L2,
L1D без префетчера). Каждый префетчер берётся с параметрами gem5 v24.1 по
умолчанию, SMS — с параметрами из `binary_run.py`. В серии `l2` запуск `sms`
совпадает с `lab` по конфигурации; это контрольная точка, такты должны совпасть.

| имя | префетчер gem5 | идея |
|---|---|---|
| tagged | TaggedPrefetcher | следующая строка (next-line), degree 2 |
| stride | StridePrefetcher | шаг по адресу инструкции (PC) |
| ampm | AMPMPrefetcher | карта обращений в зоне памяти |
| dcpt | DCPTPrefetcher | таблица разностей адресов по PC |
| sms | SmsPrefetcher | пространственные шаблоны по регионам 4 КиБ |
| spp | SignaturePathPrefetcher | сигнатуры последовательностей разностей |
| isb | IrregularStreamBufferPrefetcher | временная корреляция промахов |

Итог: `results/pf_l1d_nasa2910.csv` (и `pf_l2_...`), сводка печатается в консоль.

### Шаг 3а. Число MSHR в L1D и префетчеры

Кэш gem5 отправляет запрос префетчера, только когда у него нет ожидающих
обычных промахов и свободен регистр промаха (MSHR). Для этого должно быть
занято меньше `mshrs − 2` регистров (`BaseCache::getNextQueueEntry`,
`MSHRQueue::canPrefetch`). В L1D лаборатории 4 MSHR, то есть префетч уходит,
только пока занято меньше 2. В L2 их 40. Та же серия с 16 MSHR в L1D:

```bash
TAG=_mshr16 EXTRA="--l1d-mshrs 16" scripts/run_prefetchers.sh nasa2910
python3 tools/plot_results.py pf results/pf_l1d_mshr16_nasa2910.csv -o results/fig_pf_l1d_mshr16_nasa2910.png
```

`EXTRA` и `TAG` работают так же, как в серии латентностей: любые параметры
`spmv_run.py`, результаты в отдельной папке.

### Шаг 3в. Чувствительность к размещению данных в памяти

Одна и та же программа может работать по-разному в зависимости от того, по
каким адресам лежат массивы матрицы (наборы кэша, банки DRAM, области
префетчера SMS). Проверка: те же ядра с массивами, выровненными по 64 и по
4096 байт (`ALIGN`), остальное без изменений.

```bash
ALIGN=64   scripts/build.sh nasa2910      # -> build/spmv_nasa2910_a64
ALIGN=4096 scripts/build.sh nasa2910      # -> build/spmv_nasa2910_a4096
for v in nasa2910_a64 nasa2910_a4096; do
    PFS="none stride dcpt spp" scripts/run_prefetchers.sh $v
    PFS="none stride dcpt spp" scripts/run_prefetchers.sh $v l2
done
```

Без `ALIGN` бинарник получается побайтно тем же, что и раньше, поэтому уже
готовые результаты остаются в силе. Если какой-то вывод меняется от
выравнивания, в дипломе его нужно давать с разбросом, а не одним числом.

### Шаг 3б (по желанию). BOP и IMP: нужен патч gem5

В gem5 v24.1 (и в вашем форке) два префетчера не работают:

- **BOP** (Best-Offset). В `BOP::bestOffsetLearning` полный адрес сравнивается
  с тегами строк, поэтому обучение никогда не находит смещение, и префетчер не
  выдаёт ни одного запроса (`pfIssued = 0` во всех блоках). В ветке develop
  gem5 эта строка уже исправлена; патч делает то же самое.
- **IMP** (Indirect Memory Prefetcher, шаблон `x[col_idx[k]]`). Падает с
  `panic: PrefetchInfo::get called with a request with no data`: при
  попадании в кэш данные загрузки до префетчера не доходят. Патч передаёт их.
  Даже с патчем IMP видит индексы только из скалярных загрузок до 8 байт, и
  в реализации gem5 он выбирает элемент для текущего индекса, а не для
  будущего (`indirect_memory.cc`, цикл после `prefetchThreshold`). Поэтому
  эффект от него стоит ждать только у скалярного CSR.

Патч меняет 2 файла. На всех остальных конфигурациях (в том числе `lab`)
пропатченный gem5 даёт побайтно тот же `stats.txt`, что и исходный: проверено.

```bash
cd ~/projects/RVV-cross-ext/gem5
git apply --check ../diploma/gem5_patches/prefetch_bop_imp.patch && \
git apply ../diploma/gem5_patches/prefetch_bop_imp.patch
scons build/RISCV/gem5.opt -j2      # той же командой, что собирали раньше
cd ../diploma
PFS="bop imp" scripts/run_prefetchers.sh nasa2910
PFS="bop"     scripts/run_prefetchers.sh nasa2910 l2
```

## Шаг 4. Серия «латентности RVV»

```bash
scripts/run_latency.sh nasa2910
```

Для каждой группы задаются латентности 1, 2, 4, 8, 16, 32, 64, 128 тактов.
Остальные параметры при этом — как в лабораторной конфигурации:

| группа | классы gem5 | инструкции в ядрах | в конфиге лаборатории |
|---|---|---|---|
| `gather` | SimdIndexedLoad | `vluxei32` | 7 |
| `vload` | SimdUnitStrideLoad | `vle32` | 5 |
| `vec_fp` | SimdFloatMult, SimdFloatMultAcc, SimdFloatAdd | `vfmul`, `vfmacc`, `vfadd` | 6, 6, 5 |
| `vec_red` | SimdFloatReduceAdd | `vfredosum`, `vfredusum` | 7 |
| `vec_misc` | SimdMisc | `vfmv.f.s`, `vfmv.v.f`, `vslidedown` | 12 |
| `vec_all` | все Simd* | все векторные | — |

Классы определены по `src/arch/riscv/isa/decoder.isa` вашего gem5.
В O3 латентность класса задерживает начало выполнения инструкции, в том
числе загрузки. Поэтому для `gather` и `vload` это добавка к времени доступа
в кэш. `vluxei32` gem5 разбивает на микрооперации по одной на элемент, и
латентность действует на каждую. Такты скалярного ядра от этой серии зависеть
не должны: это встроенная проверка

Свои значения можно задать так: `LAT_GROUPS="gather vec_fp" VALUES="1 4 16 64" scripts/run_latency.sh nasa2910`.

Та же серия при другом процессоре

```bash
TAG=_l2_2MB EXTRA="--l2-size 2MB" scripts/run_latency.sh nasa2910
python3 tools/plot_results.py lat results/lat_l2_2MB_nasa2910.csv -o results/fig_lat_l2_2MB_nasa2910.png
```

**Известная ошибка gem5: `--lat gather=1`.** При латентности `SimdIndexedLoad`
= 1 такт часть ядер в нескольких строках выдаёт NaN (на nasa2910 и crystm03,
у разных компиляторов это разные ядра). При латентностях 2–128, при
`--lat vec_all=1` и в QEMU тот же бинарник считает верно.

Причина найдена по трассировке gem5 (`--debug-flags=ExecAll,O3PipeView`).
gem5 разбивает `vluxei32` на микрооперации (`isa/templates/vector_mem.isa`,
`VlIndexConstructor`):

1. `vcpyvs` копирует вектор индексов во внутренний регистр (SimdMisc);
2. `vpinvd` заполняет регистр-приёмник единицами (политика `ta`) и
   «закрепляет» его физический регистр (pinned writes) (SimdMisc);
3. 8 микроопераций загрузки, по одной на элемент: каждая пишет свой
   элемент прямо в этот закреплённый физический регистр.

Микрооперации загрузки зависят только от `vcpyvs` (индексы), но не от
`vpinvd`: регистр-приёмник не объявлен у них источником. Порядок «сначала
`vpinvd`, потом элементы» ничем не обеспечен. В конфигурации лаборатории
у SimdMisc 12 тактов, у SimdIndexedLoad 7, и загрузки всегда заканчиваются
позже `vpinvd`. При SimdIndexedLoad = 1 первая загрузка иногда заканчивается
раньше. Тогда `vpinvd` выполняется после неё и затирает загруженный элемент
единицами, а 0xFFFFFFFF как float — это NaN. В трассе nasa2910 (`csr_rvv_red`,
строка 197): у элемента 0 данные уже записаны, когда в остальных элементах ещё
нет единиц от `vpinvd`; у элемента 1 в позиции 0 уже стоит 0xFFFFFFFF. При
`vec_all=1` у `vpinvd` тоже 1 такт, и гонки нет.

В текущей ветке develop gem5 разбиение `vluxei32` устроено так же:
у микроопераций элементов регистр-приёмник по-прежнему не объявлен
источником. Исправлена ли гонка как-то иначе, не проверялось.

Почему остальным точкам можно доверять: ядра используют политику `ta`,
поэтому потерянный элемент всегда превращается в NaN, а NaN проверка
результата ловит всегда. Такие запуски помечаются `[VERIFY FAIL]`, в CSV у них
`verified=False`, и `plot_results.py` их на графики не выводит.

## Шаг 5. Графики

```bash
sudo apt install python3-matplotlib    # один раз (в Ubuntu 24.04 pip без venv не ставит)
python3 tools/plot_results.py pf  results/pf_l1d_nasa2910.csv -o results/fig_pf_l1d_nasa2910.png
python3 tools/plot_results.py pf  results/pf_l2_nasa2910.csv  -o results/fig_pf_l2_nasa2910.png
python3 tools/plot_results.py lat results/lat_nasa2910.csv    -o results/fig_lat_nasa2910.png
```

На графике префетчеров два ряда: сверху такты на итерацию (какое ядро быстрее
при данном префетчере), снизу ускорение каждого ядра относительно `none`.

Скрипт `lat` печатает для каждого ядра максимальную латентность группы,
при которой векторное ядро ещё быстрее скалярного.

## Как пользоваться конфигом напрямую

```bash
../gem5/build/RISCV/gem5.opt -re -d results/my_run gem5/spmv_run.py \
    --bin build/spmv_nasa2910 --l1d-pf stride --l2-pf none \
    --lat gather=16 --l2-size 1MB --args "csr_scalar sellcs_rvv"
```

`--lat` принимает и группу, и имя класса (`--lat SimdIndexedLoad=16`).
Параметры кэшей: `--l1d-size --l1d-assoc --l1d-mshrs --l2-size --l2-assoc --l2-lat`.

## Что получается в результатах

`results/<серия>/<матрица>/<конфигурация>/`: `stats.txt`, `simout.txt`
(вывод программы), `config.ini`, `cmdline.txt`, `wall.txt`.
В CSV для каждого ядра: такты на итерацию, время, GFLOP/s, ускорение
относительно скалярного CSR того же запуска, IPC, промахи L1D/L2, байты из
DRAM, у префетчеров — выдано / полезных / неиспользованных / опоздавших,
точность и покрытие.

## Если что-то пошло не так

- `[FAIL] ... rc=...` — смотрите `simerr.txt` в папке запуска.
- `VERIFY FAIL` — ядро посчитало неверно; пришлите `simout.txt`.
- Серию можно прервать (Ctrl+C) и запустить снова: готовые запуски пропускаются.
- Не запускайте больше 2 gem5 одновременно: в WSL 2 ядра и 5,8 ГБ памяти
  (`JOBS=1 scripts/...` — по одному).
- `fatal: Could not mmap 8589934592 bytes` — gem5 резервирует 8 ГиБ под
  память модели (реально используется гораздо меньше). Летом у вас это
  работало; если ошибка появится, выполните `sudo sysctl vm.overcommit_memory=1`
  (действует до перезапуска WSL).

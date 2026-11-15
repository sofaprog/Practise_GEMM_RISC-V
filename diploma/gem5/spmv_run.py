# Конфигурация gem5 SE для экспериментов SpMV.
#
# Это gem5_board/binary_run.py лаборатории + параметры командной строки.
# БЕЗ параметров даёт ту же систему, что binary_run.py:
#   O3 1.6 ГГц, L1I/L1D 32 КиБ 4-way (2+2+2 такта, 4 MSHR), L2 512 КиБ 2-way
#   (40+40+40 тактов, 40 MSHR, префетчер SMS), DDR4-2400, VLEN=256,
#   те же функциональные устройства и латентности.
#
# Примеры:
#   gem5.opt -re -d out/x spmv_run.py --bin build/spmv_nasa2910
#   ... --l1d-pf stride --l2-pf none          # префетчер Stride в L1D, без SMS в L2
#   ... --lat gather=16 --lat vec_fp=12       # латентности векторных операций
#   ... --lat SimdIndexedLoad=16              # то же по имени класса gem5
#   ... --args "csr_scalar sellcs_rvv"        # какие ядра запускать
import argparse
import shlex

import m5
from m5.objects import *
from m5.objects.Prefetcher import *
from m5.params import NULL

p = argparse.ArgumentParser()
p.add_argument("--bin", required=True, help="бинарник RISC-V")
p.add_argument("--args", default="", help="аргументы программы (строкой)")
p.add_argument("--vlen", type=int, default=256)
p.add_argument("--crosslat", type=int, default=6,
               help="латентность vfcross (в SpMV не используется)")
PF_NAMES = ["none", "tagged", "stride", "ampm", "bop", "dcpt", "sms",
            "imp", "spp", "isb"]
p.add_argument("--l1d-pf", default="none", choices=PF_NAMES,
               help="префетчер L1D (по умолчанию нет, как в binary_run.py)")
p.add_argument("--l2-pf", default="sms", choices=PF_NAMES,
               help="префетчер L2 (по умолчанию SMS, как в binary_run.py)")
p.add_argument("--lat", action="append", default=[], metavar="ИМЯ=ТАКТЫ",
               help="латентность класса операций или группы; можно повторять")
# Параметры кэшей (по умолчанию -- как в binary_run.py)
p.add_argument("--l1d-size", default="32kB")
p.add_argument("--l1d-assoc", type=int, default=4)
p.add_argument("--l1d-mshrs", type=int, default=4)
p.add_argument("--l2-size", default="512kB")
p.add_argument("--l2-assoc", type=int, default=2)
p.add_argument("--l2-lat", type=int, default=40,
               help="tag = data = response латентность L2, тактов")
args = p.parse_args()

# ---------------------------------------------------------------- префетчеры
class SmsPrefetcherMy(SmsPrefetcher):  # ровно как в binary_run.py
    ft_size = Param.Unsigned(32, "Size of Filter and Active generation table")
    pht_size = Param.Unsigned(16384, "Size of pattern history table")
    region_size = Param.Unsigned(4096, "Spatial region size")
    queue_squash = True
    queue_filter = True
    cache_snoop = True
    prefetch_on_access = True
    on_inst = True


def make_prefetcher(name, level):
    """Каждый префетчер берётся с параметрами gem5 v24.1 по умолчанию
    (SMS -- с параметрами лаборатории)."""
    if name == "none":
        return NULL
    if name == "tagged":
        return TaggedPrefetcher()          # next-N-line, degree=2
    if name == "stride":
        return StridePrefetcher()          # по PC, degree=4
    if name == "ampm":
        return AMPMPrefetcher()            # Access Map Pattern Matching
    if name == "bop":
        # Best-Offset. В gem5 v24.1 ошибка в BOP::bestOffsetLearning: префетчер
        # ни разу не выдаёт запрос (pfIssued = 0). Нужен патч
        # gem5_patches/prefetch_bop_imp.patch (исправление как в gem5 develop).
        return BOPPrefetcher()
    if name == "dcpt":
        return DCPTPrefetcher()            # Delta-Correlating Prediction Tables
    if name == "sms":
        return SmsPrefetcherMy()           # Spatial Memory Streaming
    if name == "spp":
        return SignaturePathPrefetcher()
    if name == "isb":
        return IrregularStreamBufferPrefetcher()
    if name == "imp":
        # Indirect Memory Prefetcher (шаблон A[B[i]]). Читает значения индексов
        # из данных скалярных загрузок <= 8 байт при попадании в кэш, поэтому
        # имеет смысл только в L1D и должен видеть все попадания. В
        # Base::observeAccess при prefetch_on_pf_hit=True попадания в
        # непредвыбранные блоки отбрасываются, поэтому он выключен.
        # Без патча gem5_patches/prefetch_bop_imp.patch gem5 v24.1 падает
        # с panic "PrefetchInfo::get called with a request with no data".
        if level != "l1d":
            m5.fatal("imp работает только в L1D")
        return IndirectMemoryPrefetcher(prefetch_on_access=True,
                                        prefetch_on_pf_hit=False)
    m5.fatal(f"неизвестный префетчер {name}")


# ---------------------------------------------------------------- кэши
class L1Cache(Cache):
    assoc = 4
    tag_latency = 2
    data_latency = 2
    response_latency = 2
    mshrs = 4
    tgts_per_mshr = 20


class L2Cache(Cache):
    size = "512kB"
    assoc = 2
    tag_latency = 40
    data_latency = 40
    response_latency = 40
    mshrs = 40
    tgts_per_mshr = 12


system = System()
system.clk_domain = SrcClockDomain()
system.clk_domain.clock = "1.6GHz"
system.clk_domain.voltage_domain = VoltageDomain()
system.mem_mode = "timing"
system.mem_ranges = [AddrRange("8192MB")]

system.cpu = RiscvO3CPU()
system.cpu.icache = L1Cache(size="32kB")
system.cpu.dcache = L1Cache(size=args.l1d_size, assoc=args.l1d_assoc,
                            mshrs=args.l1d_mshrs)
system.cpu.dcache.prefetcher = make_prefetcher(args.l1d_pf, "l1d")
system.cpu.icache.cpu_side = system.cpu.icache_port
system.cpu.dcache.cpu_side = system.cpu.dcache_port

system.l2bus = L2XBar()
system.cpu.icache.mem_side = system.l2bus.cpu_side_ports
system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports

system.l2cache = L2Cache(size=args.l2_size, assoc=args.l2_assoc,
                         tag_latency=args.l2_lat, data_latency=args.l2_lat,
                         response_latency=args.l2_lat)
system.l2cache.prefetcher = make_prefetcher(args.l2_pf, "l2")
system.l2cache.cpu_side = system.l2bus.mem_side_ports

system.membus = SystemXBar()
system.l2cache.mem_side = system.membus.cpu_side_ports
system.cpu.createInterruptController()

system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR4_2400_8x8()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports

system.cpu.isa = RiscvISA(vlen=args.vlen)
system.workload = SEWorkload.init_compatible(args.bin)
process = Process()
process.cmd = [args.bin] + shlex.split(args.args)
system.cpu.workload = process
system.multi_thread = True
system.cpu.createThreads()

system.cpu.fetchWidth = 6
system.cpu.decodeWidth = 2
system.cpu.issueWidth = 4
system.cpu.renameWidth = 4
system.cpu.commitWidth = 6
system.cpu.commitToRenameDelay = 1
system.cpu.numIQEntries = 24
system.cpu.wbWidth = 8
system.cpu.dispatchWidth = 8

# ------------------------------------------------- функциональные устройства
# Латентности (тактов) -- как в binary_run.py. Ключ = класс операций gem5.
LAT = {
    # скалярные
    "IntAlu": 1, "IntMult": 3, "IntDiv": 20,
    "FloatAdd": 4, "FloatCmp": 4, "FloatCvt": 4, "FloatMisc": 4,
    "FloatMult": 4, "FloatMultAcc": 5, "FloatDiv": 28, "FloatSqrt": 21,
    "MemWrite": 3, "MemRead": 1, "FloatMemWrite": 3, "FloatMemRead": 1,
    # векторные (RVV)
    "SimdConfig": 3, "SimdAlu": 1, "SimdAdd": 1, "SimdCvt": 3,
    "SimdReduceAlu": 5, "SimdReduceCmp": 5, "SimdReduceAdd": 5, "SimdShift": 3,
    "SimdMult": 4, "SimdMultAcc": 4, "SimdDiv": 21,
    "SimdExt": 4, "SimdCmp": 4, "SimdMisc": 12,
    "SimdFloatAlu": 5, "SimdFloatAdd": 5, "SimdFloatCmp": 5, "SimdFloatExt": 5,
    "SimdFloatMisc": 5, "SimdFloatCvt": 6, "SimdFloatReduceAdd": 7,
    "SimdFloatReduceCmp": 7,
    "SimdFloatMult": 6, "SimdFloatMultAcc": 6, "SimdFloatMatMultAcc": 1,
    "VectorFloatVecMathArith": args.crosslat,
    "SimdFloatDiv": 28, "SimdFloatSqrt": 21,
    "SimdWholeRegisterLoad": 4, "SimdUnitStrideLoad": 5, "SimdStridedLoad": 7,
    "SimdIndexedLoad": 7, "SimdUnitStrideMaskLoad": 5,
    "SimdUnitStrideSegmentedLoad": 7, "SimdUnitStrideFaultOnlyFirstLoad": 10,
    "SimdWholeRegisterStore": 3, "SimdUnitStrideStore": 5, "SimdStridedStore": 7,
    "SimdIndexedStore": 7, "SimdUnitStrideMaskStore": 5,
    "SimdUnitStrideSegmentedStore": 7,
}
# Группы для перебора латентностей. В скобках -- инструкции ядер SpMV
# (проверено по src/arch/riscv/isa/decoder.isa).
GROUPS = {
    "gather":  ["SimdIndexedLoad"],                       # vluxei32
    "vload":   ["SimdUnitStrideLoad"],                    # vle32
    "vstore":  ["SimdUnitStrideStore", "SimdIndexedStore"],  # vse32, vsuxei32
    "vec_fp":  ["SimdFloatMult", "SimdFloatMultAcc", "SimdFloatAdd"],  # vfmul, vfmacc, vfadd
    "vec_red": ["SimdFloatReduceAdd"],                    # vfredosum, vfredusum
    "vec_misc": ["SimdMisc"],                             # vfmv.f.s, vmv.v.i, vslidedown
    "vec_int": ["SimdShift", "SimdConfig"],               # vsll, vsetvli
}
GROUPS["vec_mem"] = GROUPS["gather"] + GROUPS["vload"] + GROUPS["vstore"]
GROUPS["vec_all"] = [k for k in LAT if k.startswith("Simd")]

for item in args.lat:
    name, val = item.split("=")
    targets = GROUPS.get(name, [name])
    for t in targets:
        if t not in LAT:
            m5.fatal(f"--lat: неизвестный класс или группа {name}")
        LAT[t] = int(val)

HAS_CROSS = "VectorFloatVecMathArith" in OpClass.vals  # есть только в форке


def ops(names, pipelined=True):
    return [OpDesc(opClass=n, opLat=LAT[n], pipelined=pipelined)
            for n in names if n in OpClass.vals]


def fu(names, count, pipelined=True):
    return FUDesc(opList=ops(names, pipelined), count=count)


system.cpu.fuPool = FUPool(FUList=[
    # скалярные
    fu(["IntAlu"], 2),
    fu(["IntMult"], 2),
    fu(["IntDiv"], 1, pipelined=False),
    fu(["FloatAdd", "FloatCmp", "FloatCvt", "FloatMisc"], 2),
    fu(["FloatMult", "FloatMultAcc"], 2),
    fu(["FloatDiv"], 1, pipelined=False),
    fu(["FloatSqrt"], 1, pipelined=False),
    fu(["MemWrite", "MemRead", "FloatMemWrite", "FloatMemRead"], 2),
    # RVV
    fu(["SimdConfig", "SimdAlu", "SimdAdd", "SimdCvt", "SimdReduceAlu",
        "SimdReduceCmp", "SimdReduceAdd", "SimdShift"], 2),
    fu(["SimdMult", "SimdMultAcc"], 2),
    fu(["SimdDiv"], 1, pipelined=False),
    fu(["SimdExt", "SimdCmp", "SimdMisc"], 1),
    fu(["SimdFloatAlu", "SimdFloatAdd", "SimdFloatCmp", "SimdFloatExt",
        "SimdFloatMisc", "SimdFloatCvt", "SimdFloatReduceAdd",
        "SimdFloatReduceCmp"], 2),
    FUDesc(count=2, opList=ops(["SimdFloatMult", "SimdFloatMultAcc"])
           + [OpDesc(opClass="SimdFloatMatMultAcc")]
           + ops(["VectorFloatVecMathArith"])),
    fu(["SimdFloatDiv"], 1, pipelined=False),
    fu(["SimdFloatSqrt"], 1, pipelined=False),
    fu(["SimdWholeRegisterLoad", "SimdUnitStrideLoad", "SimdStridedLoad",
        "SimdIndexedLoad", "SimdUnitStrideMaskLoad",
        "SimdUnitStrideSegmentedLoad", "SimdUnitStrideFaultOnlyFirstLoad",
        "SimdWholeRegisterStore", "SimdUnitStrideStore", "SimdStridedStore",
        "SimdIndexedStore", "SimdUnitStrideMaskStore",
        "SimdUnitStrideSegmentedStore"], 2),
])

changed = {k: v for k, v in LAT.items() if k.startswith("Simd")}
print(f"@GEM5CFG l1d_pf={args.l1d_pf} l2_pf={args.l2_pf} vlen={args.vlen} "
      f"l1d={args.l1d_size}/{args.l1d_assoc}w/{args.l1d_mshrs}mshr "
      f"l2={args.l2_size}/{args.l2_assoc}w/{args.l2_lat}cyc "
      f"lat_overrides={';'.join(args.lat) or 'none'}")

root = Root(full_system=False, system=system)
m5.instantiate()
print("Beginning simulation!")
exit_event = m5.simulate()
print(f"Exiting @ tick {m5.curTick()} because {exit_event.getCause()}")

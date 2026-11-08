# Kintex-7 部分重配置（PR）实战：SPI Flash → PRC → ICAP

基于 Xilinx UG947 / UG909 部分重配置流程，在 **AX7325 开发板（Kintex-7 XC7K325T-2FFG900）** 上实现
**不依赖 JTAG、上电后由 Fabric 自主从 SPI Flash 读取 partial bitstream 并经 PRC + ICAP 完成动态重配置**。
按键 `key1` 在两个 Reconfigurable Module（`shift_right` / `shift_left`）之间切换，LED 走灯方向随之改变。

本项目完整记录了从"JTAG 能加载、PRC 路径挂死"到硬件验证通过的调试过程，并把所有踩过的坑固化为
设计约束与脚本，可直接复现。

---

## 1. 平台与工具

| 项 | 值 |
|---|---|
| 开发板 | AX7325（Alinx / 黑金风格），Kintex-7 `xc7k325tffg900-2` |
| 配置 Flash | Micron `MT25QL128`（= N25Q128，128 Mbit，SPI x4） |
| Vivado | 2019.2（非工程 Tcl 流程） |
| 重配置控制器 | Xilinx PRC IP v1.3（1 个 Virtual Socket `vs_shift`，2 个 RM） |
| 系统时钟 | 100 MHz |

## 2. 架构

```
            SPI Flash (MT25QL128)
              │  CCLK(经 STARTUPE2.USRCCLKO) / MOSI / MISO / CE
              ▼
        spi_flash_reader.v          ← 自定义 AXI4 只读 slave，bit-bang SPI
              │  m_axi_mem (AXI4 read)
              ▼
           PRC (prc v1.3)           ← 管理 VS / RM 生命周期、CP FIFO
              │  ICAP 写引擎
              ▼
           ICAPE2                 ← 把 partial bitstream 写入配置帧
              │
              ▼
        RM (shift_left / shift_right)  ← LED 走灯方向改变
```

- `spi_flash_reader.v` 把 Flash 中的 partial `.bin` 以 AXI4 burst 读出的方式喂给 PRC。
  CCLK 通过 `STARTUPE2` 的 `USRCCLKO` 输出到 Flash 引脚，数据脚为普通 IO。
- PRC 的 `m_axi_mem` 接 reader；PRC 内部对每个字节做 bit-reverse（rev8）后送 ICAP。
- 两个 RM 的 partial bitstream 与 static 一起烧进 Flash 的固定偏移（见 §4）。

## 3. 目录结构

```
.
├── design.tcl                     # 顶层非工程构建流程（synth/impl/write_bitstream）
├── create_prom_file_myb.tcl       # 生成 partial .bin + 整片 pr_prom.mcs
├── write_static_bitstream.tcl     # 从 route DCP 重生成 static full bit + ltx
├── gen_debug_probes.tcl           # 重生成 ILA probes (.ltx)
├── Sources/
│   ├── hdl/
│   │   ├── top/                   # top.v / spi_flash_reader.v / clocks / debouncer ...
│   │   ├── shift_left/  shift_right/   # 两个 RM
│   │   └── count_up/    count_down/    # 备用 RM（教程遗留）
│   ├── xdc/                       # top_myb.xdc（pblock / 引脚 / 时钟）+ budget xdc
│   ├── scripts/                   # gen_ip / pr_info / update_prc / axi_lite_procs / regen_ila
│   └── ip/                        # 仅保留 canonical IP 的 .xci（见 .gitignore）
├── Tcl_HD/                        # UG947 hierarchical-design 流程库
├── sim/                           # spi_flash_reader  testbench + SPI Flash 行为模型
└── ilaset/                        # 硬件调试 Tcl / 解析脚本（ILA 抓取、PRC 寄存器、flash verify）
```

canonical IP（`design.tcl` 实际引用）：`prc_1`、`jtag_to_axi`、`ila_vs_shift`、
`ila_axi_mem`、`ila_axi_reg`、`ila_icap`。仓库只保留它们的 `.xci`，生成产物不入库。

## 4. Flash 布局与 PRC 表

| 内容 | Flash 偏移 | 大小 |
|---|---|---|
| static full (`Config_shift_right_full.bit`) | `0x000000` | — |
| `rm_shift_left` partial | `0xAEA000` | 215280 B |
| `rm_shift_right` partial | `0xB60000` | 215280 B |
| `greybox` partial | `0xBD6000` | 215280 B |

地址/尺寸定义在 `Sources/scripts/pr_info_myb.tcl`，由 `update_prc_myb.tcl`（write_bitstream 的
pre-hook）写入 PRC 的 bitstream 表。**改 partial 尺寸时必须同步更新 pr_info。**

## 5. 构建与烧写

```tcl
# 1) 完整构建（synth + impl + write_bitstream，含 PRC 表 pre-hook）
vivado -mode batch -source design.tcl

# 2) 生成 partial .bin 与整片 MCS
vivado -mode batch -source create_prom_file_myb.tcl

# 3) 如需单独重生成 static / probes
vivado -mode batch -source write_static_bitstream.tcl
vivado -mode batch -source gen_debug_probes.tcl
```

烧写（Hardware Manager GUI）：
1. 给 `xc7k325t` **Add Configuration Memory Device** → 选 `mt25ql128-spi-x1_x2_x4` → 指定 `Bitstreams/pr_prom.mcs`。
2. 勾 **Erase + Program + Verify** → OK。
3. **彻底断电重启**（重要，见 §6.4）。

验证：
- 上电后 LED 右走（4-3-2-1）。
- `key2` 复位 → 确认右走 → 按一次 `key1` → LED 变左走（1-2-3-4）且稳定。
- 再按 `key1` 回右走，可反复切换。

## 6. 关键设计要点与踩坑记录（本项目核心价值）

### 6.1 字节序：reader 必须"原样"交付文件字
PRC 会对每个字节做 rev8（byte lane 不变）把 AXI 字变成 ICAP 需要的 SelectMAP 位交换格式。
因此 reader 的 `rdata` 必须等于 Flash 文件字本身（`{B3,B2,B1,B0}`，B0 为先读字节）。
**任何在 reader 里额外做的 bit-reverse 都会抵消 PRC 的交换**，使 ICAP 看到未交换的 sync
`0xAA995566`（而非 `0x5599AA66`），永远不同步、静默丢弃整条流。

### 6.2 SCLK 分频：STARTUPE2 往返延迟
CCLK 经 `STARTUPE2.USRCCLKO` 出、MISO 经普通 IO 回，往返延迟大且不可控。50 MHz SCLK 采样裕量
不足，在 ~3.9 Mbit 流上产生 sporadic 位错误（ICAP CRC 拒绝）。现 `SCLK_DIV=4` → **12.5 MHz**，
上升沿后 ~40 ns 采样 MISO，覆盖往返延迟；加载时间 ~310 ms（按键触发可接受）。

### 6.3 根因：partial 中的 `IPROG` 与 `RESET_AFTER_RECONFIG`
**症状**：JTAG 加载同一 partial 正常，但 PRC/SPI/ICAP 路径在固定点（bin word 66897）读死，
Flash MISO 冻结、只有断电能恢复。
**根因**：`RESET_AFTER_RECONFIG 1` 使 `write_bitstream -cell` 在 partial 中插入 `CMD=IPROG`
（warm boot）。ICAP 在 user mode 执行 IPROG 后配置逻辑接管 CCLK/SPI 引脚去重读 boot 镜像，
与 Fabric 的 `spi_flash_reader` 抢引脚 → Flash 访问死锁 → 尾部 DESYNC 丢失 → 挂死。
JTAG 加载时配置逻辑受 JTAG 控制、IPROG 被屏蔽，故能"复活"。
**修复**：`Sources/xdc/top_myb.xdc` 设 `RESET_AFTER_RECONFIG 0`，重生成 partial（无 IPROG）+
同步 pr_info 尺寸 + 重生成 static/MCS。硬件验证双向切换稳定。

### 6.4 JTAG / 间接烧写后必须断电
JTAG 间接编程会把 SPI Flash 留在 x4 / 连续读模式；不断电时 Fabric reader 读回全 `FFFFFFFF`，
看起来像"数据路径死了"。**任何 SPI/Flash 测量前，若刚做过 JTAG program 或 cfgmem 烧写，先彻底断电重启。**

### 6.5 其它已修复问题
- AXI `arready` 时序 bug（reader FSM）。
- 悬空的 `vs_shift_rm_shutdown_ack`。
- ICAP 时钟不分频，与参考设计一致。
- `hw_triggers` 改脉冲输出，消除上电自触发死循环。
- PRC `DEVICE_ID` 配置修正。

## 7. 调试工具（`ilaset/`、`sim/`）

- `sim/tb_spi_flash_reader.v` + `sim/spi_flash_model.v`：reader 全 burst 行为仿真。
- `ilaset/verify_flash.tcl`：JTAG 只读校验整片 Flash（`program_hw_cfgmem` + `VERIFY=1`）。
- `ilaset/jtag_load_partial.tcl`：JTAG 直接加载 partial，判别 static/RM 是否完好。
- `ilaset/dump_prc_regs.tcl` / `read_status.tcl` / `poll_status.tcl`：JTAG 读 PRC 寄存器。
- `ilaset/cmp_iprog.py`：检测 partial bitstream 是否含 `IPROG` / `DESYNC`。
- `ilaset/rebuild_partials_reset0.tcl` / `rebuild_static_mcs_reset0.tcl`：§6.3 修复的重建脚本。
- ILA  cores：`ila_axi_mem`(AXI/SPI)、`ila_icap`(ICAP 写侧)、`ila_vs_shift`(PRC/VS)、`ila_axi_reg`(寄存器总线)。

ILA 触发注意：GUI 值框对总线探针要写**满 hex 位宽**（如 `00AEAXXX`），短值会静默约束错误的位；
每次触发前 `key2` 复位以对齐 `reconfig_toggle` 奇偶（奇数次 key1 → `rm_shift_left` @ `0xAEA000`）。

## 8. 验证结果

- SPI Flash JTAG Verify 通过（数据完好）。
- reader 仿真全 472 burst 行为正确。
- 硬件：上电右走 → key1 左走稳定 → key1 回右走，反复切换正常（PRC/SPI/ICAP 全链路）。

## 9. 参考

- Xilinx UG947 — Vivado Partial Reconfiguration Tutorial
- Xilinx UG909 — Partial Reconfiguration User Guide
- Xilinx UG470 — 7 Series FPGAs Configuration User Guide
- Xilinx PG926 — Partial Reconfiguration Controller IP

## 10. 说明

- 构建产物（`Implement/`、`Synth/`、`Bitstreams/` 等）不入库，按 §5 脚本复现；
  如需预烧镜像，请从 Release 获取或本地生成。
- 旧版（`RESET_AFTER_RECONFIG=1`）产物备份于本地 `Bitstreams/backup_reset1/`（不入库）。
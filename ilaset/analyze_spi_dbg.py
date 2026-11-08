import csv, io, collections

SRC = "ilaset/iladata0.csv"
OUT = "ilaset/spi_dbg_analysis.txt"

with io.open(SRC, "r", encoding="latin-1", newline="") as f:
    rows = list(csv.reader(f))

hdr = rows[0]
radix = rows[1]
data = rows[2:]

idx = {name: i for i, name in enumerate(hdr)}

def col(name):
    for k in idx:
        if k.startswith(name):
            return idx[k]
    raise KeyError(name)

C_TRIG   = col("TRIGGER")
C_ARADDR = col("m_axi_mem_araddr")
C_ARLEN  = col("m_axi_mem_arlen")
C_ARVAL  = col("m_axi_mem_arvalid_v")
C_ARRDY  = col("m_axi_mem_arready_v")
C_RDATA  = col("m_axi_mem_rdata")
C_RLAST  = col("m_axi_mem_rlast_v")
C_RVAL   = col("m_axi_mem_rvalid_v")
C_RRDY   = col("m_axi_mem_rready_v")
C_STATE  = col("spi_dbg_state")
C_SEQ    = col("spi_dbg_seq")
C_CE     = col("flash_ce_b_OBUF")
C_CCLK   = col("usrcclko")

NAMES = {0:"IDLE",1:"CMD_SETUP",2:"CMD",3:"ADDR_SETUP",4:"ADDR",
         5:"DATA_SETUP",6:"DATA",7:"DONE"}

out = []
def w(s):
    out.append(s)

w("file=%s  data rows=%d" % (SRC, len(data)))
w("radix row: %s" % (radix,))
w("")

# ---- trigger position
trig_rows = [i for i, r in enumerate(data) if r[C_TRIG] not in ("", "0")]
w("TRIGGER marked at data rows: %s" % (trig_rows[:10],))
w("")

# ---- state run-length encoding
w("==== spi_dbg_state timeline (run lengths in clk_100 samples) ====")
runs = []
cur = data[0][C_STATE]
start = 0
for i in range(1, len(data)):
    s = data[i][C_STATE]
    if s != cur:
        runs.append((start, i - start, cur))
        cur, start = s, i
runs.append((start, len(data) - start, cur))

w("total runs = %d" % len(runs))
for (st, ln, sv) in runs[:60]:
    try:
        nm = NAMES[int(sv, 16)]
    except Exception:
        nm = "?"
    w("  row %6d  len %6d  state %s (%s)" % (st, ln, sv, nm))
if len(runs) > 60:
    w("  ... (%d more runs)" % (len(runs) - 60))
w("")

# ---- per-state totals
tot = collections.Counter()
for (st, ln, sv) in runs:
    tot[sv] += ln
w("==== total samples per state ====")
for sv in sorted(tot):
    try:
        nm = NAMES[int(sv, 16)]
    except Exception:
        nm = "?"
    w("  state %s (%-10s) = %8d samples = %9.2f us" % (sv, nm, tot[sv], tot[sv] / 100.0))
w("")

# ---- seq behaviour inside CMD and ADDR
w("==== spi_dbg_seq inside the first CMD and ADDR runs ====")
for (st, ln, sv) in runs[:40]:
    if sv in ("2", "4"):
        seqs = [data[j][C_SEQ] for j in range(st, min(st + ln, len(data)))]
        cclk = [data[j][C_CCLK] for j in range(st, min(st + ln, len(data)))]
        rises = sum(1 for j in range(1, len(cclk)) if cclk[j-1] == "0" and cclk[j] == "1")
        w("  state %s run at row %d len %d: seq distinct=%s  cclk rising edges=%d"
          % (sv, st, ln, sorted(set(seqs), key=lambda x: int(x, 16)), rises))
        w("     seq first 40: %s" % (" ".join(seqs[:40]),))
w("")

# ---- AR handshake
w("==== AXI AR handshakes (arvalid & arready) ====")
ars = []
for i, r in enumerate(data):
    if r[C_ARVAL] == "1" and r[C_ARRDY] == "1":
        ars.append((i, r[C_ARADDR], r[C_ARLEN]))
w("count = %d" % len(ars))
for a in ars[:20]:
    w("  row %6d  araddr=%s  arlen=%s" % a)
w("")

# ---- R beats: rdata at each rvalid rising edge
w("==== rdata at each rvalid RISING edge ====")
beats = []
prev = "0"
for i, r in enumerate(data):
    v = r[C_RVAL]
    if v == "1" and prev != "1":
        beats.append((i, r[C_RDATA], r[C_STATE], r[C_RLAST]))
    prev = v
w("beat count = %d" % len(beats))
for n, (i, rd, stv, rl) in enumerate(beats[:40]):
    w("  beat %3d  row %6d  rdata=%s  state=%s  rlast=%s" % (n, i, rd, stv, rl))
if len(beats) > 40:
    w("  ... last 5 beats:")
    for n, (i, rd, stv, rl) in enumerate(beats[-5:]):
        w("  beat %3d  row %6d  rdata=%s  state=%s  rlast=%s" % (len(beats)-5+n, i, rd, stv, rl))
uniq = collections.Counter(b[1] for b in beats)
w("distinct rdata over ALL beats: %d" % len(uniq))
for v, c in uniq.most_common(12):
    w("   %s x%d" % (v, c))
w("")

# ---- CE and CCLK
w("==== flash_ce_b_OBUF transitions ====")
ce_runs = []
cur = data[0][C_CE]; start = 0
for i in range(1, len(data)):
    if data[i][C_CE] != cur:
        ce_runs.append((start, i - start, cur)); cur, start = data[i][C_CE], i
ce_runs.append((start, len(data) - start, cur))
w("ce runs = %d" % len(ce_runs))
for (st, ln, v) in ce_runs[:20]:
    w("  row %6d len %6d ce=%s" % (st, ln, v))
tot_cclk = sum(1 for i in range(1, len(data))
               if data[i-1][C_CCLK] == "0" and data[i][C_CCLK] == "1")
w("usrcclko rising edges over whole window = %d" % tot_cclk)
w("rready high samples = %d / %d" % (sum(1 for r in data if r[C_RRDY] == "1"), len(data)))
w("")

# ---- MOSI / MISO bit-level decode (present only in builds with probe18/probe19)
def optcol(name):
    for k in idx:
        if k.startswith(name):
            return idx[k]
    return None

C_MOSI = optcol("flash_d0")
C_MISO = optcol("flash_d1")

w("==== SPI bit-level decode (MOSI = flash_d0, MISO = flash_d1) ====")
if C_MOSI is None or C_MISO is None:
    w("columns not present in this capture "
      "(need the 20-probe ila_axi_mem build); header=%s" % (hdr,))
else:
    w("column names: MOSI=%s  MISO=%s" % (hdr[C_MOSI], hdr[C_MISO]))

    def bits_at_rising_edges(col_i):
        acc, bits, edges = 0, [], 0
        for i in range(1, len(data)):
            if data[i-1][C_CCLK] == "0" and data[i][C_CCLK] == "1":
                edges += 1
                acc = ((acc << 1) | (1 if data[i][col_i] == "1" else 0)) & 0xFF
                if edges % 8 == 0:
                    bits.append(acc)
                    acc = 0
        return bits, edges

    mosi_bytes, e1 = bits_at_rising_edges(C_MOSI)
    miso_bytes, e2 = bits_at_rising_edges(C_MISO)
    w("cclk rising edges sampled: mosi=%d miso=%d -> %d whole bytes"
      % (e1, e2, len(mosi_bytes)))

    def show(label, bs):
        w("  %s first 24 bytes: %s" % (label, " ".join("%02X" % b for b in bs[:24])))
        w("  %s distinct bytes : %s" % (label, sorted(set("%02X" % b for b in bs))))
    show("MOSI", mosi_bytes)
    show("MISO", miso_bytes)

    w("")
    w("  expected MOSI byte 0 = 03 (READ), bytes 1-3 = burst_addr[23:0]")
    w("  MISO all FF while CE low => the flash is not driving D01_DIN")
    w("  MISO toggling but rdata all FF => sampling/assembly problem in the reader")

    # per-state MISO activity: does MISO ever differ from 1 inside ST_DATA?
    data_rows = [i for i in range(len(data)) if data[i][C_STATE] == "6"]
    if data_rows:
        lo = sum(1 for i in data_rows if data[i][C_MISO] != "1")
        w("")
        w("  ST_DATA samples = %d, of which MISO==0 : %d" % (len(data_rows), lo))
    mosi_lo = sum(1 for i in range(len(data)) if data[i][C_MOSI] == "0")
    w("  MOSI low samples over whole window = %d / %d" % (mosi_lo, len(data)))

with io.open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print("wrote", OUT)

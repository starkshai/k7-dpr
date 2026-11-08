import sys, csv, io, zipfile, os, collections

# Parse the ZIP that write_hw_ila_data produces (Vivado writes a ZIP even when the
# target filename ends in .csv). Reads waveform.csv from inside it.
#
#   python ilaset/parse_ila_zip.py [path-to-zip]
# default: ilaset/ila_icap_capture.zip

SRC = sys.argv[1] if len(sys.argv) > 1 else "ilaset/ila_icap_capture.zip"
OUT = os.path.splitext(SRC)[0] + "_analysis.txt"

if not os.path.exists(SRC):
    print("no such file:", SRC)
    sys.exit(1)

with zipfile.ZipFile(SRC) as z:
    names = z.namelist()
    print("zip members:", names)
    csv_name = None
    for n in names:
        if n.lower().endswith("waveform.csv") or n.lower().endswith(".csv"):
            csv_name = n
            break
    if csv_name is None:
        print("no CSV inside the zip")
        sys.exit(1)
    with z.open(csv_name) as f:
        rows = list(csv.reader(io.TextIOWrapper(f, encoding="latin-1", newline="")))

hdr, radix, data = rows[0], rows[1], rows[2:]
out = []
w = out.append
w("source=%s  member=%s  data rows=%d" % (SRC, csv_name, len(data)))
w("header: %s" % (hdr,))
w("radix : %s" % (radix,))
w("")

def col(sub):
    for i, h in enumerate(hdr):
        if sub in h:
            return i
    return None

C_CSIB   = col("icap_csib")
C_DATA   = col("icap_i")
C_STATUS = col("icap_status")
C_RDWRB  = col("icap_rdwrb")
C_TRIG   = col("TRIGGER")

if C_DATA is None:
    w("icap_i column not found -- this capture is not from the ICAP ILA")
    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("wrote", OUT)
    sys.exit(1)

trig = [i for i, r in enumerate(data) if C_TRIG is not None and r[C_TRIG] not in ("", "0")]
w("TRIGGER rows: %s" % (trig[:10],))
w("")

# ---- ICAP writes = csib low. Record icap_i at each csib FALLING edge.
writes = []
if C_CSIB is not None:
    prev = "1"
    for i, r in enumerate(data):
        c = r[C_CSIB]
        if c == "0" and prev != "0":
            writes.append((i, r[C_DATA], r[C_STATUS] if C_STATUS is not None else "?"))
        prev = c
    w("==== ICAP writes (icap_i at each csib FALLING edge) ====")
    w("write count in window = %d" % len(writes))
    for n, (i, d, s) in enumerate(writes[:80]):
        mark = ""
        if n == 12:
            mark = "   <== expect 5599AA66 (sync)"
        elif n == 13:
            mark = "   <== expect 04000000 (NOP)"
        elif n == 19:
            mark = "   <== expect C0A608C9 (IDCODE)"
        elif n == 8:
            mark = "   <== expect 000000DD"
        elif n == 9:
            mark = "   <== expect 88440022"
        w("  write %3d  row %6d  icap_i=%-10s icap_status=%s%s" % (n, i, d, s, mark))
    if len(writes) > 80:
        w("  ... (%d more)" % (len(writes) - 80))
else:
    w("icap_csib_v column not found; dumping icap_i at every sample change instead")
    last = None
    n = 0
    for i, r in enumerate(data):
        if r[C_DATA] != last:
            if n < 80:
                w("  row %6d  icap_i=%-10s status=%s" %
                  (i, r[C_DATA], r[C_STATUS] if C_STATUS is not None else "?"))
            n += 1
            last = r[C_DATA]
    w("  distinct icap_i values = %d" % n)
w("")

# ---- icap_status trace
if C_STATUS is not None:
    w("==== icap_status run-length trace ====")
    runs = []
    cur = data[0][C_STATUS]; start = 0
    for i in range(1, len(data)):
        if data[i][C_STATUS] != cur:
            runs.append((start, i - start, cur)); cur, start = data[i][C_STATUS], i
    runs.append((start, len(data) - start, cur))
    w("runs = %d" % len(runs))
    for (st, ln, v) in runs[:60]:
        note = ""
        try:
            b = int(v, 16)
            note = "  CFGERR_B=%d DALIGN=%d RIP=%d IN_ABORT_B=%d" % (
                (b >> 3) & 1, (b >> 2) & 1, (b >> 1) & 1, b & 1)
        except Exception:
            pass
        w("  row %6d len %6d status=%s%s" % (st, ln, v, note))
    w("")
    w("  reference: 9 = no error, NOT synced (also the never-written idle value)")
    w("               D = DALIGN set, no error  -> SYNCED, this is the success signature")
    w("               5 = DALIGN set + CFGERR   -> synced then errored mid-stream")
    w("               1 = CFGERR, not synced")

with io.open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print("wrote", OUT)

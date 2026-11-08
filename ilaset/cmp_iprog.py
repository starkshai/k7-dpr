import struct, sys, os
def words_bit(p):
    d = open(p, 'rb').read()
    i = d.find(bytes.fromhex('AA995566'))
    if i < 0:
        return []
    d = d[i:]
    n = len(d) // 4
    return list(struct.unpack('>%dI' % n, d[:n*4]))
for p in sys.argv[1:]:
    if not os.path.exists(p):
        print(p, 'MISSING'); continue
    w = words_bit(p)
    iprog = [i for i in range(len(w)-1) if w[i] == 0x30008001 and w[i+1] == 0x0000000B]
    desync = [i for i in range(len(w)-1) if w[i] == 0x30008001 and w[i+1] == 0x0000000A]
    print('%-40s words=%7d IPROG@%s DESYNC@%s' % (os.path.basename(p), len(w), iprog, desync))
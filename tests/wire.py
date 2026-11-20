#!/usr/bin/env python3
# tests/wire.py :: reads the live wire format (app/lib/wire.lua; docs/APP.md "Live client")
# byte for byte, for tests/run.sh's t_live helpers.
#   wire.py ops BODY                print "op args length" per frame
#   wire.py payload BODY OP [ARG]   write the first such frame's payload to stdout (raw)
#   wire.py merge BODY HAVEFILE     merge the hashes frame into HAVEFILE ("name=hash ...";
#                                   "name=-" drops a region), as the client does
import sys


def frames(path):
    data = open(path, "rb").read()
    if not data.startswith(b"DK1\n"):
        sys.exit("wire.py: no DK1 header")
    pos, out = 4, []
    while pos < len(data):
        nl = data.index(b"\n", pos)
        words = data[pos:nl].decode().split(" ")
        n = int(words[-1])
        payload = data[nl + 1:nl + 1 + n]
        if len(payload) != n or data[nl + 1 + n:nl + 2 + n] != b"\n":
            sys.exit("wire.py: short frame")
        out.append((words[0], words[1:-1], payload))
        pos = nl + 2 + n
    return out


def main():
    cmd, body = sys.argv[1], sys.argv[2]
    fs = frames(body)
    if cmd == "ops":
        for op, args, payload in fs:
            print(" ".join([op] + args + [str(len(payload))]))
    elif cmd == "payload":
        want = sys.argv[3:]
        for op, args, payload in fs:
            if [op] + args[:len(want) - 1] == want:
                sys.stdout.buffer.write(payload)
                return
        sys.exit("wire.py: no frame " + " ".join(want))
    elif cmd == "merge":
        have = {}
        try:
            for w in open(sys.argv[3]).read().split():
                k, _, v = w.partition("=")
                have[k] = v
        except FileNotFoundError:
            pass
        for op, args, payload in fs:
            if op == "hashes":
                for w in payload.decode().split():
                    k, _, v = w.partition("=")
                    if v == "-":
                        have.pop(k, None)
                    else:
                        have[k] = v
        open(sys.argv[3], "w").write(" ".join(k + "=" + v for k, v in have.items()))


if __name__ == "__main__":
    main()

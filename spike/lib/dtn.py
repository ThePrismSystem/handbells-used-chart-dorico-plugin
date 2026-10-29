"""Decode a Dorico .dtn (score.dtn or scorelibrary.dtn from inside a .dorico zip) into a tree.

  python spike/lib/dtn.py FILE.dorico OUT.txt   writes score.dtn as indented text, one node per line

Layout (Dorico 6.2.30, all little-endian; varints are LEB128):
  u32 4, u32 1, u32 nameCount, then nameCount NUL-terminated element names
  u32 valueCount, then valueCount NUL-terminated values (value 0 is "")
  u32 nodeCount, then nodeCount records; a node's id is its record's index, and node 0 is the root:
    tag byte, name varint, value varint, and when tag & 2, a child count varint and that many child ids
  The tag's high nibble differed between two saves of the same project (0x2_ and 0x1_) and changes nothing found
  so far; tag & 1 marks an array element.
"""
import struct
import sys
import zipfile


def varint(data, p):
    out, shift = 0, 0
    while True:
        b = data[p]
        p += 1
        out |= (b & 0x7F) << shift
        if not b & 0x80:
            return out, p
        shift += 7


def cstrings(data, p, n):
    out = []
    for _ in range(n):
        end = data.index(b"\0", p)
        out.append(data[p:end].decode("utf-8", "replace"))
        p = end + 1
    return out, p


def decode(data):
    """{names, values, nodes: [(tag, name index, value index, [child ids])]}; raises if the records don't end the file."""
    nnames = struct.unpack_from("<I", data, 8)[0]
    names, p = cstrings(data, 12, nnames)
    nvalues = struct.unpack_from("<I", data, p)[0]
    values, p = cstrings(data, p + 4, nvalues)
    nnodes = struct.unpack_from("<I", data, p)[0]
    p += 4
    nodes = []
    for _ in range(nnodes):
        tag = data[p]
        name, p = varint(data, p + 1)
        value, p = varint(data, p)
        kids = []
        if tag & 2:
            count, p = varint(data, p)
            for _ in range(count):
                k, p = varint(data, p)
                kids.append(k)
        nodes.append((tag, name, value, kids))
    if p != len(data):
        raise ValueError(f"records end at {p} of {len(data)} bytes")
    return {"names": names, "values": values, "nodes": nodes}


def read(project):
    return decode(zipfile.ZipFile(project).read("score.dtn"))


def child(tree, node, name):
    names, nodes = tree["names"], tree["nodes"]
    for k in nodes[node][3]:
        if names[nodes[k][1]] == name:
            return k
    return None


def dump(tree, out, node=0, depth=0):
    tag, name, value, kids = tree["nodes"][node]
    v = tree["values"][value]
    out.write("  " * depth + tree["names"][name] + ("*" if tag & 1 else "") + (f" = {v!r}" if v or not kids else "")
              + f"  #{node}\n")
    for k in kids:
        dump(tree, out, k, depth + 1)


if __name__ == "__main__":
    sys.setrecursionlimit(100000)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        dump(read(sys.argv[1]), f)

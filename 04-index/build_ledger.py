#!/usr/bin/env python3
"""Build the MatrixGold reconstruction ledger from SymbolScan JSONL output."""
import csv
import json
import os
import sqlite3
import sys
import time

LAB = r"D:\REA-LAB"
RAW = os.path.join(LAB, "04-index", "raw")
DB = os.path.join(LAB, "04-index", "symbols.sqlite")
DECOMP = os.path.join(LAB, "03-decompiled", "raw")

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=OFF;
CREATE TABLE IF NOT EXISTS assemblies (
  id INTEGER PRIMARY KEY,
  file TEXT UNIQUE, assembly TEXT, version TEXT, managed INTEGER,
  module TEXT, mvid TEXT, runtime TEXT, resources INTEGER,
  n_types INTEGER, n_methods INTEGER, n_strings INTEGER, n_calls INTEGER,
  decompiled_cs INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS types (
  id INTEGER PRIMARY KEY, asm_id INTEGER, full_name TEXT, namespace TEXT, name TEXT,
  is_obf INTEGER, is_public INTEGER, is_interface INTEGER, is_enum INTEGER,
  is_value_type INTEGER, is_abstract INTEGER, is_sealed INTEGER, base TEXT,
  attrs TEXT
);
CREATE TABLE IF NOT EXISTS methods (
  id INTEGER PRIMARY KEY, type_id INTEGER, name TEXT, token INTEGER, is_obf INTEGER,
  is_public INTEGER, is_static INTEGER, is_virtual INTEGER, is_abstract INTEGER,
  rva INTEGER, il_size INTEGER, signature TEXT, attrs TEXT, il_error TEXT,
  status TEXT DEFAULT 'indexed'
);
CREATE TABLE IF NOT EXISTS properties (id INTEGER PRIMARY KEY, type_id INTEGER, name TEXT, type TEXT, is_obf INTEGER);
CREATE TABLE IF NOT EXISTS fields (id INTEGER PRIMARY KEY, type_id INTEGER, name TEXT, type TEXT, is_static INTEGER, is_public INTEGER, is_obf INTEGER);
CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, type_id INTEGER, name TEXT, type TEXT);
CREATE TABLE IF NOT EXISTS strings (id INTEGER PRIMARY KEY, method_id INTEGER, value TEXT);
CREATE TABLE IF NOT EXISTS calls (id INTEGER PRIMARY KEY, method_id INTEGER, callee TEXT, declaring_type TEXT, token INTEGER, op TEXT);
CREATE TABLE IF NOT EXISTS names (token INTEGER PRIMARY KEY, scope TEXT, inferred_name TEXT, confidence TEXT, rationale TEXT, evidence TEXT);
CREATE VIRTUAL TABLE IF NOT EXISTS string_search USING fts5(value, method_id UNINDEXED);
CREATE INDEX IF NOT EXISTS idx_types_full ON types(full_name);
CREATE INDEX IF NOT EXISTS idx_types_asm ON types(asm_id);
CREATE INDEX IF NOT EXISTS idx_methods_type ON methods(type_id);
CREATE INDEX IF NOT EXISTS idx_methods_name ON methods(name);
CREATE INDEX IF NOT EXISTS idx_methods_status ON methods(status);
CREATE INDEX IF NOT EXISTS idx_strings_method ON strings(method_id);
CREATE INDEX IF NOT EXISTS idx_calls_method ON calls(method_id);
CREATE INDEX IF NOT EXISTS idx_calls_callee ON calls(callee);
"""


def decompiled_counts():
    counts = {}
    if not os.path.isdir(DECOMP):
        return counts
    for name in os.listdir(DECOMP):
        d = os.path.join(DECOMP, name)
        if not os.path.isdir(d):
            continue
        n = 0
        for _, _, files in os.walk(d):
            n += sum(1 for f in files if f.endswith(".cs"))
        counts[name] = n
    return counts


def main():
    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    con.executescript(SCHEMA)
    cur = con.cursor()
    dcounts = decompiled_counts()

    t0 = time.time()
    n_asm = n_type = n_method = n_string = n_call = 0
    files = sorted(f for f in os.listdir(RAW) if f.endswith(".jsonl"))

    for fi, fname in enumerate(files, 1):
        path = os.path.join(RAW, fname)
        header = None
        type_objs = []
        try:
            with open(path, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    obj = json.loads(line)
                    if obj.get("kind") == "assembly":
                        header = obj
                    elif obj.get("kind") == "type":
                        type_objs.append(obj)
        except Exception as exc:
            print(f"[warn] {fname}: {exc}", file=sys.stderr)
            continue

        if header is None:
            continue

        asm_name = header.get("assembly", "")
        cur.execute(
            "INSERT OR IGNORE INTO assemblies(file,assembly,version,managed,module,mvid,runtime,resources,n_types,n_methods,n_strings,n_calls,decompiled_cs) VALUES (?,?,?,?,?,?,?,?,0,0,0,0,?)",
            (
                header.get("file"), asm_name, header.get("version", ""), 1,
                header.get("module", ""), header.get("mvid", ""), header.get("runtime", ""),
                len(header.get("resources", [])), dcounts.get(asm_name, 0),
            ),
        )
        asm_id = cur.execute("SELECT id FROM assemblies WHERE file=?", (header.get("file"),)).fetchone()[0]
        n_asm += 1

        prop_rows, field_rows, event_rows = [], [], []
        method_meta = []  # (method_row, strings, calls)
        type_ids = []

        for obj in type_objs:
            cur.execute(
                "INSERT INTO types(asm_id,full_name,namespace,name,is_obf,is_public,is_interface,is_enum,is_value_type,is_abstract,is_sealed,base,attrs) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    asm_id, obj.get("full_name", ""), obj.get("namespace", ""), obj.get("name", ""),
                    1 if obj.get("is_obf") else 0, 1 if obj.get("is_public") else 0,
                    1 if obj.get("is_interface") else 0, 1 if obj.get("is_enum") else 0,
                    1 if obj.get("is_value_type") else 0, 1 if obj.get("is_abstract") else 0,
                    1 if obj.get("is_sealed") else 0, obj.get("base", ""),
                    json.dumps(obj.get("attributes", [])),
                ),
            )
            type_id = cur.lastrowid
            type_ids.append(type_id)
            n_type += 1
            for p in obj.get("properties", []):
                prop_rows.append((type_id, p.get("name", ""), p.get("type", ""), 1 if p.get("is_obf") else 0))
            for f in obj.get("fields", []):
                field_rows.append((type_id, f.get("name", ""), f.get("type", ""), 1 if f.get("is_static") else 0, 1 if f.get("is_public") else 0, 1 if f.get("is_obf") else 0))
            for e in obj.get("events", []):
                event_rows.append((type_id, e.get("name", ""), e.get("type", "")))
            for m in obj.get("methods", []):
                method_meta.append((
                    (
                        type_id, m.get("name", ""), m.get("token", 0), 1 if m.get("is_obf") else 0,
                        1 if m.get("is_public") else 0, 1 if m.get("is_static") else 0,
                        1 if m.get("is_virtual") else 0, 1 if m.get("is_abstract") else 0,
                        m.get("rva", 0), m.get("il_size", 0), m.get("signature", ""),
                        json.dumps(m.get("attributes", [])), m.get("il_error", ""),
                    ),
                    m.get("strings", []),
                    m.get("calls", []),
                ))

        if prop_rows:
            cur.executemany("INSERT INTO properties(type_id,name,type,is_obf) VALUES (?,?,?,?)", prop_rows)
        if field_rows:
            cur.executemany("INSERT INTO fields(type_id,name,type,is_static,is_public,is_obf) VALUES (?,?,?,?,?,?)", field_rows)
        if event_rows:
            cur.executemany("INSERT INTO events(type_id,name,type) VALUES (?,?,?)", event_rows)

        method_ids = []
        for mr, _, _ in method_meta:
            cur.execute(
                "INSERT INTO methods(type_id,name,token,is_obf,is_public,is_static,is_virtual,is_abstract,rva,il_size,signature,attrs,il_error) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                mr,
            )
            method_ids.append(cur.lastrowid)
            n_method += 1

        srows, crows = [], []
        for mid, (_, strs, cls) in zip(method_ids, method_meta):
            for s in strs:
                srows.append((mid, s))
                n_string += 1
            for c in cls:
                crows.append((mid, c.get("callee", ""), c.get("declaring_type", ""), c.get("token", 0), c.get("op", "")))
                n_call += 1
        if srows:
            cur.executemany("INSERT INTO strings(method_id,value) VALUES (?,?)", srows)
        if crows:
            cur.executemany("INSERT INTO calls(method_id,callee,declaring_type,token,op) VALUES (?,?,?,?,?)", crows)

        cur.execute(
            "UPDATE assemblies SET n_types=?, n_methods=?, n_strings=?, n_calls=? WHERE id=?",
            (len(type_ids), len(method_ids), len(srows), len(crows), asm_id),
        )
        con.commit()
        print(f"[{fi}/{len(files)}] {asm_name}: types={len(type_ids)} methods={len(method_ids)} strings={len(srows)} calls={len(crows)} ({time.time()-t0:.0f}s)")

    print("Building string search index...")
    cur.execute("INSERT INTO string_search(value, method_id) SELECT value, method_id FROM strings")
    con.commit()

    cov_path = os.path.join(LAB, "04-index", "coverage.csv")
    with open(cov_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["assembly", "file", "types", "methods", "obf_types", "obf_methods", "strings", "calls", "decompiled_cs", "il_errors"])
        for row in cur.execute(
            """SELECT a.assembly, a.file, a.n_types, a.n_methods,
                      (SELECT COUNT(*) FROM types t WHERE t.asm_id=a.id AND t.is_obf=1),
                      (SELECT COUNT(*) FROM methods m JOIN types t ON m.type_id=t.id WHERE t.asm_id=a.id AND m.is_obf=1),
                      a.n_strings, a.n_calls, a.decompiled_cs,
                      (SELECT COUNT(*) FROM methods m JOIN types t ON m.type_id=t.id WHERE t.asm_id=a.id AND m.il_error<>'')
               FROM assemblies a ORDER BY a.n_methods DESC"""
        ):
            w.writerow(row)

    print(f"assemblies={n_asm:,} types={n_type:,} methods={n_method:,} strings={n_string:,} calls={n_call:,}")
    print(f"db={DB} ({os.path.getsize(DB)/1024/1024:.1f} MB)")
    con.close()


if __name__ == "__main__":
    main()

import json
import sqlite3
import xml.etree.ElementTree as ET

DB = r"D:\REA-LAB\04-index\symbols.sqlite"
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row


def rows(sql, args=()):
    return [dict(r) for r in con.execute(sql, args).fetchall()]


print("=== TOP RHINO CALLS ===")
for r in rows("""SELECT callee, COUNT(*) n FROM calls WHERE declaring_type LIKE 'Rhino.%'
                 GROUP BY callee ORDER BY n DESC LIMIT 50"""):
    print(f"{r['n']:>5}  {r['callee'][:150]}")

print("\n=== SAVE / LOAD / EXPORT / IMPORT METHODS ===")
for r in rows("""SELECT a.assembly, t.full_name, m.name, m.signature
                 FROM methods m JOIN types t ON m.type_id=t.id JOIN assemblies a ON t.asm_id=a.id
                 WHERE (m.name LIKE '%Save%' OR m.name LIKE '%Load%' OR m.name LIKE '%Export%'
                        OR m.name LIKE '%Import%' OR m.name LIKE '%Serialize%')
                   AND a.assembly IN ('MatrixGold','CS','CSBlocks','MatrixGoldPlugin','SharedTypes','Common')
                 ORDER BY a.assembly, t.full_name LIMIT 70"""):
    print(f"{r['assembly']:<16} {r['full_name'][:70]:<70} {r['signature'][:80]}")

print("\n=== CSHEADBUILDER V2 METHODS ===")
for r in rows("""SELECT t.full_name, m.name, m.signature FROM methods m
                 JOIN types t ON m.type_id=t.id
                 WHERE t.full_name LIKE 'CSBlocks.Settings.Heads.CSHeadBuilderV2%'
                 ORDER BY t.full_name, m.name LIMIT 60"""):
    print(f"{r['full_name'][:80]:<80} {r['signature'][:100]}")

print("\n=== CSBLOCK / HALO / BEZEL TYPES ===")
for r in rows("""SELECT t.full_name, COUNT(m.id) n FROM types t LEFT JOIN methods m ON m.type_id=t.id
                 WHERE t.full_name LIKE 'CSBlocks.Core.CSBlock%'
                    OR t.full_name LIKE 'CSBlocks.GemClusters.CSHaloBuilder%'
                    OR t.full_name LIKE 'CSBlocks.Settings.Bezels%'
                    OR t.full_name LIKE 'CSBlocks.Patterns%'
                 GROUP BY t.id ORDER BY n DESC LIMIT 30"""):
    print(f"{r['n']:>4}  {r['full_name']}")

print("\n=== UNITS / TOLERANCE / AUTOSAVE STRINGS ===")
for r in rows("""SELECT value, COUNT(*) n FROM strings
                 WHERE value LIKE '%autosave%' OR value LIKE '%tolerance%'
                    OR value LIKE '%millimeter%' OR value LIKE '%AbsoluteTolerance%'
                    OR value LIKE '%AngleTolerance%' OR value LIKE '%unit%'
                 GROUP BY value ORDER BY n DESC LIMIT 50"""):
    print(f"{r['n']:>4}  {r['value'][:140]}")

print("\n=== STULLER / GRAPHQL / WCF TYPES ===")
for r in rows("""SELECT a.assembly, t.full_name FROM types t JOIN assemblies a ON t.asm_id=a.id
                 WHERE t.full_name LIKE 'Stuller%' OR t.full_name LIKE '%GraphQL%'
                    OR t.full_name LIKE '%ServiceReference%' OR t.full_name LIKE '%IJARS%'
                 ORDER BY a.assembly LIMIT 60"""):
    print(f"{r['assembly']:<20} {r['full_name']}")

print("\n=== MAINWINDOW XAML TOP TREE ===")
X = "{http://schemas.microsoft.com/winfx/2006/xaml}"
tree = ET.parse(r"D:\REA-LAB\03-decompiled\xaml\MatrixGold\mainwindow.xaml")
root = tree.getroot()


def short(tag):
    return tag.split("}")[-1]


def walk(el, depth=0, maxdepth=3):
    if depth > maxdepth:
        return
    name = el.attrib.get(f"{X}Name", "")
    cls = el.attrib.get(f"{X}Class", "")
    extra = f" x:Name={name}" if name else ""
    if cls:
        extra += f" x:Class={cls}"
    print("  " * depth + short(el.tag) + extra)
    for child in list(el)[:12]:
        walk(child, depth + 1, maxdepth)


walk(root)

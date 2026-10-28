import sqlite3, os, sys, collections, re

DB = r"D:\REA-LAB\04-index\symbols.sqlite"
OUT = r"D:\REA-LAB\04-index\facts"
os.makedirs(OUT, exist_ok=True)
c = sqlite3.connect(DB)
c.row_factory = sqlite3.Row

def is_obf(s):
    return bool(re.search(r"[\u0001-\u001f]|^[A-Za-z]{0,2}$", s or "")) and not re.match(r"^[A-Za-z_][\w`<>,\[\]\. ]{2,}$", s or "")

SYS = {1: 'shell', 2: 'document', 3: 'ui', 4: 'geometry', 5: 'parametric',
       6: 'gems', 7: 'ringsizing', 8: 'content'}

def rows_for(sid):
    if sid == 1:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('MatrixGold','MatrixGoldPlugin','MatrixGoldSkin','GemvisionWebhook','Stuller.Mvvm')
                 and (t.namespace is null or t.namespace not like 'MatrixGold.Views%'
                      and t.namespace not like 'MatrixGold.ViewModels%'
                      and t.namespace not like 'MatrixGold.Converters%'
                      and t.namespace not like 'MatrixGold.Models%')"""
    elif sid == 2:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('CS','CSDatas','CSBlockUtil','CSBlockDataUtils','CSCompatibility','CSLegacyObjects','CSCustomObjects')
                 and coalesce(t.namespace,'') not like 'CSBlocks%'"""
    elif sid == 3:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly='MatrixGold' and (t.namespace like 'MatrixGold.Views%' or t.namespace like 'MatrixGold.ViewModels%'
                     or t.namespace like 'MatrixGold.Converters%' or t.namespace like 'MatrixGold.Models%'
                     or t.namespace like 'MatrixGold.Helpers%')"""
    elif sid == 4:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('GemvisionGeometry','GemvisionCommon')
                  or (a.assembly='CSBlocks' and (t.namespace like 'CSBlocks.Transforms%' or t.namespace like 'CSBlocks.Curves%'
                      or t.namespace like 'CSBlocks.Maths%' or t.namespace like 'CSBlocks.Core%'))"""
    elif sid == 5:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('CSBlocks','CSBlockUtil','CSBlockDataUtils')
                 and coalesce(t.namespace,'') not like 'CSBlocks.Transforms%'
                 and coalesce(t.namespace,'') not like 'CSBlocks.Curves%'
                 and coalesce(t.namespace,'') not like 'CSBlocks.Maths%'
                 and coalesce(t.namespace,'') not like 'CSBlocks.Core%'"""
    elif sid == 6:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('CSGemInstance','CSMaterials','Common.Materials')
                  or (a.assembly='CSBlocks' and t.namespace like 'CSBlocks.Gems%')"""
    elif sid == 7:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly='CSRingSizes'"""
    else:
        q = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id
               where a.assembly in ('GVBuilders','Localization','LocalizationCore','MatrixCommon','SharedTypes','Common','Common.UI')"""
    return c.execute(q).fetchall()

def stats(tids):
    if not tids: return (0, 0)
    ph = ",".join("?" * len(tids))
    n = c.execute("select count(*) from methods where type_id in (%s)" % ph, tids).fetchone()[0]
    return (len(tids), n)

for sid, key in SYS.items():
    types = rows_for(sid)
    tids = [t["id"] for t in types]
    if not tids:
        continue
    nt, nm = stats(tids)
    lines = []
    lines.append("SUBSYSTEM: %s\nTYPES: %d  METHODS: %d\n" % (key, nt, nm))

    # per-type method counts
    ph = ",".join("?" * len(tids))
    tc = dict(c.execute("select type_id, count(*) from methods where type_id in (%s) group by type_id order by 2 desc" % ph, tids).fetchall())
    lines.append("== TOP TYPES BY METHOD COUNT ==")
    for t in types:
        lines.append("%5d  %-58s  %-22s %s" % (tc.get(t["id"], 0), (t["full_name"] or "")[:58], t["asm"], t["base"] or ""))

    # readable method names grouped by type
    lines.append("\n== READABLE METHOD NAMES (non-obfuscated) ==")
    mrows = c.execute("select m.name, m.signature, m.is_public, m.is_static, m.il_size, t.full_name from methods m join types t on t.id=m.type_id where m.type_id in (%s) and m.is_obf=0 order by m.il_size desc limit 900" % ph, tids).fetchall()
    seen = set()
    for m in mrows:
        nm2 = m["name"]
        if nm2 in seen: continue
        seen.add(nm2)
        lines.append("%-46s | %s" % (nm2, (m["signature"] or "")[:150]))
        if len(seen) > 320: break

    # properties
    lines.append("\n== PROPERTIES ==")
    prows = c.execute("select p.name, p.type, t.full_name from properties p join types t on t.id=p.type_id where p.type_id in (%s) and p.is_obf=0" % ph, tids).fetchall()
    pnames = sorted(set(p["name"] for p in prows))
    lines.append("distinct=%d" % len(pnames))
    for i in range(0, len(pnames), 6):
        lines.append("  " + " | ".join(pnames[i:i+6]))

    # strings
    lines.append("\n== STRINGS (len>=5, deduped, top 220) ==")
    srows = c.execute("select s.value, t.full_name from strings s join methods m on m.id=s.method_id join types t on t.id=m.type_id where m.type_id in (%s) and length(s.value)>=5" % ph, tids).fetchall()
    cnt = collections.Counter(r["value"] for r in srows if len(r["value"]) < 70)
    for v, n in cnt.most_common(220):
        lines.append("%4d  %s" % (n, v.replace("\n", " ")))

    open(os.path.join(OUT, key + ".txt"), "w", encoding="utf-8").write("\n".join(lines))
    print("%-12s types=%-5d methods=%-6d file=%dKB" % (key, nt, nm, len(("\n".join(lines)).encode())//1024))

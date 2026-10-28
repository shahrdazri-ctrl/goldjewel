import sqlite3, sys, re, collections, os

DB = r"D:\REA-LAB\04-index\symbols.sqlite"
c = sqlite3.connect(DB); c.row_factory = sqlite3.Row
key = sys.argv[1]
ntop = int(sys.argv[2]) if len(sys.argv) > 2 else 30

def rows_for(key):
    base = """select t.*, a.assembly as asm from types t join assemblies a on a.id=t.asm_id where """
    if key == 'shell':
        return c.execute(base + """a.assembly in ('MatrixGold','MatrixGoldPlugin','MatrixGoldSkin','GemvisionWebhook','Stuller.Mvvm')
            and coalesce(t.namespace,'') not like 'MatrixGold.Views%' and coalesce(t.namespace,'') not like 'MatrixGold.ViewModels%'
            and coalesce(t.namespace,'') not like 'MatrixGold.Converters%' and coalesce(t.namespace,'') not like 'MatrixGold.Models%'""").fetchall()
    if key == 'document':
        return c.execute(base + """a.assembly in ('CS','CSDatas','CSBlockUtil','CSBlockDataUtils','CSCompatibility','CSLegacyObjects','CSCustomObjects')
            and coalesce(t.namespace,'') not like 'CSBlocks%'""").fetchall()
    if key == 'ui':
        return c.execute(base + """a.assembly='MatrixGold' and (t.namespace like 'MatrixGold.Views%' or t.namespace like 'MatrixGold.ViewModels%'
            or t.namespace like 'MatrixGold.Converters%' or t.namespace like 'MatrixGold.Models%' or t.namespace like 'MatrixGold.Helpers%')""").fetchall()
    if key == 'geometry':
        return c.execute(base + """a.assembly in ('GemvisionGeometry','GemvisionCommon') or (a.assembly='CSBlocks'
            and (t.namespace like 'CSBlocks.Transforms%' or t.namespace like 'CSBlocks.Curves%' or t.namespace like 'CSBlocks.Maths%' or t.namespace like 'CSBlocks.Core%'))""").fetchall()
    if key == 'parametric':
        return c.execute(base + """a.assembly in ('CSBlocks','CSBlockUtil','CSBlockDataUtils')
            and coalesce(t.namespace,'') not like 'CSBlocks.Transforms%' and coalesce(t.namespace,'') not like 'CSBlocks.Curves%'
            and coalesce(t.namespace,'') not like 'CSBlocks.Maths%' and coalesce(t.namespace,'') not like 'CSBlocks.Core%'
            and coalesce(t.namespace,'') not like 'CSBlocks.Gems%'""").fetchall()
    if key == 'gems':
        return c.execute(base + """a.assembly in ('CSGemInstance','CSMaterials','Common.Materials') or (a.assembly='CSBlocks' and t.namespace like 'CSBlocks.Gems%')""").fetchall()
    if key == 'ringsizing':
        return c.execute(base + "a.assembly='CSRingSizes'").fetchall()
    return c.execute(base + """a.assembly in ('GVBuilders','Localization','LocalizationCore','MatrixCommon','SharedTypes','Common','Common.UI')""").fetchall()

types = rows_for(key)
tids = [t['id'] for t in types]
ph = ",".join("?" * len(tids))
tc = dict(c.execute("select type_id, count(*) from methods where type_id in (%s) group by type_id" % ph, tids).fetchall())
print("### %s  types=%d methods=%d" % (key, len(types), sum(tc.values())))
print("\n-- types --")
for t in sorted(types, key=lambda x: -tc.get(x['id'], 0))[:ntop]:
    print("%4d %-56s %-14s %s" % (tc.get(t['id'], 0), (t['full_name'] or '')[:56], t['asm'], (t['base'] or '')[:40]))

print("\n-- readable methods --")
mr = c.execute("select distinct m.name from methods m where m.type_id in (%s) and m.is_obf=0 order by m.name" % ph, tids).fetchall()
names = [r[0] for r in mr if re.match(r"^[A-Za-z_][A-Za-z0-9_]{3,}$", r[0] or "")]
print("distinct=%d" % len(names))
for i in range(0, len(names), 4):
    print("  " + " | ".join(names[i:i+4]))

print("\n-- properties --")
pr = c.execute("select distinct p.name from properties p where p.type_id in (%s) and p.is_obf=0" % ph, tids).fetchall()
pn = sorted(r[0] for r in pr)
print("distinct=%d" % len(pn))
for i in range(0, len(pn), 8):
    print("  " + " | ".join(pn[i:i+8]))

print("\n-- strings --")
sr = c.execute("select s.value from strings s join methods m on m.id=s.method_id where m.type_id in (%s) and length(s.value)>=5" % ph, tids).fetchall()
cnt = collections.Counter(r[0] for r in sr if len(r[0]) < 60 and not re.search(r"[\u0001-\u001f]", r[0]))
for v, n in cnt.most_common(120):
    print("%3d %s" % (n, v.replace("\n", " ")))

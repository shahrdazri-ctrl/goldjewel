#!/usr/bin/env python3
"""Produce the evidence-backed fact pack used by the dossiers."""
import json
import os
import re
import sqlite3

LAB = r"D:\REA-LAB"
DB = os.path.join(LAB, "04-index", "symbols.sqlite")
OUT = os.path.join(LAB, "04-index", "semantic-facts.json")

FIRST_PARTY = (
    "MatrixGold", "CS", "CSBlocks", "MatrixGoldPlugin", "SharedTypes", "MatrixCommon",
    "Common", "Localization", "LocalizationCore", "CSGemInstance", "CSMaterials", "CSRingSizes",
    "GVBuilders", "GemvisionGeometry", "GemvisionCommon", "GemvisionWebhook", "Viewport2D",
    "SuperView", "CSDatas", "CSBlockUtil", "CSBlockDataUtils", "CSCompatibility",
    "CSCustomObjects", "CSLegacyObjects", "DebugDraw", "EventSystemNuGetPackage",
    "Stuller.Mvvm", "Stuller.Web.API.v2.Models", "ToastNotifications", "ToastNotifications.Messages",
    "MatrixGoldSkin", "Common.Materials", "Common.UI"
)


def q(con, sql, args=()):
    return [dict(row) for row in con.execute(sql, args).fetchall()]


def main():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    facts = {}

    facts["assemblies"] = q(con, """
        SELECT assembly, file, n_types, n_methods, n_strings, n_calls, decompiled_cs
        FROM assemblies ORDER BY n_methods DESC
    """)
    facts["first_party_totals"] = q(con, """
        SELECT a.assembly, a.n_types, a.n_methods, a.n_strings, a.n_calls, a.decompiled_cs,
               (SELECT COUNT(*) FROM types t WHERE t.asm_id=a.id AND t.is_obf=1) AS obf_types,
               (SELECT COUNT(*) FROM methods m JOIN types t ON m.type_id=t.id WHERE t.asm_id=a.id AND m.is_obf=1) AS obf_methods
        FROM assemblies a
        WHERE a.assembly IN (%s)
        ORDER BY a.n_methods DESC
    """ % ",".join("?" * len(FIRST_PARTY)), FIRST_PARTY)

    facts["matrixgold_namespaces"] = q(con, """
        SELECT t.namespace, COUNT(*) AS types
        FROM types t JOIN assemblies a ON t.asm_id=a.id
        WHERE a.assembly='MatrixGold' GROUP BY t.namespace ORDER BY types DESC LIMIT 60
    """)
    facts["cs_namespaces"] = q(con, """
        SELECT t.namespace, COUNT(*) AS types
        FROM types t JOIN assemblies a ON t.asm_id=a.id
        WHERE a.assembly IN ('CS','CSBlocks') GROUP BY t.namespace ORDER BY types DESC LIMIT 60
    """)
    facts["csblocks_namespaces"] = q(con, """
        SELECT t.namespace, COUNT(*) AS types
        FROM types t JOIN assemblies a ON t.asm_id=a.id
        WHERE a.assembly='CSBlocks' GROUP BY t.namespace ORDER BY types DESC LIMIT 60
    """)

    for asm in ("MatrixGold", "CS", "CSBlocks", "MatrixGoldPlugin"):
        facts[f"top_types_{asm}"] = q(con, """
            SELECT t.full_name, t.is_obf, COUNT(m.id) AS methods
            FROM types t JOIN assemblies a ON t.asm_id=a.id
            LEFT JOIN methods m ON m.type_id=t.id
            WHERE a.assembly=? GROUP BY t.id ORDER BY methods DESC LIMIT 35
        """, (asm,))

    facts["top_declaring_types"] = q(con, """
        SELECT c.declaring_type, COUNT(*) AS calls
        FROM calls c GROUP BY c.declaring_type ORDER BY calls DESC LIMIT 80
    """)
    facts["rhino_apis"] = q(con, """
        SELECT c.declaring_type, c.callee, COUNT(*) AS calls
        FROM calls c WHERE c.declaring_type LIKE 'Rhino.%'
        GROUP BY c.declaring_type, c.callee ORDER BY calls DESC LIMIT 60
    """)
    facts["rhino_totals"] = q(con, """
        SELECT c.declaring_type, COUNT(*) AS calls FROM calls c
        WHERE c.declaring_type LIKE 'Rhino.%' GROUP BY c.declaring_type ORDER BY calls DESC LIMIT 40
    """)
    facts["windows_apis"] = q(con, """
        SELECT c.declaring_type, COUNT(*) AS calls FROM calls c
        WHERE c.declaring_type LIKE 'System.Windows.%' GROUP BY c.declaring_type ORDER BY calls DESC LIMIT 30
    """)
    facts["data_apis"] = q(con, """
        SELECT c.declaring_type, COUNT(*) AS calls FROM calls c
        WHERE c.declaring_type LIKE 'System.Data%' OR c.declaring_type LIKE '%EntityFramework%'
        GROUP BY c.declaring_type ORDER BY calls DESC LIMIT 30
    """)
    facts["integration_apis"] = q(con, """
        SELECT c.declaring_type, COUNT(*) AS calls FROM calls c
        WHERE c.declaring_type LIKE 'Stuller%' OR c.declaring_type LIKE '%GraphQL%'
           OR c.declaring_type LIKE 'System.ServiceModel%' OR c.declaring_type LIKE '%HttpClient%'
        GROUP BY c.declaring_type ORDER BY calls DESC LIMIT 30
    """)

    facts["strings_urls"] = q(con, """
        SELECT s.value, COUNT(*) AS n FROM strings s
        WHERE s.value LIKE 'http%' OR s.value LIKE '%stuller%' OR s.value LIKE '%graphql%'
           OR s.value LIKE 'net.tcp%' OR s.value LIKE '%wcf%' OR s.value LIKE '%/api/%'
        GROUP BY s.value ORDER BY n DESC LIMIT 120
    """)
    facts["strings_extensions"] = q(con, """
        SELECT s.value, COUNT(*) AS n FROM strings s
        WHERE s.value LIKE '%.3dm' OR s.value LIKE '%.mgm' OR s.value LIKE '%.mge'
           OR s.value LIKE '%.mgstyle' OR s.value LIKE '%.mgp' OR s.value LIKE '%.rmtl'
           OR s.value LIKE '%.pat' OR s.value LIKE '%.stl' OR s.value LIKE '%.obj'
           OR s.value LIKE '%.usd%' OR s.value LIKE '%.csv'
        GROUP BY s.value ORDER BY n DESC LIMIT 80
    """)
    facts["strings_commands"] = q(con, """
        SELECT s.value, COUNT(*) AS n FROM strings s
        WHERE s.value LIKE '!_%' OR s.value LIKE '%Command%' OR s.value LIKE '%Undo%'
        GROUP BY s.value ORDER BY n DESC LIMIT 80
    """)

    facts["type_patterns"] = {}
    for pat in ("%ViewModel", "%View", "%Command", "%Builder", "%Gem%", "%Ring%", "%Material%", "%Block%", "%Pattern%", "%Setting%", "%Stone%"):
        facts["type_patterns"][pat] = q(con, """
            SELECT t.full_name, COUNT(m.id) AS methods
            FROM types t JOIN assemblies a ON t.asm_id=a.id
            LEFT JOIN methods m ON m.type_id=t.id
            WHERE a.assembly IN (%s) AND t.full_name LIKE ?
            GROUP BY t.id ORDER BY methods DESC LIMIT 25
        """ % ",".join("?" * len(FIRST_PARTY)), FIRST_PARTY + (pat,))

    facts["il_errors"] = q(con, """
        SELECT a.assembly, COUNT(*) AS errors FROM methods m
        JOIN types t ON m.type_id=t.id JOIN assemblies a ON t.asm_id=a.id
        WHERE m.il_error <> '' GROUP BY a.assembly ORDER BY errors DESC
    """)

    facts["obfuscation"] = q(con, """
        SELECT a.assembly, a.n_types, a.n_methods,
               (SELECT COUNT(*) FROM types t WHERE t.asm_id=a.id AND t.is_obf=1) AS obf_types,
               (SELECT COUNT(*) FROM methods m JOIN types t ON m.type_id=t.id WHERE t.asm_id=a.id AND m.is_obf=1) AS obf_methods
        FROM assemblies a WHERE a.assembly IN (%s) ORDER BY a.n_methods DESC
    """ % ",".join("?" * len(FIRST_PARTY)), FIRST_PARTY)

    xaml_summary = os.path.join(LAB, "04-index", "xaml-summary.json")
    if os.path.exists(xaml_summary):
        facts["xaml"] = json.load(open(xaml_summary, encoding="utf-8"))

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(facts, fh, indent=2)

    # Compact human-readable summary.
    print("first-party:")
    for row in facts["first_party_totals"]:
        print(f"  {row['assembly']:<28} types={row['n_types']:<5} methods={row['n_methods']:<6} strings={row['n_strings']:<6} calls={row['n_calls']:<7} cs={row['decompiled_cs']}")
    print("top Rhino namespaces:")
    for row in facts["rhino_totals"][:12]:
        print(f"  {row['declaring_type']}: {row['calls']}")
    print("top declaring types:")
    for row in facts["top_declaring_types"][:12]:
        print(f"  {row['declaring_type']}: {row['calls']}")
    print("urls:", len(facts["strings_urls"]), "extensions:", len(facts["strings_extensions"]))
    print("wrote", OUT)


if __name__ == "__main__":
    main()

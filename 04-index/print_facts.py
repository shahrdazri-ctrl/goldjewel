import json

f = json.load(open(r"D:\REA-LAB\04-index\semantic-facts.json", encoding="utf-8"))

print("=== URL / ENDPOINT STRINGS ===")
for row in f["strings_urls"][:60]:
    print(f"{row['n']:>4}  {row['value'][:160]}")

print("\n=== FILE EXTENSION STRINGS ===")
for row in f["strings_extensions"]:
    print(f"{row['n']:>4}  {row['value'][:120]}")

print("\n=== CS NAMESPACES ===")
for row in f["cs_namespaces"][:40]:
    print(f"{row['types']:>5}  {row['namespace']}")

print("\n=== CSBLOCKS NAMESPACES ===")
for row in f["csblocks_namespaces"][:40]:
    print(f"{row['types']:>5}  {row['namespace']}")

for pat in ("%Builder", "%Gem%", "%Ring%", "%Material%", "%Block%", "%Pattern%"):
    print(f"\n=== TYPES {pat} ===")
    for row in f["type_patterns"][pat][:15]:
        print(f"{row['methods']:>5}  {row['full_name']}")

print("\n=== XAML CLASSES (first 30) ===")
for path, cls in list(f.get("xaml", {}).get("classes", {}).items())[:30]:
    print(f"{cls:<55} {path}")

print("\n=== XAML TOP COMMANDS ===")
for value, n in f.get("xaml", {}).get("top_commands", [])[:25]:
    print(f"{n:>4}  {value[:140]}")

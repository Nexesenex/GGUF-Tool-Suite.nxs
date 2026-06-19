import sys
import re

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <recipe> <mapfile> <outfile>", file=sys.stderr)
        sys.exit(1)

    recipe_file = sys.argv[1]
    map_file = sys.argv[2]
    out_file = sys.argv[3]

    patterns = []
    with open(recipe_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("["):
                continue
            if "=" in line:
                regex_str, qtype = line.split("=", 1)
                qtype = qtype.strip()
                if qtype:
                    patterns.append((re.compile(regex_str), qtype))

    seen = set()
    results = []
    with open(map_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":", 3)
            if len(parts) < 3:
                continue
            fname = parts[0]
            tname = parts[2]
            m = re.search(r"-(\d{5})-of-\d{5}\.gguf", fname)
            if not m:
                continue
            chunknum = int(m.group(1))

            for pat, qtype in patterns:
                if pat.search(tname):
                    key = (qtype, chunknum)
                    if key not in seen:
                        seen.add(key)
                        results.append((chunknum, qtype))
                    break

    results.sort(key=lambda x: x[0])
    with open(out_file, "w", encoding="utf-8") as f:
        for chunknum, qtype in results:
            if chunknum == 1:
                continue
            f.write(f"{qtype} {chunknum}\n")

if __name__ == "__main__":
    main()

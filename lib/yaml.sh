#!/usr/bin/env bash

# Minimal YAML reader for the simple profile format used here.
# Supports keys with indentation and scalar string/number values.
# No arrays, no complex YAML.

yaml_get() {
  local file="$1"
  local path="$2"

  python3 - "$file" "$path" <<'PY'
import sys

file_path = sys.argv[1]
wanted = sys.argv[2].split(".")

data = {}
stack = [(-1, data)]

def strip_quotes(v):
    v = v.strip()
    if len(v) >= 2 and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
        return v[1:-1]
    return v

with open(file_path, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        indent = len(line) - len(line.lstrip(" "))
        key, value = line.strip().split(":", 1)
        key = key.strip()
        value = value.strip()

        while stack and indent <= stack[-1][0]:
            stack.pop()

        parent = stack[-1][1]

        if value == "":
            obj = {}
            parent[key] = obj
            stack.append((indent, obj))
        else:
            parent[key] = strip_quotes(value)

cur = data
for p in wanted:
    if isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(1)

if isinstance(cur, dict):
    sys.exit(1)

print(cur)
PY
}

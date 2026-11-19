"""Dump primary meanings of curated IELTS seed words for editorial review (developer tool)."""
import json
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")
db = sqlite3.connect(sys.argv[1])
cfg = json.load(open(sys.argv[2], encoding="utf-8"))
seeds = sorted({s.lower() for t in cfg["topics"] for s in t["seeds"]})
out = []
for s in seeds:
    for hw, pos, vi, src in db.execute(
            "select headword,pos,primary_vi,primary_vi_source from vocabulary_entries where headword_norm=?", (s,)):
        if src != "curated":
            out.append(f"{hw}|{pos[:3]}: {vi}")
print(" ; ".join(out))
print(len(out), file=sys.stderr)

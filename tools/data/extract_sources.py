"""Step 1 of the vocabulary pipeline.

Streams the large Wiktextract dumps (English Wiktionary + Vietnamese Wiktionary,
both CC BY-SA, extracted by kaikki.org) and writes slim JSONL files that keep only
the fields the build step needs, for English-language entries that are plausible
candidates for the IELTS lexicon.

Usage:  python -I tools/data/extract_sources.py <raw_dir> <work_dir>
"""
import gzip
import json
import os
import re
import sys

SKIP_POS = {"name", "character", "symbol", "suffix", "prefix", "infix",
            "interfix", "affix", "circumfix", "punct", "romanization", "num",
            "abbrev", "contraction"}

WORD_RE = re.compile(r"^[A-Za-z][A-Za-z' \-\.]*[A-Za-z\.]$|^[A-Za-z]$")


def slim_sense(s):
    out = {}
    for k in ("glosses", "tags", "topics", "raw_tags", "qualifier"):
        if s.get(k):
            out[k] = s[k]
    if s.get("form_of"):
        out["form_of"] = [x.get("word") for x in s["form_of"]]
    if s.get("alt_of"):
        out["alt_of"] = [x.get("word") for x in s["alt_of"]]
    exs = []
    for e in s.get("examples", []) or []:
        t = e.get("text")
        if not t:
            continue
        ex = {"text": t, "type": e.get("type")}
        if e.get("translation"):
            ex["translation"] = e["translation"]
        if e.get("ref"):
            ex["ref"] = e["ref"][:200]
        exs.append(ex)
    if exs:
        out["examples"] = exs
    for k in ("synonyms", "antonyms"):
        if s.get(k):
            out[k] = [x.get("word") for x in s[k] if x.get("word")]
    cats = [c.get("name") if isinstance(c, dict) else c for c in s.get("categories", []) or []]
    cats = [c for c in cats if c and not c.startswith(("Pages ", "Terms with ", "English entries", "Entries with", "Requests", "Pages with"))]
    if cats:
        out["categories"] = cats
    if s.get("id"):
        out["id"] = s["id"]
    return out


def slim_entry(d, vi_only_translations=True):
    out = {"word": d["word"], "pos": d.get("pos")}
    if d.get("pos_title"):
        out["pos_title"] = d["pos_title"]
    out["senses"] = [slim_sense(s) for s in d.get("senses", []) or []]
    sounds = []
    for s in d.get("sounds", []) or []:
        if s.get("ipa"):
            sounds.append({"ipa": s["ipa"], "tags": s.get("tags", []) + s.get("raw_tags", [])})
        elif s.get("audio"):
            sounds.append({"audio": s["audio"], "tags": s.get("tags", []) + s.get("raw_tags", [])})
    if sounds:
        out["sounds"] = sounds
    if d.get("forms"):
        out["forms"] = [{"form": f.get("form"), "tags": f.get("tags", [])} for f in d["forms"] if f.get("form")][:30]
    for k in ("synonyms", "antonyms", "derived", "related"):
        if d.get(k):
            out[k] = [x.get("word") for x in d[k] if x.get("word")][:80]
    tr = d.get("translations") or []
    vi = [{"word": t.get("word"), "sense": t.get("sense"), "tags": t.get("tags", [])}
          for t in tr if t.get("code") == "vi" and t.get("word")]
    # salience signal: how many translations (all languages) each translation-table sense has
    counts = {}
    for t in tr:
        k = (t.get("sense") or "").strip()
        counts[k] = counts.get(k, 0) + 1
    if counts:
        out["tr_counts"] = counts
    # translations may also live inside senses in some dumps
    for s in d.get("senses", []) or []:
        for t in s.get("translations", []) or []:
            if t.get("code") == "vi" and t.get("word"):
                vi.append({"word": t["word"], "sense": t.get("sense") or (s.get("glosses") or [None])[0], "tags": t.get("tags", [])})
    if vi:
        out["vi_translations"] = vi
    cats = [c.get("name") if isinstance(c, dict) else c for c in d.get("categories", []) or []]
    cats = [c for c in cats if c and not c.startswith(("Pages ", "Terms with ", "English entries", "Entries with", "Requests", "Pages with"))]
    if cats:
        out["categories"] = cats[:60]
    if d.get("tags"):
        out["tags"] = d["tags"]
    return out


def main():
    raw, work = sys.argv[1], sys.argv[2]
    os.makedirs(work, exist_ok=True)

    # --- Vietnamese Wiktionary: English entries with Vietnamese glosses ---
    vi_words = set()
    n_vi = 0
    with gzip.open(os.path.join(raw, "vi-wiktextract.jsonl.gz"), "rt", encoding="utf-8") as f, \
            open(os.path.join(work, "vi_en_entries.jsonl"), "w", encoding="utf-8") as out:
        for line in f:
            d = json.loads(line)
            if d.get("lang_code") != "en":
                continue
            w = d.get("word", "")
            if not WORD_RE.match(w):
                continue
            e = slim_entry(d)
            out.write(json.dumps(e, ensure_ascii=False) + "\n")
            vi_words.add(w.lower())
            n_vi += 1
    print(f"vi-wiktionary English entries kept: {n_vi} ({len(vi_words)} distinct words)")

    # --- English Wiktionary: keep entries for candidate words ---
    n_en = 0
    with open(os.path.join(raw, "en-wiktextract.jsonl"), encoding="utf-8") as f, \
            open(os.path.join(work, "en_entries.jsonl"), "w", encoding="utf-8") as out:
        for line in f:
            if '"lang_code": "en"' not in line:
                continue
            d = json.loads(line)
            if d.get("lang_code") != "en" or d.get("pos") in SKIP_POS:
                continue
            w = d.get("word", "")
            if not WORD_RE.match(w):
                continue
            has_vi = '"code": "vi"' in line
            multi = " " in w and len(w.split()) <= 6
            if not has_vi and w.lower() not in vi_words and not multi:
                continue
            out.write(json.dumps(slim_entry(d), ensure_ascii=False) + "\n")
            n_en += 1
    print(f"en-wiktionary English entries kept: {n_en}")


if __name__ == "__main__":
    main()

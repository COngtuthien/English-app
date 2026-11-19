"""Step 2 of the vocabulary pipeline: build the offline SQLite content database.

Inputs (see DATASET_SOURCES.md for licences):
  <raw>/cefrj.csv, octanove-c1c2.csv        CEFR-J Wordlist 1.5 / Octanove C1-C2 profile
  <raw>/NAWL_12_*.csv, NGSL_12_stats.csv     New Academic Word List / New General Service List
  <raw>/eng_sentences.tsv.bz2, vie_sentences.tsv.bz2, eng-vie_links.tsv.bz2   Tatoeba
  <raw>/ipa_en_UK.txt, ipa_en_US.txt          ipa-dict (MIT)
  <work>/en_entries.jsonl, vi_en_entries.jsonl   slimmed Wiktextract data (extract_sources.py)
  tools/data/curated/*.json                   original editorial content

Output:
  assets/db/vocab.db           content database bundled in the APK
  tools/data/out/build_stats.json

Usage: python -I tools/data/build_database.py <raw_dir> <work_dir> <curated_dir> <out_db> <stats_json>

Nothing here fabricates lexical data: every definition, translation, example,
pronunciation and relation is copied from a named source (recorded per row), or
comes from the curated editorial files written for this project. Entries that do
not reach the minimum quality bar are dropped and counted in the build stats.
"""
import bz2
import collections
import csv
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata

sys.stdout.reconfigure(encoding="utf-8")

CONTENT_VERSION = 1

SOURCES = [
    ("enwikt", "English Wiktionary (via Wiktextract / kaikki.org)", "https://en.wiktionary.org/ ; https://kaikki.org/dictionary/English/",
     "CC BY-SA 4.0 (and GFDL)", "Definitions, examples, IPA, synonyms, antonyms, related terms and Vietnamese translation-table entries © Wiktionary contributors. Extraction by Tatu Ylonen, Wiktextract (LREC 2022)."),
    ("viwikt", "Vietnamese Wiktionary (via Wiktextract / kaikki.org)", "https://vi.wiktionary.org/ ; https://kaikki.org/viwiktionary/",
     "CC BY-SA 4.0 (and GFDL)", "Vietnamese glosses and phrase translations for English entries © Wiktionary contributors (vi.wiktionary.org), much of it originally from the Free Vietnamese Dictionary Project."),
    ("tatoeba", "Tatoeba sentence corpus", "https://tatoeba.org/",
     "CC BY 2.0 FR", "Example sentences and Vietnamese translations © Tatoeba contributors. Sentence IDs are stored with every example."),
    ("cefrj", "CEFR-J Wordlist Version 1.5", "https://github.com/openlanguageprofiles/olp-en-cefrj",
     "Free for research and commercial use with citation", "The CEFR-J Wordlist Version 1.5. Compiled by Yukio Tono, Tokyo University of Foreign Studies. Retrieved from http://www.cefr-j.org/download.html"),
    ("octanove", "Octanove Vocabulary Profile C1/C2 1.0", "https://github.com/openlanguageprofiles/olp-en-cefrj",
     "CC BY-SA 4.0", "Octanove Vocabulary Profile C1/C2 (ver 1.0) © Octanove Labs."),
    ("nawl", "New Academic Word List 1.2", "https://www.newgeneralservicelist.com/new-academic-word-list",
     "CC BY-SA 4.0", "Browne, C., Culligan, B. & Phillips, J. The New Academic Word List 1.2."),
    ("ngsl", "New General Service List 1.2", "https://www.newgeneralservicelist.com/new-general-service-list",
     "CC BY-SA 4.0", "Browne, C., Culligan, B. & Phillips, J. The New General Service List 1.2."),
    ("ipadict", "ipa-dict (open-dict-data)", "https://github.com/open-dict-data/ipa-dict",
     "MIT", "IPA transcriptions en_UK / en_US © 2016 dohliam and contributors."),
    ("curated", "IELTS Vocabulary Master editorial content", "(this project)",
     "CC BY-SA 4.0", "Original IELTS expressions, collocations, example sentences, Vietnamese explanations, usage notes, exercises and topic mapping written for this app."),
]

CEFR_POS = {
    "noun": "noun", "verb": "verb", "adjective": "adjective", "adverb": "adverb", "pronoun": "pronoun",
    "preposition": "preposition", "determiner": "determiner", "conjunction": "conjunction", "number": "number",
    "modal auxiliary": "verb", "be-verb": "verb", "do-verb": "verb", "have-verb": "verb",
    "interjection": "interjection", "vern": "verb",
}
WIKT_POS = {
    "noun": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb", "prep": "preposition",
    "conj": "conjunction", "pron": "pronoun", "det": "determiner", "article": "determiner",
    "intj": "interjection", "num": "number", "phrase": "phrase", "prep_phrase": "phrase",
    "proverb": "phrase", "particle": "particle",
}
POS_VI = {
    "noun": "danh từ", "verb": "động từ", "adjective": "tính từ", "adverb": "trạng từ", "pronoun": "đại từ",
    "preposition": "giới từ", "determiner": "hạn định từ", "conjunction": "liên từ", "number": "số từ",
    "interjection": "thán từ", "phrase": "cụm từ", "phrasal verb": "cụm động từ", "idiom": "thành ngữ",
    "collocation": "kết hợp từ", "expression": "cách diễn đạt", "particle": "tiểu từ",
}
BAD_SENSE_TAGS = {"obsolete", "archaic", "dated", "rare", "dialectal", "nonstandard", "vulgar", "offensive",
                  "derogatory", "ethnic", "slur", "historical", "misspelling", "proscribed", "humorous",
                  "Internet", "euphemistic", "pejorative", "sexual", "Northern-England", "Scotland", "Ireland",
                  "Australia", "New-Zealand", "South-Africa", "India", "Philippines", "Singapore", "Canada",
                  "Caribbean", "Jamaica", "Nigeria", "Hong-Kong", "Malaysia", "Pakistan", "Wales", "abbreviation",
                  "initialism", "acronym", "no-gloss", "uncommon", "nonce-word", "ironic"}
REGISTER_TAGS = ["formal", "informal", "colloquial", "slang", "literary", "technical", "poetic"]
PARTICLES = {"up", "down", "out", "off", "on", "in", "over", "away", "back", "through", "around", "round",
             "about", "along", "across", "forward", "after", "into", "for", "with", "by", "apart", "aside",
             "together", "ahead", "behind", "of", "from", "to", "at", "upon", "onto", "under"}
NICHE_TOPICS = {"religion", "christianity", "theology", "mysticism", "heraldry", "nobility", "card-games", "poker",
                 "chess", "cricket", "baseball", "bdsm", "sexuality", "nautical", "falconry", "bowling", "golf",
                 "fencing", "juggling", "tarot", "mythology", "occult", "freemasonry", "philately", "numismatics",
                 "american-football", "rugby", "snooker", "billiards", "bridge", "backgammon", "go", "video-games",
                 "role-playing-games", "wrestling", "horse-racing", "hunting", "printing", "typography", "knitting"}
IPA_UK_TAGS = {"Received-Pronunciation", "UK", "British", "Standard-Southern-British", "Southern-England"}
IPA_US_TAGS = {"General-American", "US", "American"}
WORD_TOKEN = re.compile(r"[a-z]+(?:['’-][a-z]+)*")
NAME_WORDS = {"tom", "mary", "john", "ken", "jim", "jack", "bob", "alice", "mike", "jane", "taro", "tony", "lucy",
              "sami", "layla", "dan", "linda", "muiriel"}
PROFANITY = {"fuck", "fucking", "shit", "bitch", "cunt", "dick", "pussy", "whore", "slut", "nigger", "faggot", "bastard",
             "piss", "cock", "asshole", "arse", "wank", "jerk off", "piss off"}
VI_BAD_PREFIX = ("xem ", "như ", "dạng ", "số nhiều của", "quá khứ", "phân từ", "viết tắt", "cách viết khác")
VI_ARCHAIC = ("(từ cổ", "(cổ", "(từ hiếm", "(từ lóng", "(thô tục", "(tục", "(đùa cợt", "(nghĩa xấu")


def strip_vi(text):
    """Lowercase + remove Vietnamese diacritics (kept identical to lib/core/text/vietnamese.dart)."""
    t = text.replace("đ", "d").replace("Đ", "D")
    t = unicodedata.normalize("NFD", t)
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return t.lower()


def stable_id(key):
    return int(hashlib.sha1(key.encode("utf-8")).hexdigest()[:12], 16)


def tokens(text):
    return WORD_TOKEN.findall(text.lower().replace("’", "'"))


def clean_gloss_en(g):
    g = g.strip()
    g = re.sub(r"\s+", " ", g)
    return g


def sense_ok(s):
    if s.get("form_of") or s.get("alt_of"):
        return False
    tags = set(s.get("tags") or [])
    if tags & BAD_SENSE_TAGS:
        return False
    if "form-of" in tags or "alt-of" in tags:
        return False
    gl = s.get("glosses") or []
    if not gl:
        return False
    g = gl[-1]
    low = g.lower()
    if len(g) < 3 or len(g) > 300:
        return False
    if low.startswith(("synonym of", "alternative form", "alternative spelling", "plural of", "obsolete form",
                       "misspelling of", "abbreviation of", "initialism of", "acronym of", "eye dialect",
                       "short for", "clipping of", "archaic form", "nonstandard form", "dated form",
                       "simple past", "past participle", "present participle", "third-person", "simple subjunctive",
                       "comparative form", "superlative form", "comparative of", "superlative of", "inflection of",
                       "en dash", "nonstandard spelling", "pronunciation spelling", "contraction of", "ellipsis of",
                       "american spelling", "british spelling", "standard spelling", "canadian spelling",
                       "oxford british", "american and oxford")):
        return False
    return True


def expand_senses(senses):
    """Wiktextract nests sub-senses as glosses=[parent, child]. Emit the parent gloss once (as its own
    sense) before its children so the general meaning is not lost."""
    out, seen_parent = [], set()
    for s in senses:
        gl = s.get("glosses") or []
        if len(gl) >= 2 and gl[0] not in seen_parent:
            seen_parent.add(gl[0])
            parent = {k: v for k, v in s.items() if k not in ("examples", "synonyms", "antonyms", "glosses")}
            parent["glosses"] = [gl[0]]
            out.append(parent)
        out.append(s)
    return out


def clean_vi_gloss(g):
    g = re.sub(r"\s+", " ", g.strip())
    g = g.strip(" .;,")
    return g


def vi_gloss_ok(g, headword):
    if not g or len(g) < 2 or len(g) > 160:
        return False
    low = g.lower()
    if low.startswith(VI_BAD_PREFIX):
        return False
    if low.startswith(VI_ARCHAIC):
        return False
    if low == headword.lower():
        return False
    # glosses that are plain English (no Vietnamese letters, all ASCII words) are usually untranslated
    if all(ord(c) < 128 for c in g) and len(g.split()) <= 3 and not re.search(r"[đơưăâêô]", g):
        vi_markers = {"sự", "cái", "người", "làm", "có", "không", "của", "và", "bị", "được", "ra", "vào"}
        if not (set(low.split()) & vi_markers):
            return False
    return True


def has_domain_label(g):
    return g.strip().startswith("(")


def short_vi(g, max_len=70):
    # drop a leading register/domain label such as "(thành ngữ tính)" when real text follows
    m = re.match(r"^\(([^()]{1,30})\)\s*(.+)$", g)
    if m and len(m.group(2)) >= 2:
        g = m.group(2)
    parts = [p.strip() for p in re.split(r";", g) if p.strip()]
    out = parts[0] if parts else g
    if len(parts) > 1 and len(out) + len(parts[1]) + 2 <= max_len:
        out = out + "; " + parts[1]
    if len(out) > max_len:
        cut = out[:max_len]
        cut = cut[: cut.rfind(",")] if "," in cut else cut
        out = cut.strip()
    out = out.strip(" .;,")
    if out:
        first = out.split()[0]
        if not (len(first) > 1 and first.isupper()):
            out = out[0].lower() + out[1:]
    return out


def jaccard(a, b):
    sa, sb = set(tokens(a)), set(tokens(b))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


class Builder:
    def __init__(self, raw, work, curated, out_db, stats_path):
        self.raw, self.work, self.curated, self.out_db, self.stats_path = raw, work, curated, out_db, stats_path
        self.stats = collections.Counter()
        self.drop = collections.Counter()
        self.drop_examples = collections.defaultdict(list)

    # ------------------------------------------------------------------ loading
    def load(self):
        t = time.time()
        self.en = collections.defaultdict(list)
        with open(os.path.join(self.work, "en_entries.jsonl"), encoding="utf-8") as f:
            for line in f:
                d = json.loads(line)
                self.en[d["word"].lower()].append(d)
        self.vi = collections.defaultdict(list)
        with open(os.path.join(self.work, "vi_en_entries.jsonl"), encoding="utf-8") as f:
            for line in f:
                d = json.loads(line)
                self.vi[d["word"].lower()].append(d)
        print(f"loaded wiktionary: en={len(self.en)} vi={len(self.vi)} ({time.time()-t:.0f}s)", flush=True)

        self.cefr_rows = []
        for fname, src in (("cefrj.csv", "cefrj"), ("octanove-c1c2.csv", "octanove")):
            with open(os.path.join(self.raw, fname), encoding="utf-8") as f:
                for r in csv.DictReader(f):
                    pos = CEFR_POS.get(r["pos"].strip())
                    hw = r["headword"].strip()
                    if not pos or not hw:
                        self.drop["cefr_row_unusable_pos"] += 1
                        continue
                    variants = [v.strip() for v in hw.split("/") if v.strip()]
                    self.cefr_rows.append({"variants": variants, "pos": pos, "cefr": r["CEFR"].strip(), "src": src})
        self.nawl = []
        with open(os.path.join(self.raw, "NAWL_12_lemmatized_for_teaching.csv"), encoding="latin-1") as f:
            for line in f:
                parts = [p.strip() for p in line.strip().split(",") if p.strip()]
                if parts:
                    self.nawl.append(parts[0])
        self.nawl_set = {w.lower() for w in self.nawl}
        self.nawl_defs = {}
        with open(os.path.join(self.raw, "NAWL_12_with_en_definitions.csv"), encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                self.nawl_defs[r["Meanings"].strip().lower()] = (r["English Definition"].strip(), r["POS"].strip())
        self.ngsl_rank = {}
        with open(os.path.join(self.raw, "NGSL_12_stats.csv"), encoding="utf-8") as f:
            for r in csv.DictReader(f):
                try:
                    self.ngsl_rank[r["Lemma"].strip().lower()] = int(r["SFI Rank"])
                except ValueError:
                    pass
        self.ipa = {"uk": {}, "us": {}}
        for k, fname in (("uk", "ipa_en_UK.txt"), ("us", "ipa_en_US.txt")):
            with open(os.path.join(self.raw, fname), encoding="utf-8") as f:
                for line in f:
                    if "\t" in line:
                        w, p = line.rstrip("\n").split("\t", 1)
                        self.ipa[k].setdefault(w.lower(), p.split(",")[0].strip())
        cur = lambda n: json.load(open(os.path.join(self.curated, n), encoding="utf-8"))
        self.topics_cfg = cur("topics.json")
        self.expr_cfg = cur("expressions_writing.json")
        self.usage_cfg = cur("usage_notes.json")
        self.writing_cfg = cur("writing_exercises.json")
        self.speaking_cfg = cur("speaking_packs.json")
        vm = cur("vi_meanings.json")
        self.vi_override = {}
        for k, v in vm["words"].items():
            self.vi_override[k.lower()] = v
        for k, v in vm["phrasal_verbs"].items():
            self.vi_override[f"{k.lower()}|phrasal verb"] = v
        self.curated_pv = list(vm["phrasal_verbs"].keys())
        print("loaded lists and curated content", flush=True)

    # ------------------------------------------------------------------ helpers
    def en_entries_for(self, variants, pos):
        """Wiktionary entries of the requested canonical POS for the first variant that has any."""
        for v in variants:
            cands = self.en.get(v.lower(), [])
            exact = [e for e in cands if e["word"] == v and WIKT_POS.get(e["pos"]) == pos]
            loose = [e for e in cands if WIKT_POS.get(e["pos"]) == pos]
            chosen = exact or loose
            chosen = [e for e in chosen if any(sense_ok(s) for s in e["senses"])]
            if chosen:
                return v, chosen
        return None, []

    def vi_entries_for(self, variants, pos):
        for v in variants:
            cands = self.vi.get(v.lower(), [])
            chosen = [e for e in cands if WIKT_POS.get(e.get("pos")) == pos]
            if chosen:
                return chosen
        return []

    def forms_for(self, word, en_entries, pos):
        forms = {word.lower()}
        for e in en_entries:
            for f in e.get("forms") or []:
                form = (f.get("form") or "").lower()
                tags = set(f.get("tags") or [])
                if not form or tags & {"obsolete", "archaic", "dialectal", "alternative", "nonstandard", "rare",
                                        "table-tags", "inflection-template", "romanization"}:
                    continue
                if " " in form and " " not in word:
                    continue  # periphrastic comparatives like "more sustainable"
                if re.fullmatch(r"[a-z][a-z'\- ]*", form):
                    forms.add(form)
        return forms

    # ------------------------------------------------------------------ tatoeba
    def load_tatoeba(self, needed_unigrams, needed_ngrams):
        t = time.time()
        vie = {}
        with bz2.open(os.path.join(self.raw, "vie_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 3:
                    vie[p[0]] = p[2]
        eng2vie = {}
        with bz2.open(os.path.join(self.raw, "eng-vie_links.tsv.bz2"), "rt", encoding="utf-8") as f:
            for line in f:
                p = line.strip().split("\t")
                if len(p) == 2 and p[1] in vie:
                    eng2vie.setdefault(p[0], vie[p[1]])
        self.tat_freq = collections.Counter()
        self.tat_cap = collections.Counter()
        self.tat_hits = collections.defaultdict(list)  # form -> [(score, sid)]
        self.tat_text = {}
        maxn = max([len(k) for k in needed_ngrams] + [2])
        n = 0
        with bz2.open(os.path.join(self.raw, "eng_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if len(p) < 3:
                    continue
                sid, text = p[0], p[2]
                n += 1
                toks = tokens(text)
                if not toks:
                    continue
                matched = set()
                for tk in toks:
                    if tk in needed_unigrams:
                        matched.add(tk)
                # capitalised mid-sentence occurrences reveal proper names ("Harry", "China")
                for raw_tok in re.findall(r"(?<=[a-z,;] )[A-Z][A-Za-z]+", text):
                    lt = raw_tok.lower()
                    if lt in needed_unigrams:
                        self.tat_cap[lt] += 1
                for size in range(2, maxn + 1):
                    for i in range(len(toks) - size + 1):
                        ng = tuple(toks[i:i + size])
                        if ng in needed_ngrams:
                            matched.add(" ".join(ng))
                if not matched:
                    continue
                for m in matched:
                    self.tat_freq[m] += 1
                nw = len(toks)
                if nw < 5 or nw > 20 or "\n" in text or len(text) > 140:
                    continue
                has_vi = sid in eng2vie
                names = len(set(toks) & NAME_WORDS)
                bad = bool(set(toks) & PROFANITY)
                if bad:
                    continue
                # lower score = better
                score = (0 if has_vi else 10) + names * 3 + abs(nw - 10) * 0.3
                for m in matched:
                    lst = self.tat_hits[m]
                    if len(lst) < 12:
                        lst.append((score, sid))
                        self.tat_text[sid] = text
                    else:
                        worst = max(range(len(lst)), key=lambda i: lst[i][0])
                        if score < lst[worst][0]:
                            lst[worst] = (score, sid)
                            self.tat_text[sid] = text
        self.eng2vie = eng2vie
        print(f"tatoeba scanned {n} sentences, {len(self.tat_hits)} forms with examples ({time.time()-t:.0f}s)", flush=True)

    # ------------------------------------------------------------------ main build
    def build(self):
        self.load()
        # idiomatic multiword expressions indexed by each of their words; known English word forms
        self.idiom_index = collections.defaultdict(list)
        self.known_words = set()
        for word, ents in self.en.items():
            for e in ents:
                for f in e.get("forms") or []:
                    for tk in tokens(f.get("form") or ""):
                        self.known_words.add(tk)
            if " " not in word:
                self.known_words.update(tokens(word))
                continue
            toks = tokens(word)
            if not 2 <= len(toks) <= 5:
                continue
            # any multiword headword (compound, idiom, phrasal verb) blocks single-word examples that use it
            for tk in set(toks):
                self.idiom_index[tk].append(" ".join(toks))
        for w in ("a", "an", "the", "i", "to", "one's", "someone's", "something", "someone", "oneself", "sb", "sth"):
            self.known_words.add(w)
        topics = self.topics_cfg["topics"]
        self.topic_wikt = collections.defaultdict(set)
        self.seed_topics = collections.defaultdict(set)
        for tp in topics:
            for w in tp["wikt"]:
                self.topic_wikt[w.lower()].add(tp["code"])
            for s in tp["seeds"]:
                self.seed_topics[s.lower()].add(tp["code"])

        cands = collections.OrderedDict()  # key -> candidate dict

        def add_cand(c):
            key = c["key"]
            if key in cands:
                self.drop["duplicate_candidate"] += 1
                return
            cands[key] = c

        # A. CEFR-J + Octanove
        for r in self.cefr_rows:
            hw = r["variants"][0]
            add_cand({"key": f"{hw.lower()}|{r['pos']}", "headword": hw, "variants": r["variants"], "pos": r["pos"],
                      "entry_type": "word" if " " not in hw else "expression", "cefr": r["cefr"], "cefr_src": r["src"],
                      "lists": {r["src"]}})
        cefr_hw = {c["headword"].lower() for c in cands.values()}
        # B. NAWL words not covered by CEFR lists
        for w in self.nawl:
            if w.lower() in cefr_hw:
                for c in cands.values():
                    if c["headword"].lower() == w.lower():
                        c["lists"].add("nawl")
                continue
            ents = [e for e in self.en.get(w.lower(), []) if any(sense_ok(s) for s in e["senses"])]
            pos = None
            for e in ents:
                p = WIKT_POS.get(e["pos"])
                if p in ("noun", "verb", "adjective", "adverb"):
                    pos = p
                    break
            if not pos and w.lower() in self.nawl_defs:
                pos = {"n": "noun", "v": "verb", "adj": "adjective", "adv": "adverb"}.get(self.nawl_defs[w.lower()][1])
            if not pos:
                self.drop["nawl_no_pos"] += 1
                continue
            add_cand({"key": f"{w.lower()}|{pos}", "headword": w, "variants": [w], "pos": pos, "entry_type": "word",
                      "cefr": None, "cefr_src": None, "lists": {"nawl"}})

        # C. Phrasal verbs and D. idioms from English Wiktionary
        lex_verbs = {c["headword"].lower() for c in cands.values() if c["pos"] == "verb"}
        for word, ents in self.en.items():
            if " " not in word:
                continue
            toks = word.split()
            if any(t in PROFANITY for t in toks) or word in PROFANITY:
                continue
            if not re.fullmatch(r"[a-z][a-z' \-]*", word):
                continue
            for e in ents:
                if e["word"] != e["word"].lower():
                    continue
                good = [s for s in e["senses"] if sense_ok(s)]
                if not good:
                    continue
                cats = {c for s in e["senses"] for c in (s.get("categories") or [])}
                tags = {t for s in good for t in (s.get("tags") or [])}
                if any("phrasebook" in c.lower() for c in cats):
                    continue
                p = WIKT_POS.get(e["pos"])
                is_pv = (p == "verb" and 2 <= len(toks) <= 3 and toks[0] in lex_verbs and toks[-1] in PARTICLES)
                is_idiom = (not is_pv) and (("idiomatic" in tags) or ("English idioms" in cats) or p == "phrase") \
                    and 2 <= len(toks) <= 6 and toks[0] not in {"i", "i'm", "you", "he", "she", "we", "they", "it's"}
                if is_pv:
                    add_cand({"key": f"{word}|phrasal verb", "headword": word, "variants": [word], "pos": "phrasal verb",
                              "wikt_pos": "verb", "entry_type": "phrasal_verb", "cefr": None, "cefr_src": None,
                              "lists": {"enwikt"}, "needs_freq": 3})
                elif is_idiom:
                    add_cand({"key": f"{word}|idiom", "headword": word, "variants": [word], "pos": "idiom",
                              "wikt_pos": p, "entry_type": "idiom", "cefr": None, "cefr_src": None,
                              "lists": {"enwikt"}, "needs_freq": 3})

        # C2. curated common phrasal verbs (Vietnamese meaning written for this app)
        for pv in self.curated_pv:
            key = f"{pv.lower()}|phrasal verb"
            if key in cands:
                cands[key]["lists"].add("curated")
                continue
            add_cand({"key": key, "headword": pv, "variants": [pv], "pos": "phrasal verb", "wikt_pos": "verb",
                      "entry_type": "phrasal_verb", "cefr": None, "cefr_src": None, "lists": {"curated"}})

        # E. Curated expressions
        sections = {"writing_task1": 3, "writing_task2": 4, "speaking": 3, "collocations": 3, "listening": 2}
        self.curated_items = []
        for sec, diff in sections.items():
            for row in self.expr_cfg[sec]:
                hw, typ, vi, df, ex, exvi, tps, note = row
                self.curated_items.append({"section": sec, "headword": hw, "type": typ, "vi": vi, "def": df, "ex": ex,
                                           "exvi": exvi, "topics": tps, "note": note, "difficulty": diff})
        # F. frequent general words are added after Tatoeba frequencies are known (see below)

        # ---------------------------------------------------- Tatoeba scan
        needed_uni, needed_ng = set(), set()
        self.cand_forms = {}
        for key, c in cands.items():
            wpos = c.get("wikt_pos", c["pos"])
            _, ents = self.en_entries_for(c["variants"], wpos)
            c["_en"] = ents
            forms = set()
            for v in c["variants"]:
                forms |= self.forms_for(v, ents, wpos)
            if c["entry_type"] == "phrasal_verb":
                # inflect the verb part using the base verb's forms
                vtoks = c["headword"].split()
                base_ents = [e for e in self.en.get(vtoks[0], []) if e["pos"] == "verb"]
                vforms = self.forms_for(vtoks[0], base_ents, "verb")
                forms = {" ".join([vf] + vtoks[1:]) for vf in vforms if " " not in vf}
            self.cand_forms[key] = forms
        for it in self.curated_items:
            needed_ng.add(tuple(tokens(it["headword"]))) if len(tokens(it["headword"])) > 1 else needed_uni.add(it["headword"].lower())
        # general-word pool for section F: single words in en-wikt with vi translations or vi-wikt glosses
        self.pool = {}
        for word, ents in self.en.items():
            if " " in word or "-" in word or not re.fullmatch(r"[a-z]{3,}", word):
                continue
            if word in cefr_hw or word in self.nawl_set or word in PROFANITY:
                continue
            best_p, best_n = None, 0
            for e in ents:
                if e["word"] != word:
                    continue
                p = WIKT_POS.get(e["pos"])
                if p not in ("noun", "verb", "adjective", "adverb"):
                    continue
                n_good = sum(1 for s in e["senses"] if sense_ok(s)) + 3 * len(e.get("vi_translations") or [])
                if n_good > best_n:
                    best_p, best_n = p, n_good
            if best_p:
                self.pool[word] = best_p
        for word in self.pool:
            needed_uni.add(word)
        for key, forms in self.cand_forms.items():
            for f in forms:
                tt = tuple(tokens(f))
                if len(tt) == 1:
                    needed_uni.add(tt[0])
                elif len(tt) > 1:
                    needed_ng.add(tt)
        self.load_tatoeba(needed_uni, needed_ng)

        # F. frequent general words (corpus frequency >= 40 sentences in Tatoeba)
        added_f = 0
        for word, p in sorted(self.pool.items(), key=lambda kv: -self.tat_freq.get(kv[0], 0)):
            fq = self.tat_freq.get(word, 0)
            if fq < 40:
                break
            if self.tat_cap.get(word, 0) > 0.15 * fq:
                self.drop["frequency_word_mostly_capitalised"] += 1
                continue
            key = f"{word}|{p}"
            if key in cands:
                continue
            ents = [e for e in self.en.get(word, []) if WIKT_POS.get(e["pos"]) == p]
            # skip words whose good senses are all form-of (inflections such as "went")
            if all(not sense_ok(s) for e in ents for s in e["senses"]):
                continue
            # skip inflected forms that appear as a form of another lexicon headword
            add_cand({"key": key, "headword": word, "variants": [word], "pos": p, "entry_type": "word", "cefr": None,
                      "cefr_src": None, "lists": {"tatoeba-frequency"}, "_en": ents})
            self.cand_forms[key] = self.forms_for(word, ents, p)
            added_f += 1
        self.stats["candidates_frequency_words"] = added_f
        # drop F-words that are inflections of existing headwords (e.g. "books" when "book" exists)
        all_forms_owner = {}
        for key, c in cands.items():
            if "tatoeba-frequency" in c["lists"]:
                continue
            for f in self.cand_forms.get(key, ()):
                all_forms_owner.setdefault(f, key)
        for key in [k for k, c in cands.items() if "tatoeba-frequency" in c["lists"]]:
            if cands[key]["headword"] in all_forms_owner:
                del cands[key]
                self.drop["frequency_word_is_inflection"] += 1

        print(f"candidates: {len(cands)}", flush=True)
        self.cands = cands
        self.assemble()

    # ------------------------------------------------------------------ assemble rows
    def pick_examples(self, c, forms, en_ents, multi_pos):
        examples = []
        seen = set()
        hw = c["headword"].lower()

        def find_form(text):
            low = text.lower().replace("’", "'")
            best = None
            for f in sorted(forms, key=len, reverse=True):
                m = re.search(r"(?<![a-z])" + re.escape(f) + r"(?![a-z])", low)
                if m:
                    best = text[m.start():m.end()]
                    break
            return best

        # 1. Tatoeba sentences (with Vietnamese translation preferred)
        use_tatoeba = True
        if multi_pos and c["pos"] != c.get("_primary_pos"):
            use_tatoeba = False
        idioms_here = []
        fallback = []
        if " " not in hw:
            idioms_here = [p for p in self.idiom_index.get(hw, []) if p != hw]
        if use_tatoeba:
            hits = []
            for f in forms:
                hits.extend(self.tat_hits.get(f, []))
            hits.sort()
            for score, sid in hits:
                if sid in seen:
                    continue
                text = self.tat_text[sid]
                form = find_form(text)
                if not form:
                    continue
                low = " " + " ".join(tokens(text)) + " "
                if any(" " + p + " " in low for p in idioms_here):
                    # the word is used inside a fixed expression here ("brass tacks"), not in its own sense
                    fallback.append((text, sid, form))
                    continue
                seen.add(sid)
                examples.append({"en": text, "vi": self.eng2vie.get(sid), "form": form, "kind": "sentence",
                                 "source": "tatoeba", "ref": f"tatoeba:{sid}", "sense": None})
                if len(examples) >= 2:
                    break
        # 2. Wiktionary usage examples (sense-specific; core senses only)
        for si, s in enumerate(c.get("_good_senses", [])[:3]):
            if {x.lower() for x in (s.get("topics") or [])} & NICHE_TOPICS:
                continue
            for ex in s.get("examples") or []:
                if ex.get("type") != "example":
                    continue
                text = ex["text"].strip()
                if "\n" in text or len(text) > 160:
                    continue
                nw = len(text.split())
                if nw < 2:
                    continue
                form = find_form(text)
                if not form:
                    continue
                kind = "sentence" if nw >= 4 and re.search(r"[.!?]$", text) else "phrase"
                if text in seen:
                    continue
                seen.add(text)
                examples.append({"en": text, "vi": None, "form": form, "kind": kind, "source": "enwikt",
                                 "ref": s.get("id"), "sense": si})
            if sum(1 for e in examples if e["kind"] == "sentence") >= 4:
                break
        # 3. Vietnamese Wiktionary phrase examples with translations
        for ve in c.get("_vi", []):
            for s in ve.get("senses", []):
                for ex in s.get("examples") or []:
                    text = (ex.get("text") or "").strip()
                    tr = (ex.get("translation") or "").strip()
                    if not text or not tr or len(text) > 140 or text in seen:
                        continue
                    # reject phrases containing tokens that are not known English words (source typos)
                    if any(tk not in self.known_words for tk in tokens(text)):
                        self.drop["viwikt_example_unknown_token"] += 1
                        continue
                    form = find_form(text)
                    if not form:
                        continue
                    nw = len(text.split())
                    kind = "sentence" if nw >= 4 and re.search(r"[.!?]$", text) else "phrase"
                    seen.add(text)
                    examples.append({"en": text, "vi": tr, "form": form, "kind": kind, "source": "viwikt",
                                     "ref": None, "sense": None})
        sentences = [e for e in examples if e["kind"] == "sentence"]
        if not sentences and fallback:
            text, sid, form = fallback[0]
            sentences.append({"en": text, "vi": self.eng2vie.get(sid), "form": form, "kind": "sentence",
                              "source": "tatoeba", "ref": f"tatoeba:{sid}", "sense": None})
        phrases = [e for e in examples if e["kind"] == "phrase"]
        return sentences[:4], phrases[:6]

    def assemble(self):
        cands = self.cands
        # primary POS per headword: the CEFR row with lowest level, else first
        lvl = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
        by_hw = collections.defaultdict(list)
        for c in cands.values():
            by_hw[c["headword"].lower()].append(c)
        for hw, lst in by_hw.items():
            lst_sorted = sorted(lst, key=lambda c: (lvl.get(c.get("cefr") or "", 9), -sum(
                self.tat_freq.get(f, 0) for f in self.cand_forms.get(c["key"], ()))))
            for c in lst:
                c["_primary_pos"] = lst_sorted[0]["pos"]
                c["_multi_pos"] = len(lst) > 1

        entries = []
        for key, c in cands.items():
            wpos = c.get("wikt_pos", c["pos"])
            en_ents = c.get("_en")
            if en_ents is None:
                _, en_ents = self.en_entries_for(c["variants"], wpos)
            vi_ents = self.vi_entries_for(c["variants"], wpos)
            if c["entry_type"] in ("phrasal_verb", "idiom") and not vi_ents:
                vi_ents = [e for v in c["variants"] for e in self.vi.get(v.lower(), [])]
            c["_vi"] = vi_ents
            good = []
            tr_counts = collections.Counter()
            for e in en_ents:
                for s in expand_senses(e["senses"]):
                    if sense_ok(s):
                        good.append(s)
                for k, n in (e.get("tr_counts") or {}).items():
                    tr_counts[k] += n
            # keep distinct glosses
            seen_g, gs = set(), []
            for s in good:
                g = clean_gloss_en(s["glosses"][-1])
                if g.lower() in seen_g:
                    continue
                seen_g.add(g.lower())
                s = dict(s)
                s["_gloss"] = g
                gs.append(s)
                if len(gs) >= 12:
                    break
            # salience: a sense whose translation table has many translations (all languages) is a
            # core, widely-used meaning. Move the most salient sense to the front.
            if gs and tr_counts:
                def salience(s):
                    best = 0
                    for t, n in tr_counts.items():
                        if not t:
                            continue
                        j = jaccard(t, s["_gloss"])
                        if t.lower() in s["_gloss"].lower():
                            j = max(j, 0.6)
                        if j >= 0.34:
                            best = max(best, n)
                    tags = set(s.get("tags") or [])
                    if c["entry_type"] == "idiom" and tags & {"idiomatic", "figuratively"}:
                        best += 5
                    return best

                def has_vi_alignment(s):
                    for t in vi_sense_texts:
                        j = jaccard(t, s["_gloss"])
                        if t.lower() in s["_gloss"].lower():
                            j = max(j, 0.6)
                        if j >= 0.34:
                            return True
                    return False
                vi_sense_texts = [(t.get("sense") or "").strip() for e in en_ents
                                  for t in (e.get("vi_translations") or []) if (t.get("sense") or "").strip()]
                scored = []
                for i, s in enumerate(gs):
                    niche = bool({x.lower() for x in (s.get("topics") or [])} & NICHE_TOPICS)
                    # rank: senses with a Vietnamese translation first, then salience, then original order
                    scored.append((0 if niche else 1, 1 if has_vi_alignment(s) else 0, salience(s), -i, s))
                top = max(scored, key=lambda x: x[:4])
                if top[2] > 0 or top[1] > 0:
                    gs.remove(top[4])
                    gs.insert(0, top[4])
                # demote niche-topic senses to the end
                gs.sort(key=lambda s: 1 if {x.lower() for x in (s.get("topics") or [])} & NICHE_TOPICS else 0)
            gs = gs[:6]
            c["_good_senses"] = gs
            c["_tr_counts"] = tr_counts
            # ---- Vietnamese meanings
            tr_groups = collections.OrderedDict()
            for e in en_ents:
                for t in e.get("vi_translations") or []:
                    w = (t.get("word") or "").strip()
                    if not w or len(w) > 60 or set(t.get("tags") or []) & {"obsolete", "archaic"}:
                        continue
                    tr_groups.setdefault((t.get("sense") or "").strip(), [])
                    if w not in tr_groups[(t.get("sense") or "").strip()]:
                        tr_groups[(t.get("sense") or "").strip()].append(w)
            vi_gl = []
            for ve in vi_ents:
                for s in ve.get("senses", []):
                    for g in s.get("glosses") or []:
                        g = clean_vi_gloss(g)
                        if vi_gloss_ok(g, c["headword"]) and g not in vi_gl:
                            vi_gl.append(g)
            vi_gl.sort(key=lambda g: 1 if has_domain_label(g) else 0)  # general senses first (stable)
            # align translation groups to English senses
            sense_vi = {}
            for sense_txt, words in tr_groups.items():
                if not sense_txt:
                    continue
                best, bi = 0.0, None
                for i, s in enumerate(gs):
                    j = jaccard(sense_txt, s["_gloss"])
                    if sense_txt.lower() in s["_gloss"].lower():
                        j = max(j, 0.6)
                    if j > best:
                        best, bi = j, i
                if bi is not None and best >= 0.34 and bi not in sense_vi:
                    sense_vi[bi] = ", ".join(words[:3])
            primary_vi = None
            primary_vi_src = None
            if 0 in sense_vi:
                # Vietnamese translation aligned with the (most salient) primary English sense
                primary_vi, primary_vi_src = sense_vi[0], "enwikt"
            elif tr_groups:
                # otherwise the translation group with the most translations overall
                best = max(tr_groups.items(), key=lambda kv: tr_counts.get(kv[0], 0))
                primary_vi = ", ".join(best[1][:3])
                primary_vi_src = "enwikt"
            if (not primary_vi or len(primary_vi) < 2) and vi_gl:
                primary_vi = short_vi(vi_gl[0])
                primary_vi_src = "viwikt"
            c["_tr_groups"], c["_vi_gl"], c["_sense_vi"] = tr_groups, vi_gl, sense_vi
            c["_primary_vi"], c["_primary_vi_src"] = primary_vi, primary_vi_src
            # ---- English definition
            primary_def = gs[0]["_gloss"] if gs else None
            primary_def_src = "enwikt" if gs else None
            if not primary_def and c["headword"].lower() in self.nawl_defs:
                primary_def = self.nawl_defs[c["headword"].lower()][0]
                primary_def_src = "nawl"
            c["_primary_def"], c["_primary_def_src"] = primary_def, primary_def_src
            ov = self.vi_override.get(key.lower())
            if ov:
                c["_primary_vi"], c["_primary_vi_src"] = ov[0], "curated"
                c["_primary_def"], c["_primary_def_src"] = ov[1], "curated"
                c["lists"].add("curated")
            # ---- examples
            forms = self.cand_forms.get(key) or {c["headword"].lower()}
            sents, phrases = self.pick_examples(c, forms, en_ents, c.get("_multi_pos"))
            c["_examples"], c["_phrases"] = sents, phrases
            entries.append(c)

        # ---- merge curated expressions (either enrich existing entry or create a new one)
        by_hw = collections.defaultdict(list)
        for c in entries:
            by_hw[c["headword"].lower()].append(c)
        for it in self.curated_items:
            hw = it["headword"]
            existing = by_hw.get(hw.lower())
            ex = {"en": it["ex"], "vi": it["exvi"], "form": None, "kind": "sentence", "source": "curated", "ref": None,
                  "sense": None}
            if existing:
                tgt = existing[0]
                tgt.setdefault("_curated", []).append(it)
                tgt["_examples"] = [ex] + tgt["_examples"]
                continue
            typ = it["type"]
            pos = {"word": None, "phrasal verb": "phrasal verb", "idiom": "idiom", "collocation": "collocation",
                   "phrase": "expression", "expression": "expression"}[typ]
            if pos is None:
                # single word not in lexicon: take POS from Wiktionary
                ents = [e for e in self.en.get(hw.lower(), []) if any(sense_ok(s) for s in e["senses"])]
                pos = WIKT_POS.get(ents[0]["pos"]) if ents else "expression"
            c = {"key": f"{hw.lower()}|{pos}", "headword": hw, "variants": [hw], "pos": pos,
                 "entry_type": {"phrasal verb": "phrasal_verb", "idiom": "idiom", "collocation": "collocation"}.get(pos, "expression" if " " in hw else "word"),
                 "cefr": None, "cefr_src": None, "lists": {"curated"}, "_good_senses": [], "_tr_groups": {}, "_vi_gl": [],
                 "_sense_vi": {}, "_primary_vi": it["vi"], "_primary_vi_src": "curated", "_primary_def": it["def"],
                 "_primary_def_src": "curated", "_examples": [ex], "_phrases": [], "_curated": [it], "_en": [], "_vi": []}
            entries.append(c)
            by_hw[hw.lower()].append(c)
        # attach curated meaning/definition to existing entries lacking them
        for c in entries:
            for it in c.get("_curated", []):
                if not c["_primary_vi"]:
                    c["_primary_vi"], c["_primary_vi_src"] = it["vi"], "curated"
                if not c["_primary_def"]:
                    c["_primary_def"], c["_primary_def_src"] = it["def"], "curated"
        self.write(entries)

    # ------------------------------------------------------------------ write database
    def write(self, entries):
        if os.path.exists(self.out_db):
            os.remove(self.out_db)
        os.makedirs(os.path.dirname(self.out_db), exist_ok=True)
        db = sqlite3.connect(self.out_db)
        db.executescript(SCHEMA)
        src_id = {}
        for i, (code, name, url, lic, attr) in enumerate(SOURCES, 1):
            db.execute("INSERT INTO source_provenance(id,code,name,url,license,attribution) VALUES(?,?,?,?,?,?)",
                       (i, code, name, url, lic, attr))
            src_id[code] = i
        topic_id = {}
        order = 0
        for tp in self.topics_cfg["topics"]:
            order += 1
            db.execute("INSERT INTO topics(id,code,name_en,name_vi,category,icon,sort_order) VALUES(?,?,?,?,?,?,?)",
                       (order, tp["code"], tp["en"], tp["vi"], "ielts", tp["icon"], order))
            topic_id[tp["code"]] = order
        for g in self.topics_cfg["groups"]:
            order += 1
            db.execute("INSERT INTO topics(id,code,name_en,name_vi,category,icon,sort_order) VALUES(?,?,?,?,?,?,?)",
                       (order, g["code"], g["en"], g["vi"], g["category"], g["icon"], order))
            topic_id[g["code"]] = order

        usage_patterns = {k.lower(): v for k, v in self.usage_cfg["patterns"].items()}
        spelling = {k.lower(): v for k, v in self.usage_cfg["spelling"].items()}
        confusable_groups = self.usage_cfg["confusables"]
        conf_by_word = collections.defaultdict(list)
        for g in confusable_groups:
            for w in g["words"]:
                conf_by_word[w.lower()].append(g)

        # frequency rank over all entries
        def corpus_freq(c):
            return sum(self.tat_freq.get(f, 0) for f in self.cand_forms.get(c["key"], {c["headword"].lower()}))
        for c in entries:
            c["_freq"] = corpus_freq(c)
        ranked = sorted(entries, key=lambda c: -c["_freq"])
        for i, c in enumerate(ranked, 1):
            c["_freq_rank"] = i

        lex_index = collections.defaultdict(list)
        valid = []
        for c in entries:
            reasons = []
            if not c.get("_primary_vi"):
                reasons.append("no_vietnamese_meaning")
            if not c.get("_primary_def"):
                reasons.append("no_english_definition")
            if not c.get("_examples"):
                reasons.append("no_sentence_example")
            if c.get("needs_freq") and c["_freq"] < c["needs_freq"] and "curated" not in c["lists"]:
                reasons.append("too_rare_in_corpus")
            if reasons:
                for r in reasons:
                    self.drop[f"{c['entry_type']}:{r}"] += 1
                if len(self.drop_examples[reasons[0]]) < 40:
                    self.drop_examples[reasons[0]].append(c["headword"] + " (" + c["pos"] + ")")
                continue
            c["_id"] = stable_id(c["key"])
            valid.append(c)
            for v in c["variants"]:
                lex_index[v.lower()].append(c)

        ids = [c["_id"] for c in valid]
        assert len(ids) == len(set(ids)), "stable id collision"

        ex_id = sense_id = 0
        n_rows = collections.Counter()
        for c in valid:
            eid = c["_id"]
            hw = c["headword"]
            hwl = hw.lower()
            # pronunciation
            ipa_uk = ipa_us = None
            ipa_uk_src = ipa_us_src = None
            other = None
            for e in c.get("_en", []):
                for s in e.get("sounds") or []:
                    ipa = s.get("ipa")
                    if not ipa or not ipa.startswith(("/", "[")):
                        continue
                    tags = set(s.get("tags") or [])
                    if "dialectal" in tags:
                        continue
                    if not ipa_uk and tags & IPA_UK_TAGS:
                        ipa_uk, ipa_uk_src = ipa, "enwikt"
                    if not ipa_us and tags & IPA_US_TAGS:
                        ipa_us, ipa_us_src = ipa, "enwikt"
                    if not other and ipa.startswith("/"):
                        other = ipa
            if " " not in hw:
                if not ipa_uk and hwl in self.ipa["uk"]:
                    ipa_uk, ipa_uk_src = self.ipa["uk"][hwl], "ipadict"
                if not ipa_us and hwl in self.ipa["us"]:
                    ipa_us, ipa_us_src = self.ipa["us"][hwl], "ipadict"
            if not ipa_uk and not ipa_us and other:
                ipa_uk, ipa_uk_src = other, "enwikt"
            # register
            register = None
            if c["_good_senses"]:
                tags = set(c["_good_senses"][0].get("tags") or [])
                for r in REGISTER_TAGS:
                    if r in tags:
                        register = r
                        break
            # usage notes / mistakes
            notes = []
            for it in c.get("_curated", []):
                if it.get("note"):
                    notes.append(it["note"])
            if hwl in usage_patterns:
                notes.append("Cấu trúc: " + usage_patterns[hwl])
            for g in conf_by_word.get(hwl, []):
                notes.append("Dễ nhầm: " + " / ".join(g["words"]) + " – " + g["note_vi"])
            mistake = None
            if hwl in spelling:
                mistake = "Lỗi chính tả hay gặp: " + ", ".join(m + " ✗" for m in spelling[hwl]) + f" → {hw} ✓"
            # skills
            skills = set()
            if "nawl" in c["lists"]:
                skills |= {"reading", "writing"}
            for it in c.get("_curated", []):
                skills |= {"writing_task1": {"writing"}, "writing_task2": {"writing"}, "speaking": {"speaking"},
                           "collocations": {"writing", "speaking"}, "listening": {"listening"}}[it["section"]]
            # difficulty
            cefr = c.get("cefr")
            if cefr:
                difficulty = {"A1": 1, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}[cefr]
            elif c.get("_curated"):
                difficulty = max(it["difficulty"] for it in c["_curated"])
            else:
                pct = c["_freq_rank"] / len(entries)
                difficulty = 2 if pct < 0.25 else 3 if pct < 0.55 else 4 if pct < 0.8 else 5
            sources = set()
            if c["_primary_vi_src"]:
                sources.add(c["_primary_vi_src"])
            if c["_primary_def_src"]:
                sources.add(c["_primary_def_src"])
            for x in c["_examples"] + c["_phrases"]:
                sources.add(x["source"])
            for l in c["lists"]:
                if l in ("cefrj", "octanove", "nawl"):
                    sources.add(l)
            if c["entry_type"] in ("phrasal_verb", "idiom") and "curated" not in c["lists"]:
                sources.add("enwikt")
            if hwl in self.ngsl_rank:
                sources.add("ngsl")
            if ipa_uk_src:
                sources.add(ipa_uk_src)
            if ipa_us_src:
                sources.add(ipa_us_src)
            vi_all = [c["_primary_vi"]] + [", ".join(w) for w in c["_tr_groups"].values()] + c["_vi_gl"]
            vi_norm = strip_vi(" | ".join(vi_all))
            db.execute(
                """INSERT INTO vocabulary_entries(id,entry_key,headword,headword_norm,variants,pos,pos_vi,entry_type,cefr,
                cefr_source,difficulty,freq_rank,corpus_freq,ngsl_rank,ipa_uk,ipa_uk_source,ipa_us,ipa_us_source,primary_vi,
                primary_vi_source,primary_def,primary_def_source,vi_norm,register,skills,usage_note,common_mistake,
                is_academic,sources) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (eid, c["key"], hw, hwl, " / ".join(c["variants"]) if len(c["variants"]) > 1 else None, c["pos"],
                 POS_VI.get(c["pos"], c["pos"]), c["entry_type"], cefr, c.get("cefr_src"), difficulty,
                 c["_freq_rank"], c["_freq"], self.ngsl_rank.get(hwl), ipa_uk, ipa_uk_src, ipa_us, ipa_us_src,
                 c["_primary_vi"], c["_primary_vi_src"], c["_primary_def"], c["_primary_def_src"], vi_norm, register,
                 ",".join(sorted(skills)) or None, "\n".join(notes) or None, mistake,
                 1 if "nawl" in c["lists"] else 0, ",".join(sorted(sources))))
            n_rows["entries"] += 1
            # senses
            sense_ids = {}
            for i, s in enumerate(c["_good_senses"]):
                sense_id += 1
                sense_ids[i] = sense_id
                labels = [t for t in (s.get("tags") or []) if t in REGISTER_TAGS or t in ("transitive", "intransitive", "countable", "uncountable", "figuratively", "idiomatic")]
                labels += [t for t in (s.get("topics") or [])][:2]
                db.execute("INSERT INTO vocabulary_senses(id,entry_id,sense_no,definition_en,labels,meaning_vi,meaning_vi_source,source_id) VALUES(?,?,?,?,?,?,?,?)",
                           (sense_id, eid, i + 1, s["_gloss"], ", ".join(dict.fromkeys(labels)) or None,
                            c["_sense_vi"].get(i), "enwikt" if i in c["_sense_vi"] else None, src_id["enwikt"]))
                n_rows["senses"] += 1
            if not c["_good_senses"]:
                sense_id += 1
                db.execute("INSERT INTO vocabulary_senses(id,entry_id,sense_no,definition_en,labels,meaning_vi,meaning_vi_source,source_id) VALUES(?,?,?,?,?,?,?,?)",
                           (sense_id, eid, 1, c["_primary_def"], None, c["_primary_vi"], c["_primary_vi_src"],
                            src_id[c["_primary_def_src"]]))
                n_rows["senses"] += 1
            # translations (all Vietnamese meanings)
            ordn = 0
            seen_tr = set()
            for sense_txt, words in c["_tr_groups"].items():
                t = ", ".join(words[:4])
                if t in seen_tr:
                    continue
                seen_tr.add(t)
                ordn += 1
                db.execute("INSERT INTO translations(entry_id,ord,meaning_vi,context_en,source_id) VALUES(?,?,?,?,?)",
                           (eid, ordn, t, sense_txt or None, src_id["enwikt"]))
            for g in c["_vi_gl"][:8]:
                if g in seen_tr:
                    continue
                seen_tr.add(g)
                ordn += 1
                db.execute("INSERT INTO translations(entry_id,ord,meaning_vi,context_en,source_id) VALUES(?,?,?,?,?)",
                           (eid, ordn, g, None, src_id["viwikt"]))
            if c["_primary_vi_src"] == "curated" and c["_primary_vi"] not in seen_tr:
                ordn += 1
                db.execute("INSERT INTO translations(entry_id,ord,meaning_vi,context_en,source_id) VALUES(?,?,?,?,?)",
                           (eid, ordn, c["_primary_vi"], None, src_id["curated"]))
            n_rows["translations"] += ordn
            # examples
            for j, x in enumerate(c["_examples"][:4] + c["_phrases"][:4]):
                ex_id += 1
                db.execute("INSERT INTO examples(id,entry_id,sense_id,ord,text_en,text_vi,highlight,kind,source_id,source_ref) VALUES(?,?,?,?,?,?,?,?,?,?)",
                           (ex_id, eid, sense_ids.get(x["sense"]) if x["sense"] is not None else None, j + 1,
                            x["en"], x["vi"], x["form"], x["kind"], src_id[x["source"]], x["ref"]))
                n_rows["examples"] += 1
                if x["vi"]:
                    n_rows["examples_with_vi"] += 1
            # synonyms / antonyms
            rels = collections.OrderedDict()
            for s in c["_good_senses"][:4]:
                for kind in ("synonyms", "antonyms"):
                    for w in s.get(kind) or []:
                        rels.setdefault((kind[:-1], w), None)
            for e in c.get("_en", []):
                for kind in ("synonyms", "antonyms"):
                    for w in (e.get(kind) or [])[:10]:
                        rels.setdefault((kind[:-1], w), None)
            cnt = collections.Counter()
            for (kind, w) in rels:
                if not re.fullmatch(r"[A-Za-z][A-Za-z' \-]{0,30}", w) or w.lower() == hwl or w.lower() in PROFANITY:
                    continue
                if cnt[kind] >= 8:
                    continue
                cnt[kind] += 1
                tgt = lex_index.get(w.lower())
                db.execute("INSERT INTO lexical_relations(entry_id,relation,target_text,target_entry_id,source_id) VALUES(?,?,?,?,?)",
                           (eid, kind, w, tgt[0]["_id"] if tgt else None, src_id["enwikt"]))
                n_rows[kind] += 1
            # word family: other POS of same headword + derived/related single words present in lexicon
            fam = collections.OrderedDict()
            for o in lex_index.get(hwl, []):
                if o["_id"] != eid:
                    fam.setdefault(o["_id"], (o["headword"], o))
            for e in c.get("_en", []):
                for w in (e.get("derived") or []) + (e.get("related") or []):
                    if " " in w or w.lower() == hwl:
                        continue
                    for o in lex_index.get(w.lower(), [])[:1]:
                        fam.setdefault(o["_id"], (o["headword"], o))
            for tid, (w, o) in list(fam.items())[:10]:
                db.execute("INSERT INTO lexical_relations(entry_id,relation,target_text,target_entry_id,source_id) VALUES(?,?,?,?,?)",
                           (eid, "family", f"{w} ({POS_VI.get(o['pos'], o['pos'])})", tid, src_id["enwikt"]))
                n_rows["family"] += 1
            for g in conf_by_word.get(hwl, []):
                for w in g["words"]:
                    if w.lower() == hwl:
                        continue
                    tgt = lex_index.get(w.lower())
                    db.execute("INSERT INTO lexical_relations(entry_id,relation,target_text,target_entry_id,source_id) VALUES(?,?,?,?,?)",
                               (eid, "confusable", w, tgt[0]["_id"] if tgt else None, src_id["curated"]))
                    n_rows["confusable"] += 1
            # collocations
            colls = collections.OrderedDict()
            for x in c["_phrases"]:
                colls.setdefault(x["en"], (x["vi"], x["source"]))
            for e in c.get("_en", []):
                for w in e.get("derived") or []:
                    if " " not in w or hwl not in w.lower().split() or len(w) > 40:
                        continue
                    vg = None
                    for ve in self.vi.get(w.lower(), []):
                        for s in ve.get("senses", []):
                            for g in s.get("glosses") or []:
                                g = clean_vi_gloss(g)
                                if vi_gloss_ok(g, w):
                                    vg = short_vi(g)
                                    break
                            if vg:
                                break
                        if vg:
                            break
                    if vg:
                        colls.setdefault(w, (vg, "viwikt"))
            for (phrase, (vi, src)) in list(colls.items())[:8]:
                db.execute("INSERT INTO collocations(entry_id,phrase,meaning_vi,source_id) VALUES(?,?,?,?)",
                           (eid, phrase, vi, src_id[src]))
                n_rows["collocations"] += 1
            # topics
            tps = {}
            if hwl in self.seed_topics:
                for t in self.seed_topics[hwl]:
                    tps.setdefault(t, "curated")
            for s in c["_good_senses"][:3]:
                labels = [x.lower() for x in (s.get("topics") or [])] + [x.lower() for x in (s.get("categories") or [])]
                for lab in labels:
                    for t in self.topic_wikt.get(lab, ()):
                        tps.setdefault(t, "wiktionary")
            for it in c.get("_curated", []):
                for t in it["topics"]:
                    tps.setdefault(t, "curated")
                tps.setdefault(it["section"], "curated")
            if "nawl" in c["lists"]:
                tps.setdefault("academic", "list")
            if c["entry_type"] == "phrasal_verb":
                tps.setdefault("phrasal_verbs", "type")
            if c["entry_type"] == "idiom":
                tps.setdefault("idioms", "type")
            if c["entry_type"] == "collocation":
                tps.setdefault("collocations", "type")
            if hwl in conf_by_word:
                tps.setdefault("confusables", "curated")
            if not tps:
                tps["general"] = "default"
            for t, method in tps.items():
                if t not in topic_id:
                    raise SystemExit(f"unknown topic code {t} for {hw}")
                db.execute("INSERT INTO vocabulary_topics(entry_id,topic_id,method) VALUES(?,?,?)", (eid, topic_id[t], method))
                n_rows["topic_links"] += 1
            # search index
            defs = " ".join([c["_primary_def"]] + [s["_gloss"] for s in c["_good_senses"][1:4]])
            db.execute("INSERT INTO search_index(docid,headword,meaning,definition) VALUES(?,?,?,?)",
                       (eid, " ".join(v.lower() for v in c["variants"]), vi_norm, defs.lower()))

        # writing exercises
        for i, row in enumerate(self.writing_cfg["items"], 1):
            cat, prompt, opts, ans, expl = row
            assert 0 <= ans < len(opts), prompt
            db.execute("INSERT INTO writing_exercises(id,category,prompt,options_json,answer_index,explanation_vi,source_id) VALUES(?,?,?,?,?,?,?)",
                       (i, cat, prompt, json.dumps(opts, ensure_ascii=False), ans, expl, src_id["curated"]))
        # speaking packs
        for i, p in enumerate(self.speaking_cfg["packs"], 1):
            vocab_ids = []
            for w in p["vocab"]:
                tgt = lex_index.get(w.lower())
                vocab_ids.append({"text": w, "entry_id": tgt[0]["_id"] if tgt else None,
                                  "vi": tgt[0]["_primary_vi"] if tgt else None})
            db.execute("INSERT INTO speaking_packs(id,code,part,title,title_vi,topic_code,questions_json,vocab_json,sample_answer,tips_vi) VALUES(?,?,?,?,?,?,?,?,?,?)",
                       (i, p["code"], p["part"], p["title"], p["title_vi"], p["topic"],
                        json.dumps(p["questions"], ensure_ascii=False), json.dumps(vocab_ids, ensure_ascii=False),
                        p["sample"], p["tips_vi"]))
        db.execute("INSERT INTO meta(key,value) VALUES('self_practice',?)",
                   (json.dumps(self.speaking_cfg["self_practice"], ensure_ascii=False),))
        db.execute("INSERT INTO meta(key,value) VALUES('content_version',?)", (str(CONTENT_VERSION),))
        db.execute("INSERT INTO meta(key,value) VALUES('built_at',?)", (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),))
        db.execute("INSERT INTO meta(key,value) VALUES('entry_count',?)", (str(len(valid)),))
        db.execute("INSERT INTO search_index(search_index) VALUES('optimize')")
        db.commit()
        fk = db.execute("PRAGMA foreign_key_check").fetchall()
        if fk:
            raise SystemExit(f"foreign key violations: {fk[:10]}")
        db.execute("ANALYZE")
        db.commit()
        db.execute("VACUUM")
        db.close()
        self.stats.update(n_rows)
        self.stats["valid_entries"] = len(valid)
        self.stats["candidate_entries"] = len(entries)
        stats = {"counts": dict(self.stats), "dropped": dict(self.drop),
                 "drop_examples": {k: v for k, v in self.drop_examples.items()}}
        os.makedirs(os.path.dirname(self.stats_path), exist_ok=True)
        with open(self.stats_path, "w", encoding="utf-8") as f:
            json.dump(stats, f, ensure_ascii=False, indent=2)
        print(json.dumps(stats["counts"], indent=1))
        print("dropped:", json.dumps(stats["dropped"], indent=1))


SCHEMA = """
PRAGMA foreign_keys = OFF;
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE source_provenance(
  id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, url TEXT NOT NULL,
  license TEXT NOT NULL, attribution TEXT NOT NULL, notes TEXT);
CREATE TABLE topics(
  id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_en TEXT NOT NULL, name_vi TEXT NOT NULL,
  category TEXT NOT NULL, icon TEXT, sort_order INTEGER NOT NULL);
CREATE TABLE vocabulary_entries(
  id INTEGER PRIMARY KEY,
  entry_key TEXT NOT NULL UNIQUE,
  headword TEXT NOT NULL,
  headword_norm TEXT NOT NULL,
  variants TEXT,
  pos TEXT NOT NULL,
  pos_vi TEXT NOT NULL,
  entry_type TEXT NOT NULL,
  cefr TEXT, cefr_source TEXT,
  difficulty INTEGER NOT NULL CHECK(difficulty BETWEEN 1 AND 5),
  freq_rank INTEGER, corpus_freq INTEGER, ngsl_rank INTEGER,
  ipa_uk TEXT, ipa_uk_source TEXT, ipa_us TEXT, ipa_us_source TEXT,
  primary_vi TEXT NOT NULL, primary_vi_source TEXT NOT NULL,
  primary_def TEXT NOT NULL, primary_def_source TEXT NOT NULL,
  vi_norm TEXT NOT NULL,
  register TEXT, skills TEXT, usage_note TEXT, common_mistake TEXT,
  is_academic INTEGER NOT NULL DEFAULT 0,
  sources TEXT NOT NULL);
CREATE INDEX idx_entries_headword ON vocabulary_entries(headword_norm);
CREATE INDEX idx_entries_cefr ON vocabulary_entries(cefr);
CREATE INDEX idx_entries_pos ON vocabulary_entries(pos);
CREATE INDEX idx_entries_difficulty ON vocabulary_entries(difficulty, freq_rank);
CREATE INDEX idx_entries_freq ON vocabulary_entries(freq_rank);
CREATE TABLE vocabulary_senses(
  id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  sense_no INTEGER NOT NULL, definition_en TEXT NOT NULL, labels TEXT, meaning_vi TEXT, meaning_vi_source TEXT,
  source_id INTEGER NOT NULL REFERENCES source_provenance(id));
CREATE INDEX idx_senses_entry ON vocabulary_senses(entry_id);
CREATE TABLE translations(
  id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  ord INTEGER NOT NULL, meaning_vi TEXT NOT NULL, context_en TEXT,
  source_id INTEGER NOT NULL REFERENCES source_provenance(id));
CREATE INDEX idx_translations_entry ON translations(entry_id);
CREATE TABLE examples(
  id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  sense_id INTEGER REFERENCES vocabulary_senses(id), ord INTEGER NOT NULL,
  text_en TEXT NOT NULL, text_vi TEXT, highlight TEXT, kind TEXT NOT NULL,
  source_id INTEGER NOT NULL REFERENCES source_provenance(id), source_ref TEXT);
CREATE INDEX idx_examples_entry ON examples(entry_id);
CREATE TABLE collocations(
  id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  phrase TEXT NOT NULL, meaning_vi TEXT, source_id INTEGER NOT NULL REFERENCES source_provenance(id));
CREATE INDEX idx_collocations_entry ON collocations(entry_id);
CREATE TABLE lexical_relations(
  id INTEGER PRIMARY KEY, entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  relation TEXT NOT NULL CHECK(relation IN ('synonym','antonym','family','confusable')),
  target_text TEXT NOT NULL, target_entry_id INTEGER REFERENCES vocabulary_entries(id),
  source_id INTEGER NOT NULL REFERENCES source_provenance(id));
CREATE INDEX idx_relations_entry ON lexical_relations(entry_id, relation);
CREATE TABLE vocabulary_topics(
  entry_id INTEGER NOT NULL REFERENCES vocabulary_entries(id) ON DELETE CASCADE,
  topic_id INTEGER NOT NULL REFERENCES topics(id), method TEXT NOT NULL,
  PRIMARY KEY(entry_id, topic_id));
CREATE INDEX idx_vtopics_topic ON vocabulary_topics(topic_id);
CREATE VIRTUAL TABLE search_index USING fts4(headword, meaning, definition);
CREATE TABLE writing_exercises(
  id INTEGER PRIMARY KEY, category TEXT NOT NULL, prompt TEXT NOT NULL, options_json TEXT NOT NULL,
  answer_index INTEGER NOT NULL, explanation_vi TEXT NOT NULL, source_id INTEGER NOT NULL REFERENCES source_provenance(id));
CREATE TABLE speaking_packs(
  id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, part INTEGER NOT NULL, title TEXT NOT NULL, title_vi TEXT NOT NULL,
  topic_code TEXT, questions_json TEXT NOT NULL, vocab_json TEXT NOT NULL, sample_answer TEXT, tips_vi TEXT);
"""

if __name__ == "__main__":
    raw, work, curated, out_db, stats = sys.argv[1:6]
    Builder(raw, work, curated, out_db, stats).build()

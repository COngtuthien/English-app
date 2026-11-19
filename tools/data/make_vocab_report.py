"""Renders release/VOCABULARY_REPORT.md from tools/data/out/validation.json and build_stats.json.
Usage: python -I tools/data/make_vocab_report.py tools/data/out/validation.json tools/data/out/build_stats.json release/VOCABULARY_REPORT.md
"""
import json
import sys


def table(d, h1="Value", h2="Count"):
    rows = [f"| {h1} | {h2} |", "|---|---:|"]
    rows += [f"| {k} | {v:,} |" for k, v in d.items()]
    return "\n".join(rows)


def main():
    val = json.load(open(sys.argv[1], encoding="utf-8"))
    build = json.load(open(sys.argv[2], encoding="utf-8"))
    s = val["stats"]
    t = s["total_entries"]
    pct = lambda n: f"{n:,} ({n * 100 / t:.1f}%)"
    ielts_topics = {k: v for k, v in s["by_topic"].items() if not k.split(" ")[0] in
                    ("general", "academic", "writing_task1", "writing_task2", "speaking", "listening", "phrasal_verbs",
                     "idioms", "collocations", "confusables")}
    groups = {k: v for k, v in s["by_topic"].items() if k not in ielts_topics}
    dropped = build.get("dropped", {})
    out = f"""# Vocabulary database report

Generated from `assets/db/vocab.db` (content version {s['meta'].get('content_version')}, built {s['meta'].get('built_at')})
by `tools/data/validate_database.py` and `tools/data/make_vocab_report.py`.

## Result
**Validation: {'PASSED' if val['ok'] else 'FAILED'}** – {len(val['errors'])} errors.

**Validated unique lexical entries: {t:,}** (unique `headword + part of speech`; topic links are not counted as entries).
The ≥ 10,000 target is {'met' if t >= 10000 else 'NOT met'}.

Minimum quality bar enforced for *every* entry (entries failing it were dropped, not padded):
headword · part of speech/expression type · Vietnamese meaning · English definition · ≥ 1 English example
sentence · ≥ 1 topic association · difficulty (1–5) · source provenance.

## Coverage
| Field | Entries |
|---|---:|
| Vietnamese meaning | {pct(s['with_vietnamese_meaning'])} |
| English definition | {pct(s['with_english_definition'])} |
| ≥ 1 example sentence | {pct(s['with_sentence_example'])} |
| Example sentence with Vietnamese translation (Tatoeba human translations, Vietnamese Wiktionary, curated) | {pct(s['with_vietnamese_example_translation'])} |
| IPA (UK or US) | {pct(s['with_any_ipa'])} |
| British IPA | {pct(s['with_ipa_uk'])} |
| American IPA | {pct(s['with_ipa_us'])} |
| Collocations / fixed phrases | {pct(s['with_collocations'])} |
| Synonyms | {pct(s['with_synonyms'])} |
| Antonyms | {pct(s['with_antonyms'])} |
| Word family links | {pct(s['with_word_family'])} |
| Multiple separate senses | {pct(s['multi_sense_entries'])} |
| Usage notes (curated) | {pct(s['with_usage_note'])} |
| Common spelling mistakes (curated) | {pct(s['with_common_mistake'])} |
| Academic (NAWL) | {pct(s['academic_nawl_entries'])} |

IPA sources – UK: {s['ipa_uk_by_source']}; US: {s['ipa_us_by_source']}
(`enwikt` = accent-tagged Wiktionary IPA, `ipadict` = ipa-dict MIT dataset; ipa-dict is word-level and does not
distinguish homographs such as *record* n./v.).

Row totals: {', '.join(f'{k} {v:,}' for k, v in s['rows'].items())}.

## CEFR levels
CEFR is shown only where it comes from CEFR-J (A1–B2) or the Octanove C1/C2 profile. Other entries carry an
**estimated difficulty** (1–5) derived from corpus frequency and are labelled "not rated" for CEFR.

{table(s['by_cefr'], 'CEFR', 'Entries')}

{table(s['by_difficulty'], 'Difficulty (1 easy – 5 hard)', 'Entries')}

## Entry types and parts of speech
{table(s['by_entry_type'], 'Type', 'Entries')}

{table(s['by_pos'], 'POS', 'Entries')}

## Provenance of the primary meaning / definition / examples
{table(s['vietnamese_meaning_source'], 'Primary Vietnamese meaning source', 'Entries')}

{table(s['definition_source'], 'Primary English definition source', 'Entries')}

{table(s['example_sources'], 'Example source', 'Examples')}

`curated` Vietnamese meanings (≈{s['vietnamese_meaning_source'].get('curated', 0):,}) are editorial: IELTS expressions written for the app,
common phrasal verbs missing from the open data, and high-value IELTS words whose first open-source gloss was archaic or the wrong sense
(e.g. *battery* "khẩu đội pháo" → "pin, ắc quy"; *cell* "phòng giam" → "tế bào; phòng giam"). All other meanings are copied from Wiktionary.

## Topics (50 IELTS topics)
Topic links come from curated seed lists (`curated`), Wiktionary sense topics/categories (`wiktionary`), list membership (`list`, NAWL → Academic),
entry type (`type`) or the fallback "General English" group (`default`): {s['topic_assignment_method']}.
Wiktionary-derived topic links are broad (e.g. many mathematics/physics terms fall under *Science*).

{table(ielts_topics, 'IELTS topic', 'Entries')}

{table(groups, 'Skill / group', 'Entries')}

## Dropped candidates (did not meet the quality bar)
{table(dropped, 'Reason', 'Candidates')}

## Known limitations
* Vietnamese meanings from Vietnamese Wiktionary (largely derived from the Free Vietnamese Dictionary Project) are sometimes
  old-fashioned or list a rare sense first; senses from English Wiktionary translation tables are aligned to English senses
  automatically (token overlap), which can occasionally mis-align.
* Only {pct(s['with_vietnamese_example_translation'])} entries have a Vietnamese translation of an example sentence;
  the rest have English-only examples (no machine translation was used).
* Some example sentences come from Wiktionary usage examples or Tatoeba and may use a different sense of the word than the primary meaning.
* Phrasal verbs ({s['by_entry_type'].get('phrasal_verb', 0)}) and idioms ({s['by_entry_type'].get('idiom', 0)}) are limited to those with a
  Vietnamese meaning, an example and corpus frequency ≥ 3.
* IELTS topic coverage is uneven: some topics (e.g. Globalization, Migration, Population) have fewer than 30 entries.
"""
    with open(sys.argv[3], "w", encoding="utf-8") as f:
        f.write(out)
    print("written", sys.argv[3])


if __name__ == "__main__":
    main()

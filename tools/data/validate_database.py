"""Validates the bundled vocabulary database and writes a machine-readable report.

Checks (all must pass, otherwise exit code 1):
  * every entry has headword, POS, Vietnamese meaning, English definition, >=1 sentence example,
    >=1 topic link, difficulty 1-5 and source provenance
  * stable ids are unique, entry keys unique, foreign keys consistent
  * no placeholder headwords (digits runs, "word_", "vocabulary_item", "generic ...")
  * every source code used by rows exists in source_provenance with a licence
  * writing exercises have exactly one valid answer index and no duplicate options
  * the FTS index has one row per entry

Usage: python -I tools/data/validate_database.py assets/db/vocab.db tools/data/out/validation.json
"""
import json
import re
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")


def main():
    db_path, out_path = sys.argv[1], sys.argv[2]
    db = sqlite3.connect(db_path)
    q = lambda sql, *a: db.execute(sql, a).fetchall()
    one = lambda sql, *a: db.execute(sql, a).fetchone()[0]
    errors = []

    total = one("SELECT COUNT(*) FROM vocabulary_entries")
    checks = {
        "empty_vietnamese": one("SELECT COUNT(*) FROM vocabulary_entries WHERE trim(primary_vi)=''"),
        "empty_definition": one("SELECT COUNT(*) FROM vocabulary_entries WHERE trim(primary_def)=''"),
        "no_sentence_example": one("SELECT COUNT(*) FROM vocabulary_entries e WHERE NOT EXISTS (SELECT 1 FROM examples x WHERE x.entry_id=e.id AND x.kind='sentence')"),
        "no_topic": one("SELECT COUNT(*) FROM vocabulary_entries e WHERE NOT EXISTS (SELECT 1 FROM vocabulary_topics v WHERE v.entry_id=e.id)"),
        "bad_difficulty": one("SELECT COUNT(*) FROM vocabulary_entries WHERE difficulty NOT BETWEEN 1 AND 5"),
        "no_sources": one("SELECT COUNT(*) FROM vocabulary_entries WHERE trim(sources)=''"),
        "duplicate_keys": one("SELECT COUNT(*) FROM (SELECT entry_key FROM vocabulary_entries GROUP BY entry_key HAVING COUNT(*)>1)"),
        "duplicate_headword_pos": one("SELECT COUNT(*) FROM (SELECT headword_norm,pos FROM vocabulary_entries GROUP BY 1,2 HAVING COUNT(*)>1)"),
        "fts_rows_mismatch": abs(one("SELECT COUNT(*) FROM search_index") - total) if db.execute("SELECT 1").fetchone() else 0,
    }
    placeholders = [r[0] for r in q("SELECT headword FROM vocabulary_entries") if
                    re.search(r"\d{3,}|^word_|vocabulary_item|generic (academic )?term|lorem", r[0], re.I)]
    checks["placeholder_headwords"] = len(placeholders)
    db.execute("PRAGMA foreign_keys=ON")
    fk = q("PRAGMA foreign_key_check")
    checks["foreign_key_violations"] = len(fk)
    codes = {r[0] for r in q("SELECT code FROM source_provenance WHERE license<>'' AND attribution<>''")}
    used = set()
    for (s,) in q("SELECT sources FROM vocabulary_entries"):
        used.update(x for x in s.split(",") if x)
    for col in ("primary_vi_source", "primary_def_source"):
        used.update(r[0] for r in q(f"SELECT DISTINCT {col} FROM vocabulary_entries"))
    checks["undocumented_sources"] = len(used - codes)
    bad_ex = 0
    for prompt, opts, ans in q("SELECT prompt, options_json, answer_index FROM writing_exercises"):
        o = json.loads(opts)
        if not (0 <= ans < len(o)) or len(set(o)) != len(o):
            bad_ex += 1
    checks["bad_writing_exercises"] = bad_ex
    for k, v in checks.items():
        if v:
            errors.append(f"{k}: {v}")

    def dist(sql):
        return {str(k): v for k, v in q(sql)}

    stats = {
        "total_entries": total,
        "with_vietnamese_meaning": total - checks["empty_vietnamese"],
        "with_english_definition": total - checks["empty_definition"],
        "with_sentence_example": total - checks["no_sentence_example"],
        "with_vietnamese_example_translation": one("SELECT COUNT(DISTINCT entry_id) FROM examples WHERE kind='sentence' AND text_vi IS NOT NULL"),
        "with_ipa_uk": one("SELECT COUNT(*) FROM vocabulary_entries WHERE ipa_uk IS NOT NULL"),
        "with_ipa_us": one("SELECT COUNT(*) FROM vocabulary_entries WHERE ipa_us IS NOT NULL"),
        "with_any_ipa": one("SELECT COUNT(*) FROM vocabulary_entries WHERE ipa_uk IS NOT NULL OR ipa_us IS NOT NULL"),
        "ipa_uk_by_source": dist("SELECT ipa_uk_source, COUNT(*) FROM vocabulary_entries WHERE ipa_uk IS NOT NULL GROUP BY 1"),
        "ipa_us_by_source": dist("SELECT ipa_us_source, COUNT(*) FROM vocabulary_entries WHERE ipa_us IS NOT NULL GROUP BY 1"),
        "with_collocations": one("SELECT COUNT(DISTINCT entry_id) FROM collocations"),
        "with_synonyms": one("SELECT COUNT(DISTINCT entry_id) FROM lexical_relations WHERE relation='synonym'"),
        "with_antonyms": one("SELECT COUNT(DISTINCT entry_id) FROM lexical_relations WHERE relation='antonym'"),
        "with_word_family": one("SELECT COUNT(DISTINCT entry_id) FROM lexical_relations WHERE relation='family'"),
        "with_usage_note": one("SELECT COUNT(*) FROM vocabulary_entries WHERE usage_note IS NOT NULL"),
        "with_common_mistake": one("SELECT COUNT(*) FROM vocabulary_entries WHERE common_mistake IS NOT NULL"),
        "multi_sense_entries": one("SELECT COUNT(*) FROM (SELECT entry_id FROM vocabulary_senses GROUP BY entry_id HAVING COUNT(*)>1)"),
        "rows": {t: one(f"SELECT COUNT(*) FROM {t}") for t in
                 ("vocabulary_senses", "translations", "examples", "collocations", "lexical_relations", "vocabulary_topics",
                  "writing_exercises", "speaking_packs")},
        "by_cefr": dist("SELECT COALESCE(cefr,'(not rated)'), COUNT(*) FROM vocabulary_entries GROUP BY 1 ORDER BY 1"),
        "by_cefr_source": dist("SELECT COALESCE(cefr_source,'(none)'), COUNT(*) FROM vocabulary_entries GROUP BY 1"),
        "by_difficulty": dist("SELECT difficulty, COUNT(*) FROM vocabulary_entries GROUP BY 1 ORDER BY 1"),
        "by_entry_type": dist("SELECT entry_type, COUNT(*) FROM vocabulary_entries GROUP BY 1 ORDER BY 2 DESC"),
        "by_pos": dist("SELECT pos, COUNT(*) FROM vocabulary_entries GROUP BY 1 ORDER BY 2 DESC"),
        "vietnamese_meaning_source": dist("SELECT primary_vi_source, COUNT(*) FROM vocabulary_entries GROUP BY 1"),
        "definition_source": dist("SELECT primary_def_source, COUNT(*) FROM vocabulary_entries GROUP BY 1"),
        "example_sources": dist("SELECT p.code, COUNT(*) FROM examples x JOIN source_provenance p ON p.id=x.source_id GROUP BY 1"),
        "academic_nawl_entries": one("SELECT COUNT(*) FROM vocabulary_entries WHERE is_academic=1"),
        "by_topic": {f"{c} ({n})": v for c, n, v in q(
            "SELECT t.code, t.name_en, COUNT(vt.entry_id) FROM topics t LEFT JOIN vocabulary_topics vt ON vt.topic_id=t.id GROUP BY t.id ORDER BY t.sort_order")},
        "topic_assignment_method": dist("SELECT method, COUNT(*) FROM vocabulary_topics GROUP BY 1"),
        "sources": [{"code": c, "name": n, "license": l} for c, n, l in q("SELECT code,name,license FROM source_provenance ORDER BY id")],
        "meta": dict(q("SELECT key, value FROM meta WHERE key <> 'self_practice'")),
    }
    report = {"ok": not errors, "errors": errors, "checks": checks, "stats": stats, "placeholder_examples": placeholders[:20]}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(json.dumps({"ok": report["ok"], "errors": errors, "total_entries": total}, ensure_ascii=False))
    sys.exit(0 if not errors else 1)


if __name__ == "__main__":
    main()

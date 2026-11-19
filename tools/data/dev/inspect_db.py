"""Developer QA helper: print samples and distributions from the built content DB.
Usage: python -I tools/data/dev/inspect_db.py assets/db/vocab.db [headword ...]"""
import sqlite3
import sys

sys.stdout.reconfigure(encoding="utf-8")
db = sqlite3.connect(sys.argv[1])
q = lambda s, *a: db.execute(s, a).fetchall()
words = sys.argv[2:]
if not words:
    print("by type", q("select entry_type,count(*) from vocabulary_entries group by 1"))
    print("by cefr", q("select cefr,count(*) from vocabulary_entries group by 1"))
    print("by pos", q("select pos,count(*) from vocabulary_entries group by 1 order by 2 desc"))
    print("vi src", q("select primary_vi_source,count(*) from vocabulary_entries group by 1"))
    print("def src", q("select primary_def_source,count(*) from vocabulary_entries group by 1"))
    print("ipa uk", q("select ipa_uk_source,count(*) from vocabulary_entries group by 1"))
    print("ipa us", q("select ipa_us_source,count(*) from vocabulary_entries group by 1"))
    print("topics", q("select t.code,count(*) from vocabulary_topics vt join topics t on t.id=vt.topic_id group by 1 order by 2 desc"))
    print("random sample:")
    for r in q("select headword,pos,cefr,primary_vi,primary_def from vocabulary_entries order by random() limit 60"):
        print("  ", r)
    print("frequency-list sample:")
    for r in q("select headword,pos,primary_vi,primary_def from vocabulary_entries where cefr is null and entry_type='word' order by random() limit 40"):
        print("  ", r)
    print("idioms/phrasal:")
    for r in q("select headword,pos,primary_vi,primary_def from vocabulary_entries where entry_type in ('idiom','phrasal_verb') order by random() limit 40"):
        print("  ", r)
else:
    for w in words:
        for (eid, hw, pos, cefr, vi, vsrc, df, uk, us) in q("select id,headword,pos,cefr,primary_vi,primary_vi_source,primary_def,ipa_uk,ipa_us from vocabulary_entries where headword_norm=?", w.lower()):
            print(f"== {hw} ({pos}) {cefr} uk={uk} us={us}\n   VI[{vsrc}]: {vi}\n   DEF: {df}")
            for r in q("select sense_no,definition_en,meaning_vi,labels from vocabulary_senses where entry_id=?", eid):
                print("   S", r)
            for r in q("select meaning_vi,context_en from translations where entry_id=? order by ord", eid):
                print("   T", r)
            for r in q("select kind,text_en,text_vi,highlight from examples where entry_id=? order by ord", eid):
                print("   E", r)
            for r in q("select phrase,meaning_vi from collocations where entry_id=?", eid):
                print("   C", r)
            for r in q("select relation,target_text from lexical_relations where entry_id=?", eid):
                print("   R", r)
            print("   TOPICS", q("select t.code,vt.method from vocabulary_topics vt join topics t on t.id=vt.topic_id where entry_id=?", eid))

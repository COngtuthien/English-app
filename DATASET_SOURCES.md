# Dataset sources & licensing

All vocabulary content in `assets/db/vocab.db` is built by `tools/data/build_database.py` from the
sources below. Every row in the database records its source (`source_provenance` table; `source_id`
columns; `vocabulary_entries.sources`). Nothing is fetched at runtime – the APK contains the finished
database and the app has no INTERNET permission.

| Code | Source | URL | Licence | Used for | Redistribution |
|---|---|---|---|---|---|
| `enwikt` | English Wiktionary, extracted by Wiktextract (kaikki.org) | https://kaikki.org/dictionary/English/ | CC BY-SA 4.0 (+GFDL) | English definitions (senses), usage examples, IPA (UK/US), synonyms, antonyms, derived/related terms, Vietnamese translation-table entries, topic tags | Allowed with attribution + share-alike |
| `viwikt` | Vietnamese Wiktionary, extracted by Wiktextract (kaikki.org) | https://kaikki.org/viwiktionary/ | CC BY-SA 4.0 (+GFDL) | Vietnamese glosses of English entries, phrase examples with Vietnamese translations, collocations | Allowed with attribution + share-alike |
| `tatoeba` | Tatoeba sentence corpus (eng, vie, eng–vie links) | https://tatoeba.org/ – downloads.tatoeba.org/exports/per_language | CC BY 2.0 FR | Natural example sentences and human Vietnamese translations; corpus frequency | Allowed with attribution (sentence ids stored as `tatoeba:<id>`) |
| `cefrj` | CEFR-J Wordlist v1.5 (Tono Laboratory, TUFS) via Open Language Profiles | https://github.com/openlanguageprofiles/olp-en-cefrj | "Free for research and commercial use, provided that you cite the dataset" | Headword list + CEFR levels A1–B2 | Allowed with citation |
| `octanove` | Octanove Vocabulary Profile C1/C2 v1.0 | https://github.com/openlanguageprofiles/olp-en-cefrj | CC BY-SA 4.0 | Headword list + CEFR levels C1–C2 | Allowed with attribution + share-alike |
| `nawl` | New Academic Word List 1.2 (Browne, Culligan & Phillips) | https://www.newgeneralservicelist.com/new-academic-word-list | CC BY-SA 4.0 | Academic headwords; 4 fallback definitions | Allowed with attribution + share-alike |
| `ngsl` | New General Service List 1.2 | https://www.newgeneralservicelist.com/new-general-service-list | CC BY-SA 4.0 | Frequency rank metadata | Allowed with attribution + share-alike |
| `ipadict` | ipa-dict en_UK / en_US (open-dict-data) | https://github.com/open-dict-data/ipa-dict | MIT | IPA where Wiktionary has no accent-tagged IPA | Allowed (MIT notice reproduced in About screen) |
| `curated` | IELTS Vocabulary Master editorial content | this repository (`tools/data/curated/`) | CC BY-SA 4.0 | IELTS Writing Task 1/2 & Speaking expressions, collocations, listening phrases, example sentences + Vietnamese translations, curated Vietnamese meanings for common phrasal verbs and ~280 key IELTS words, confusable-word notes, spelling mistakes, grammar patterns, 141 writing exercises, 24 speaking packs, 50-topic taxonomy | Original work |

Required citations:
* Ylonen, T. (2022). *Wiktextract: Wiktionary as Machine-Readable Structured Data.* LREC 2022.
* The CEFR-J Wordlist Version 1.5. Compiled by Yukio Tono, Tokyo University of Foreign Studies.
* Octanove Vocabulary Profile C1/C2 (ver 1.0), Octanove Labs.
* Browne, C., Culligan, B. & Phillips, J. The New General Service List 1.2 / The New Academic Word List 1.2.
* Tatoeba (https://tatoeba.org), sentences by Tatoeba contributors.

Because CC BY-SA material is included, the vocabulary database as a whole is distributed under
**CC BY-SA 4.0**; the app's About screen shows every source, licence and attribution.

## What was *not* used
* No commercial dictionary content (Oxford, Cambridge, Longman, Collins, etc.) and no Oxford 3000/5000 lists.
* No machine translation and no AI-generated definitions or translations.
* The Free Vietnamese Dictionary Project files (GPL) were not imported directly; Vietnamese
  Wiktionary content (which incorporates FVDP material under its CC BY-SA/GFDL licence) was used instead.

## Download dates
All sources were downloaded on 2026-11-19 (see `scripts/validate_vocabulary.ps1 -Rebuild` for exact URLs).
Raw files are kept in `data_sources/` (git-ignored, ~3.7 GB).

# Vocabulary database report

Generated from `assets/db/vocab.db` (content version 1, built 2026-11-18T18:20:38Z)
by `tools/data/validate_database.py` and `tools/data/make_vocab_report.py`.

## Result
**Validation: PASSED** – 0 errors.

**Validated unique lexical entries: 10,657** (unique `headword + part of speech`; topic links are not counted as entries).
The ≥ 10,000 target is met.

Minimum quality bar enforced for *every* entry (entries failing it were dropped, not padded):
headword · part of speech/expression type · Vietnamese meaning · English definition · ≥ 1 English example
sentence · ≥ 1 topic association · difficulty (1–5) · source provenance.

## Coverage
| Field | Entries |
|---|---:|
| Vietnamese meaning | 10,657 (100.0%) |
| English definition | 10,657 (100.0%) |
| ≥ 1 example sentence | 10,657 (100.0%) |
| Example sentence with Vietnamese translation (Tatoeba human translations, Vietnamese Wiktionary, curated) | 4,554 (42.7%) |
| IPA (UK or US) | 9,903 (92.9%) |
| British IPA | 9,699 (91.0%) |
| American IPA | 9,778 (91.8%) |
| Collocations / fixed phrases | 5,651 (53.0%) |
| Synonyms | 6,455 (60.6%) |
| Antonyms | 2,620 (24.6%) |
| Word family links | 4,679 (43.9%) |
| Multiple separate senses | 8,517 (79.9%) |
| Usage notes (curated) | 281 (2.6%) |
| Common spelling mistakes (curated) | 86 (0.8%) |
| Academic (NAWL) | 950 (8.9%) |

IPA sources – UK: {'enwikt': 6128, 'ipadict': 3571}; US: {'enwikt': 6054, 'ipadict': 3724}
(`enwikt` = accent-tagged Wiktionary IPA, `ipadict` = ipa-dict MIT dataset; ipa-dict is word-level and does not
distinguish homographs such as *record* n./v.).

Row totals: vocabulary_senses 37,911, translations 35,867, examples 43,090, collocations 17,069, lexical_relations 46,773, vocabulary_topics 14,873, writing_exercises 141, speaking_packs 24.

## CEFR levels
CEFR is shown only where it comes from CEFR-J (A1–B2) or the Octanove C1/C2 profile. Other entries carry an
**estimated difficulty** (1–5) derived from corpus frequency and are labelled "not rated" for CEFR.

| CEFR | Entries |
|---|---:|
| (not rated) | 2,084 |
| A1 | 1,043 |
| A2 | 1,289 |
| B1 | 2,236 |
| B2 | 2,489 |
| C1 | 831 |
| C2 | 685 |

| Difficulty (1 easy – 5 hard) | Entries |
|---|---:|
| 1 | 2,332 |
| 2 | 2,608 |
| 3 | 3,972 |
| 4 | 1,060 |
| 5 | 685 |

## Entry types and parts of speech
| Type | Entries |
|---|---:|
| word | 9,797 |
| idiom | 336 |
| phrasal_verb | 196 |
| expression | 171 |
| collocation | 157 |

| POS | Entries |
|---|---:|
| noun | 5,178 |
| adjective | 2,123 |
| verb | 1,754 |
| adverb | 662 |
| idiom | 336 |
| phrasal verb | 196 |
| collocation | 157 |
| expression | 79 |
| preposition | 69 |
| pronoun | 41 |
| conjunction | 29 |
| determiner | 29 |
| interjection | 4 |

## Provenance of the primary meaning / definition / examples
| Primary Vietnamese meaning source | Entries |
|---|---:|
| curated | 676 |
| enwikt | 5,445 |
| viwikt | 4,536 |

| Primary English definition source | Entries |
|---|---:|
| curated | 653 |
| enwikt | 10,000 |
| nawl | 4 |

| Example source | Examples |
|---|---:|
| curated | 335 |
| enwikt | 13,243 |
| tatoeba | 18,944 |
| viwikt | 10,568 |

`curated` Vietnamese meanings (≈676) are editorial: IELTS expressions written for the app,
common phrasal verbs missing from the open data, and high-value IELTS words whose first open-source gloss was archaic or the wrong sense
(e.g. *battery* "khẩu đội pháo" → "pin, ắc quy"; *cell* "phòng giam" → "tế bào; phòng giam"). All other meanings are copied from Wiktionary.

## Topics (50 IELTS topics)
Topic links come from curated seed lists (`curated`), Wiktionary sense topics/categories (`wiktionary`), list membership (`list`, NAWL → Academic),
entry type (`type`) or the fallback "General English" group (`default`): {'curated': 2296, 'default': 5324, 'list': 950, 'type': 599, 'wiktionary': 5704}.
Wiktionary-derived topic links are broad (e.g. many mathematics/physics terms fall under *Science*).

| IELTS topic | Entries |
|---|---:|
| education (Education) | 83 |
| environment (Environment) | 53 |
| climate (Climate Change) | 51 |
| technology (Technology) | 306 |
| ai (Artificial Intelligence) | 29 |
| science (Science) | 1,444 |
| healthcare (Healthcare) | 322 |
| mental_health (Mental Health) | 33 |
| psychology (Psychology) | 418 |
| society (Society) | 53 |
| culture (Culture) | 53 |
| globalization (Globalization) | 20 |
| economy (Economy) | 164 |
| business (Business) | 261 |
| employment (Employment) | 199 |
| government (Government) | 210 |
| politics (Politics) | 181 |
| crime (Crime) | 96 |
| law (Law) | 212 |
| tourism (Tourism) | 57 |
| transportation (Transportation) | 212 |
| urbanization (Urbanization) | 31 |
| housing (Housing) | 119 |
| architecture (Architecture) | 111 |
| agriculture (Agriculture) | 60 |
| food (Food) | 139 |
| family (Family) | 82 |
| relationships (Relationships) | 57 |
| communication (Communication) | 258 |
| media (Media) | 159 |
| advertising (Advertising) | 43 |
| art (Art) | 161 |
| music (Music) | 135 |
| sports (Sports) | 257 |
| wildlife (Wildlife) | 99 |
| biodiversity (Biodiversity) | 100 |
| energy (Energy) | 79 |
| space (Space Exploration) | 98 |
| research (Research) | 83 |
| public_services (Public Services) | 31 |
| population (Population) | 25 |
| migration (Migration) | 23 |
| consumerism (Consumerism) | 39 |
| lifestyle (Lifestyle) | 584 |
| history (History) | 80 |
| geography (Geography) | 98 |
| natural_resources (Natural Resources) | 45 |
| inequality (Social Inequality) | 37 |
| public_policy (Public Policy) | 34 |
| sustainable_development (Sustainable Development) | 33 |

| Skill / group | Entries |
|---|---:|
| general (General English) | 5,324 |
| academic (Academic English) | 950 |
| writing_task1 (Writing Task 1) | 69 |
| writing_task2 (Writing Task 2) | 70 |
| speaking (Speaking) | 79 |
| listening (Listening expressions) | 20 |
| phrasal_verbs (Phrasal verbs) | 196 |
| idioms (Idioms & fixed expressions) | 336 |
| collocations (Collocations) | 164 |
| confusables (Commonly confused words) | 108 |

## Dropped candidates (did not meet the quality bar)
| Reason | Candidates |
|---|---:|
| cefr_row_unusable_pos | 2 |
| duplicate_candidate | 278 |
| nawl_no_pos | 6 |
| frequency_word_mostly_capitalised | 143 |
| frequency_word_is_inflection | 1,086 |
| viwikt_example_unknown_token | 438 |
| word:no_vietnamese_meaning | 723 |
| word:no_english_definition | 416 |
| word:no_sentence_example | 600 |
| expression:no_vietnamese_meaning | 55 |
| expression:no_english_definition | 19 |
| expression:no_sentence_example | 3 |
| idiom:no_vietnamese_meaning | 9,142 |
| idiom:no_sentence_example | 4,233 |
| idiom:too_rare_in_corpus | 6,117 |
| phrasal_verb:no_vietnamese_meaning | 2,489 |
| phrasal_verb:too_rare_in_corpus | 906 |
| phrasal_verb:no_sentence_example | 458 |

## Known limitations
* Vietnamese meanings from Vietnamese Wiktionary (largely derived from the Free Vietnamese Dictionary Project) are sometimes
  old-fashioned or list a rare sense first; senses from English Wiktionary translation tables are aligned to English senses
  automatically (token overlap), which can occasionally mis-align.
* Only 4,554 (42.7%) entries have a Vietnamese translation of an example sentence;
  the rest have English-only examples (no machine translation was used).
* Some example sentences come from Wiktionary usage examples or Tatoeba and may use a different sense of the word than the primary meaning.
* Phrasal verbs (196) and idioms (336) are limited to those with a
  Vietnamese meaning, an example and corpus frequency ≥ 3.
* IELTS topic coverage is uneven: some topics (e.g. Globalization, Migration, Population) have fewer than 30 entries.

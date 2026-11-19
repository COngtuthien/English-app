<#
.SYNOPSIS  Validates the bundled vocabulary database (and optionally rebuilds it from sources first).
.PARAMETER Rebuild   Re-download (if missing) and rebuild assets/db/vocab.db from the open datasets.
#>
param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force 'tools\data\out' | Out-Null
if ($Rebuild) {
  $raw = 'data_sources\raw'; $work = 'data_sources\work'
  New-Item -ItemType Directory -Force $raw, $work | Out-Null
  $files = @{
    'vi-wiktextract.jsonl.gz' = 'https://kaikki.org/viwiktionary/raw-wiktextract-data.jsonl.gz'
    'en-wiktextract.jsonl' = 'https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl'
    'cefrj.csv' = 'https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/cefrj-vocabulary-profile-1.5.csv'
    'octanove-c1c2.csv' = 'https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/octanove-vocabulary-profile-c1c2-1.0.csv'
    'eng_sentences.tsv.bz2' = 'https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2'
    'vie_sentences.tsv.bz2' = 'https://downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2'
    'eng-vie_links.tsv.bz2' = 'https://downloads.tatoeba.org/exports/per_language/eng/eng-vie_links.tsv.bz2'
    'ipa_en_UK.txt' = 'https://raw.githubusercontent.com/open-dict-data/ipa-dict/master/data/en_UK.txt'
    'ipa_en_US.txt' = 'https://raw.githubusercontent.com/open-dict-data/ipa-dict/master/data/en_US.txt'
    'NAWL_12_lemmatized_for_teaching.csv' = 'https://www.newgeneralservicelist.com/s/NAWL_12_lemmatized_for_teaching.csv'
    'NAWL_12_with_en_definitions.csv' = 'https://www.newgeneralservicelist.com/s/NAWL_12_with_en_definitions.csv'
    'NGSL_12_stats.csv' = 'https://www.newgeneralservicelist.com/s/NGSL_12_stats.csv'
  }
  foreach ($f in $files.Keys) {
    if (-not (Test-Path "$raw\$f")) { Write-Host "Downloading $f"; & curl.exe -sSL --compressed -o "$raw\$f" $files[$f] }
  }
  python -I tools/data/extract_sources.py $raw $work; if ($LASTEXITCODE) { exit 1 }
  python -I tools/data/build_database.py $raw $work tools/data/curated assets/db/vocab.db tools/data/out/build_stats.json; if ($LASTEXITCODE) { exit 1 }
}
python -I tools/data/validate_database.py assets/db/vocab.db tools/data/out/validation.json
exit $LASTEXITCODE

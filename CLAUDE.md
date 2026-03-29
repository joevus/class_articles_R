# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Automate the process of finding and importing grad school syllabus readings into Zotero. The user's current manual workflow:
1. Open syllabus PDF
2. Google each article citation
3. Navigate to the article (often requires institutional login)
4. Click the Zotero browser connector to save to a collection

## Automation Approach

An R CLI script that:
1. Parses a syllabus PDF to extract week labels and their associated article citations ✅
2. Resolves DOIs via Crossref ✅
3. Opens one browser tab per article (in week order) at `https://doi.org/<doi>` ✅
4. The user clicks the Zotero browser connector on each tab to save it ✅
5. Articles without a DOI are printed for manual lookup ✅

**Institutional login cannot be automated** — this stays manual per university SSO/EZproxy constraints.

The Zotero API approach (creating collections, adding items, uploading PDFs) was abandoned due to Zotero cloud storage limits and sync complications.

## Syllabus Structure

Syllabi are PDFs with weeks labeled like "Week 1 Demand Side of International Trade" followed by article citations. The tool must detect these week headings and associate subsequent citations with the correct week/collection.

## What's Been Built

### `parser.R`
Parses a syllabus PDF into structured weeks + citations using `pdftools` (text extraction) and Gemini (`gemini-2.5-flash-lite`) for intelligent citation extraction. `temperature=0` is set for deterministic output.

**Usage:**
```bash
Rscript parser.R path/to/syllabus.pdf           # pretty-printed output
Rscript parser.R path/to/syllabus.pdf --json    # JSON output
```

### `doi_lookup.R`
Sources `parser.R`. Looks up DOIs via the Crossref REST API (`query.bibliographic`). Also captures full bibliographic metadata (title, authors, journal, year, volume, issue, pages, item type). Default min-score threshold: 80.

**Usage:**
```bash
Rscript doi_lookup.R path/to/syllabus.pdf
Rscript doi_lookup.R path/to/syllabus.pdf --min-score 70
```

**Results on POL 209:** 59/88 DOIs found (67%) at default threshold.

### `open_tabs.R`
Sources `doi_lookup.R`. Opens one browser tab per article (in week order) as the first step toward importing them into Zotero — the user then clicks the Zotero browser connector on each tab to save the article to their library. Articles without a DOI are printed for manual lookup.

**Usage:**
```bash
Rscript open_tabs.R path/to/syllabus.pdf
Rscript open_tabs.R path/to/syllabus.pdf --min-score 70
Rscript open_tabs.R path/to/syllabus.pdf --delay 2   # seconds between tabs
```

## Key Libraries

All HTTP calls use `httr2` directly — no wrapper packages for Crossref or Zotero.

- `pdftools` — extract text from syllabus PDFs (install binary version on Mac for bundled Poppler)
- `httr2` — all API calls (Gemini, Crossref)
- `jsonlite` — JSON parsing and serialization
- `optparse` — CLI argument parsing

## Architecture

Each script sources the previous one, building up the data pipeline:

```
parser.R → doi_lookup.R → open_tabs.R
```

Each script is also independently runnable (CLI) and sourceable in RStudio. The `if (!interactive() && sys.nframe() == 0)` guard ensures the CLI block only fires when the script is the entry point.

## Configuration

Stored in `.env` (not committed). See `.env.example`.

| Variable | Purpose |
|---|---|
| `GEMINI_API_KEY` | Google Gemini API key |
| `CROSSREF_EMAIL` | Optional — gets better Crossref rate limits (polite pool) |

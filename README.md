# Syllabus to Zotero

Automates importing grad school syllabus readings into Zotero. Give it a syllabus PDF and it opens a browser tab for each article so you just click the Zotero connector — no more Googling each citation manually.

## How it works

1. Extracts citations from a syllabus PDF using Google Gemini
2. Looks up each citation's DOI via the Crossref API
3. Prompts you to choose a week (or all weeks)
4. Opens `https://doi.org/<doi>` in your browser for each article
5. You click the Zotero browser connector on each tab to save it

Institutional login (SSO/EZproxy) remains manual — there's no way to automate that.

## Prerequisites

- **R** (any recent version) — [r-project.org](https://www.r-project.org)
- **R packages**
  ```r
  install.packages(c("pdftools", "httr2", "jsonlite", "optparse"))
  ```
  `pdftools` installs with Poppler bundled when using the CRAN binary (the default). Only if you build from source would you need `brew install poppler` separately.
- **Zotero** desktop app + browser connector installed

## API keys

| Key | Required | Notes |
|-----|----------|-------|
| `GEMINI_API_KEY` | Yes | Used for syllabus parsing. The script uses `gemini-2.5-flash-lite`. Get a free key at [Google AI Studio](https://aistudio.google.com/app/apikey) — sign in, click **Create API key**, and copy the result. If you can't find it, ask Gemini directly — it can walk you through the steps. |
| `CROSSREF_EMAIL` | No | Any email address — unlocks higher Crossref rate limits |

## Setup

1. Copy the example env file and fill in your keys:
   ```bash
   cp .env.example .env
   ```
   Then open `.env` and set `GEMINI_API_KEY` (and optionally `CROSSREF_EMAIL`).

## Usage

```bash
Rscript open_tabs.R path/to/syllabus.pdf
```

This opens browser tabs for each article — the final step is clicking the Zotero browser connector on each tab to save it to your library. The script will parse the syllabus, look up DOIs, then prompt you:

```
Which week would you like to open?

   1. Week 1 Demand Side of International Trade (6 DOI(s))
   2. Week 2 Supply Side of International Trade (5 DOI(s))
   ...
   a. All weeks

Enter a number or 'a' for all:
```

After you choose, it opens one tab per article. Articles with no DOI found are printed at the end for manual lookup.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--min-score` | 80 | Minimum Crossref confidence score (0–100). Lower values find more DOIs but with higher risk of wrong matches. |
| `--delay` | 1 | Seconds between opening tabs. Increase if your browser struggles to keep up. |

```bash
Rscript open_tabs.R path/to/syllabus.pdf --min-score 70 --delay 2
```

## Syllabus format

The syllabus must label weeks clearly for the parser to detect them — for example:

> **Week 1 Demand Side of International Trade**

Most standard syllabi work without any changes.

## Other scripts

These run automatically as part of the pipeline but can also be run standalone for debugging or exploration:

| Script | What it does |
|--------|-------------|
| `parser.R` | Extracts week labels and citations from a syllabus PDF |
| `doi_lookup.R` | Looks up DOIs and bibliographic metadata via Crossref |

Each accepts `--json` to output raw JSON, and `--min-score` where applicable.

## Credits

Built with the help of [Claude](https://claude.ai) by Anthropic.

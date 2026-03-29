# run.R — RStudio entry point for Syllabus to Zotero.
#
# 1. Update the path below to point to your syllabus file.
# 2. Click the Source button (top-right of this editor pane) to run.

source("open_tabs.R")

weeks <- parse_syllabus("path/to/your/syllabus.pdf")
weeks <- enrich_with_dois(weeks)
open_in_browser(weeks)

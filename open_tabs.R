#!/usr/bin/env Rscript
# open_tabs.R — Open syllabus readings in the browser for Zotero connector import.
#
# Prompts the user to select a week or all weeks, then opens one browser tab
# per article for every DOI found. The user then clicks the Zotero browser
# connector on each tab to save the article to their Zotero library.
# Articles without a DOI are printed for manual lookup.
#
# Usage (terminal):
#   Rscript open_tabs.R path/to/syllabus.pdf
#   Rscript open_tabs.R path/to/syllabus.pdf --min-score 70
#   Rscript open_tabs.R path/to/syllabus.pdf --delay 2
#
# Usage (RStudio):
#   source("open_tabs.R")
#   weeks <- parse_syllabus("syllabus.pdf")
#   weeks <- enrich_with_dois(weeks)
#   open_in_browser(weeks)               # prompts for week selection
#   open_in_browser(weeks, week = 3)     # open week 3 directly
#   open_in_browser(weeks, week = "all") # skip prompt

source("doi_lookup.R")  # pipeline up to DOI resolution


# --- Week selection prompt ----------------------------------------------------

prompt_week_selection <- function(weeks) {
  cat("\nWhich week would you like to open?\n\n")
  for (i in seq_along(weeks)) {
    n_doi <- sum(vapply(weeks[[i]]$citations,
                        function(c) !is.null(c$doi) && nzchar(c$doi %||% ""), logical(1)))
    cat(sprintf("  %2d. %s (%d DOI(s))\n", i, weeks[[i]]$label, n_doi))
  }
  cat(sprintf("   a. All weeks\n\n"))

  repeat {
    cat("Enter a number or 'a' for all: ")
    raw <- trimws(readLines(con = "stdin", n = 1))
    if (tolower(raw) == "a") return("all")
    n <- suppressWarnings(as.integer(raw))
    if (!is.na(n) && n >= 1L && n <= length(weeks)) return(n)
    cat(sprintf("  Please enter a number between 1 and %d, or 'a'.\n",
                length(weeks)))
  }
}


# --- Main function ------------------------------------------------------------

open_in_browser <- function(weeks, delay = 1, week = NULL) {
  # Resolve which weeks to open
  if (is.null(week)) {
    week <- prompt_week_selection(weeks)
  }

  selected <- if (identical(week, "all")) weeks else list(weeks[[week]])

  n_opened <- 0L
  no_doi   <- list()

  for (w in selected) {
    message("\n--- ", w$label, " ---")

    for (cit in w$citations) {
      doi <- cit$doi %||% NA_character_

      if (!is.na(doi)) {
        url <- paste0("https://doi.org/", doi)
        message("  Opening: ", substr(cit$raw, 1, 70))
        browseURL(url)
        n_opened <- n_opened + 1L
        if (delay > 0) Sys.sleep(delay)
      } else {
        no_doi <- c(no_doi, list(cit$raw))
      }
    }
  }

  if (length(no_doi) > 0) {
    message(sprintf("\n%d article(s) had no DOI — look these up manually:",
                    length(no_doi)))
    for (raw in no_doi) {
      cat(sprintf("  %s\n", substr(raw, 1, 100)))
    }
  }

  message(sprintf(
    "\nDone. %d tab(s) opened, %d article(s) need manual lookup.",
    n_opened, length(no_doi)
  ))
  invisible(list(n_opened = n_opened, n_no_doi = length(no_doi)))
}


# --- CLI ----------------------------------------------------------------------
if (!interactive() && sys.nframe() == 0) {
  opt_parser <- OptionParser(
    usage       = "Rscript %prog [options] <syllabus.pdf>",
    description = paste(
      "Open syllabus articles in the browser so you can click the Zotero",
      "connector to import them. Prompts for week selection at runtime."
    ),
    option_list = list(
      make_option("--min-score", type = "double", default = 80,
                  help = "Minimum Crossref confidence score [default: %default]"),
      make_option("--delay", type = "double", default = 1,
                  help = "Seconds between opening tabs [default: %default]")
    )
  )

  args     <- parse_args(opt_parser, positional_arguments = 1)
  pdf_path <- args$args[[1]]

  if (!file.exists(pdf_path)) {
    message("Error: file not found: ", pdf_path)
    quit(status = 1)
  }

  message("Parsing syllabus...")
  weeks <- parse_syllabus(pdf_path)

  message("Looking up DOIs via Crossref...")
  weeks <- enrich_with_dois(weeks, min_score = args$options$`min-score`)

  open_in_browser(weeks, delay = args$options$delay)
}

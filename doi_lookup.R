#!/usr/bin/env Rscript
# doi_lookup.R — Add DOIs to parsed syllabus citations via Crossref.
#
# No extra packages needed beyond what parser.R already uses (httr2, jsonlite).
#
# Usage (terminal):
#   Rscript doi_lookup.R path/to/syllabus.pdf
#   Rscript doi_lookup.R path/to/syllabus.pdf --json
#   Rscript doi_lookup.R path/to/syllabus.pdf --min-score 70
#
# Usage (RStudio):
#   source("doi_lookup.R")   # also sources parser.R
#   weeks <- parse_syllabus("syllabus.pdf")
#   weeks <- enrich_with_dois(weeks)
#   print_doi_results(weeks)

source("parser.R")  # brings in parse_syllabus(), %||%, httr2, jsonlite, optparse


# --- Core functions -----------------------------------------------------------

# Empty metadata skeleton — used when no match is found.
empty_meta <- list(
  doi = NA_character_, score = NA_real_,
  title = NA_character_, authors = list(),
  journal = NA_character_, year = NA_character_,
  volume = NA_character_, issue = NA_character_,
  pages = NA_character_, item_type = NA_character_
)

# Extract bibliographic metadata from a single Crossref item.
extract_crossref_meta <- function(item) {
  year <- tryCatch({
    parts <- item$published[["date-parts"]]
    if (length(parts) > 0 && length(parts[[1]]) > 0)
      as.character(parts[[1]][[1]])
    else NA_character_
  }, error = function(e) NA_character_)

  list(
    title     = item$title[[1]]               %||% NA_character_,
    journal   = item[["container-title"]][[1]] %||% NA_character_,
    year      = year,
    volume    = item$volume                   %||% NA_character_,
    issue     = item$issue                    %||% NA_character_,
    pages     = item$page                     %||% NA_character_,
    item_type = item$type                     %||% NA_character_,
    authors   = lapply(item$author %||% list(), function(a)
      list(given = a$given %||% "", family = a$family %||% "")
    )
  )
}

# Returns a named list with doi, score, and full bibliographic metadata.
# Returns doi = NA (and empty metadata) if nothing meets min_score.
lookup_doi <- function(citation, min_score = 80) {
  email <- Sys.getenv("CROSSREF_EMAIL")

  req <- request("https://api.crossref.org/works") |>
    req_url_query(
      `query.bibliographic` = citation,
      rows                  = 1,
      mailto                = if (nzchar(email)) email else NULL
    ) |>
    req_error(is_error = \(r) FALSE)

  resp <- tryCatch(req_perform(req), error = function(e) {
    message("  HTTP error: ", conditionMessage(e))
    NULL
  })

  if (is.null(resp) || resp_is_error(resp)) return(empty_meta)

  items <- resp_body_json(resp)$message$items
  if (length(items) == 0) return(empty_meta)

  item  <- items[[1]]
  score <- as.numeric(item$score %||% NA_real_)
  doi   <- item$DOI %||% NA_character_

  if (!is.na(score) && score < min_score) {
    return(modifyList(empty_meta, list(score = score)))
  }

  c(list(doi = doi, score = score), extract_crossref_meta(item))
}

# Enriches a weeks list (from parse_syllabus) by adding doi + score to each
# citation. Citations go from plain strings to list(raw, doi, score).
enrich_with_dois <- function(weeks, min_score = 80) {
  total <- sum(sapply(weeks, function(w) length(w$citations)))
  done  <- 0L

  lapply(weeks, function(week) {
    citations <- lapply(week$citations, function(citation) {
      done <<- done + 1L
      message(sprintf("[%d/%d] %s", done, total, substr(citation, 1, 72)))
      match <- lookup_doi(citation, min_score)
      c(list(raw = citation), match)
    })
    list(label = week$label, citations = citations)
  })
}


# --- Output helpers -----------------------------------------------------------

print_doi_results <- function(weeks) {
  if (length(weeks) == 0) {
    cat("No weeks found.\n")
    return(invisible(NULL))
  }

  found <- 0L
  total <- 0L

  for (week in weeks) {
    cat(strrep("=", 60), "\n")
    cat(sprintf("  %s\n", week$label))
    cat(strrep("=", 60), "\n")
    for (i in seq_along(week$citations)) {
      cit   <- week$citations[[i]]
      total <- total + 1L
      if (!is.na(cit$doi)) {
        found <- found + 1L
        cat(sprintf("  %d. %s\n     DOI: %s (score: %.1f)\n",
                    i, cit$raw, cit$doi, cit$score %||% NA_real_))
      } else {
        score_note <- if (!is.na(cit$score %||% NA_real_))
          sprintf(" (best score %.1f below threshold)", cit$score) else ""
        cat(sprintf("  %d. %s\n     DOI: not found%s\n", i, cit$raw, score_note))
      }
    }
    cat("\n")
  }

  cat(sprintf("DOIs found: %d / %d (%.0f%%)\n",
              found, total, 100 * found / max(total, 1)))
}


# --- CLI ----------------------------------------------------------------------
if (!interactive() && sys.nframe() == 0) {
  opt_parser <- OptionParser(
    usage       = "Rscript %prog [options] <syllabus.pdf>",
    description = "Look up DOIs for syllabus citations via Crossref.",
    option_list = list(
      make_option("--json", action = "store_true", default = FALSE,
                  help = "Print raw JSON instead of formatted output"),
      make_option("--min-score", type = "double", default = 80,
                  help = "Minimum Crossref confidence score to accept [default: %default]")
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

  message(sprintf("Looking up DOIs for %d citation(s) via Crossref...",
                  sum(sapply(weeks, function(w) length(w$citations)))))
  weeks_with_dois <- enrich_with_dois(weeks, min_score = args$options$`min-score`)

  if (args$options$json) {
    cat(toJSON(list(weeks = weeks_with_dois), auto_unbox = TRUE, pretty = TRUE), "\n")
  } else {
    print_doi_results(weeks_with_dois)
  }
}

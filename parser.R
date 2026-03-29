#!/usr/bin/env Rscript
# parser.R — Parse a syllabus (PDF or Word doc) into weeks and citations.
#
# Required packages (install once):
#   install.packages(c("pdftools", "officer", "httr2", "jsonlite", "optparse"))
#
# Usage:
#   Rscript parser.R path/to/syllabus.pdf
#   Rscript parser.R path/to/syllabus.docx
#   Rscript parser.R path/to/syllabus.pdf --json   # raw JSON output

library(pdftools)
library(officer)
library(httr2)
library(jsonlite)
library(optparse)

# Load .env file if present (base R — no extra package needed)
if (file.exists(".env")) readRenviron(".env")


# --- Core functions -----------------------------------------------------------

extract_pdf_text <- function(path) {
  pages <- pdftools::pdf_text(path)
  paste(pages, collapse = "\n\n")
}

extract_docx_text <- function(path) {
  doc   <- officer::read_docx(path)
  lines <- officer::docx_summary(doc)$text
  paste(lines[!is.na(lines)], collapse = "\n")
}

extract_syllabus_text <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "pdf")        extract_pdf_text(path)
  else if (ext == "docx")  extract_docx_text(path)
  else stop("Unsupported file type: ", ext, ". Only PDF and Word (.docx) are supported.")
}

parse_syllabus <- function(pdf_path) {
  text <- extract_syllabus_text(pdf_path)
  if (!nzchar(trimws(text))) stop("Could not extract text from: ", pdf_path)

  prompt <- sprintf(
    'You are extracting structured data from a grad school course syllabus.

Your task: identify each week (or session/module) and the readings assigned to it.

Weeks are typically labeled like:
- "Week 1: Demand Side of International Trade"
- "Week 2 - Supply and Comparative Advantage"
- "Session 3: Firms and Trade"
- "Module 1 Introduction"

For each week, extract all article/reading citations. A citation typically includes
some combination of: author name(s), article title, journal name, year, volume, pages.
Include the full citation text as it appears.

Ignore: syllabus metadata (instructor info, office hours, grading policies, course
descriptions), and non-reading items like "in-class discussion" or "problem set due".

Return a JSON object with this exact structure:
{
  "weeks": [
    {
      "label": "Week 1 Demand Side of International Trade",
      "citations": [
        "Krugman, Paul. 1979. Increasing Returns, Monopolistic Competition, and International Trade. Journal of International Economics 9(4): 469-479.",
        "Melitz, Marc J. 2003. The Impact of Trade on Intra-Industry Reallocations and Aggregate Industry Productivity. Econometrica 71(6): 1695-1725."
      ]
    }
  ]
}

If you cannot find any week structure, return {"weeks": []}.
Return only valid JSON, no other text.

SYLLABUS TEXT:
%s',
    text
  )

  resp <- request("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent") |>
    req_url_query(key = Sys.getenv("GEMINI_API_KEY")) |>
    req_body_json(list(
      contents          = list(list(parts = list(list(text = prompt)))),
      generationConfig  = list(temperature = 0)
    )) |>
    req_error(is_error = \(r) FALSE) |>   # handle HTTP errors manually
    req_perform()

  if (resp_is_error(resp)) {
    stop("Gemini API error ", resp_status(resp), ": ", resp_body_string(resp))
  }

  raw_text <- resp |>
    resp_body_json() |>
    (\(r) r$candidates[[1]]$content$parts[[1]]$text)()

  # Strip markdown code fences if Gemini wraps the JSON
  raw_text <- trimws(raw_text)
  if (startsWith(raw_text, "```")) {
    lines <- strsplit(raw_text, "\n")[[1]]
    end   <- if (tail(lines, 1) == "```") length(lines) - 1L else length(lines)
    raw_text <- paste(lines[2:end], collapse = "\n")
  }

  data <- fromJSON(raw_text, simplifyVector = FALSE)

  lapply(data$weeks %||% list(), function(w) {
    list(label = w$label, citations = w$citations %||% list())
  })
}


# --- Output helpers -----------------------------------------------------------

print_results <- function(weeks) {
  if (length(weeks) == 0) {
    cat("No weeks found in syllabus.\n")
    return(invisible(NULL))
  }

  cat(sprintf("\nFound %d week(s):\n\n", length(weeks)))
  for (week in weeks) {
    cat(strrep("=", 60), "\n")
    cat(sprintf("  %s\n", week$label))
    cat(strrep("=", 60), "\n")
    if (length(week$citations) > 0) {
      for (i in seq_along(week$citations)) {
        cat(sprintf("  %d. %s\n", i, week$citations[[i]]))
      }
    } else {
      cat("  (no citations found)\n")
    }
    cat("\n")
  }
}


# --- Null-coalescing operator (base R doesn't have one) -----------------------
`%||%` <- function(x, y) if (!is.null(x)) x else y


# --- CLI (only runs via `Rscript parser.R`, not when sourced in RStudio) ------
#
# RStudio users: source this file, then call functions directly, e.g.:
#   source("parser.R")
#   weeks <- parse_syllabus("syllabus.pdf")
#   print_results(weeks)

if (!interactive() && sys.nframe() == 0) {
  opt_parser <- OptionParser(
    usage       = "Rscript %prog [options] <syllabus.pdf|syllabus.docx>",
    description = "Parse a syllabus (PDF or Word doc) into weeks and article citations.",
    option_list = list(
      make_option("--json", action = "store_true", default = FALSE,
                  help = "Print raw JSON instead of formatted output")
    )
  )

  args     <- parse_args(opt_parser, positional_arguments = 1)
  pdf_path <- args$args[[1]]

  if (!file.exists(pdf_path)) {
    message("Error: file not found: ", pdf_path)
    quit(status = 1)
  }

  if (!nzchar(Sys.getenv("GEMINI_API_KEY"))) {
    message("Error: GEMINI_API_KEY not set. Add it to a .env file or your environment.")
    quit(status = 1)
  }

  message("Parsing ", pdf_path, "...")
  weeks <- parse_syllabus(pdf_path)

  if (args$options$json) {
    cat(toJSON(list(weeks = weeks), auto_unbox = TRUE, pretty = TRUE), "\n")
  } else {
    print_results(weeks)
  }
}

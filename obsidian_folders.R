#!/usr/bin/env Rscript
# obsidian_folders.R — Create one folder per syllabus week inside an Obsidian vault,
# with one note per reading inside each week's folder.
#
# Folders are named "Week <n> - <topic>", e.g. "Week 1 - Demand Side of
# International Trade". Notes are named after the authors' last names and year
# ("Krugman 1979", "Smith and Jones 2010", "Melitz et al 2003"), and contain the
# full citation on their first line. Existing folders and notes are left alone,
# and if you already made a folder for a week ("Week 4 Elections"), its notes go there.
#
# Usage (terminal):
#   Rscript obsidian_folders.R path/to/syllabus.pdf --dir ~/Vault/Classes/POL209
#   Rscript obsidian_folders.R path/to/syllabus.pdf --dir ~/Vault/Classes/POL209 --dry-run
#   Rscript obsidian_folders.R path/to/syllabus.pdf --dir ~/Vault/Classes/POL209 \
#     --weeks 4-9 --required-only --journal
#
# Usage (RStudio):
#   source("obsidian_folders.R")
#   weeks <- parse_syllabus("syllabus.pdf", required_only = TRUE)
#   create_week_folders(weeks, "~/Vault/Classes/POL209", only_weeks = 4:9, journal = TRUE)

source("parser.R")  # only needs week labels and citations, so no Crossref lookup


# --- Naming -------------------------------------------------------------------

# Characters that macOS, Windows, or Obsidian links can't handle in a name
sanitize_file_name <- function(x) {
  x <- gsub('[/\\\\:*?"<>|#^\\[\\]]', " ", x, perl = TRUE)
  x <- gsub("\\s+", " ", x)
  trimws(gsub("^[. ]+|[. ]+$", "", x))
}

# "Week 1: Demand Side of Trade" -> list(num = 1, topic = "Demand Side of Trade").
# Bare numbered labels work too: "1 – Thinking about theory" -> list(num = 1, ...).
# Falls back to the week's position when the label has no number.
week_parts <- function(label, index) {
  pattern <- "^\\s*(week|session|module|unit|class|lecture|topic)\\s*(\\d+)\\s*[:.–—-]*\\s*(.*)$"
  bare    <- "^\\s*(\\d+)\\s*[:.–—-]+\\s*(.*)$"
  m <- regmatches(label, regexec(pattern, label, ignore.case = TRUE, perl = TRUE))[[1]]
  b <- regmatches(label, regexec(bare, label, perl = TRUE))[[1]]

  if (length(m) > 0) {
    num   <- as.integer(m[3])
    topic <- m[4]
    # "Week 1: 1 – Thinking about theory" -> drop the repeated number
    rep <- regmatches(topic, regexec(bare, topic, perl = TRUE))[[1]]
    if (length(rep) > 0 && as.integer(rep[2]) == num) topic <- rep[3]
  } else if (length(b) > 0) {
    num   <- as.integer(b[2])
    topic <- b[3]
  } else {
    num   <- index
    topic <- label
  }

  list(num = num, topic = sanitize_file_name(topic))
}

# "Week 1: Demand Side of Trade" -> "Week 1 - Demand Side of Trade"
week_folder_name <- function(label, index) {
  p <- week_parts(label, index)
  if (nzchar(p$topic)) sprintf("Week %d - %s", p$num, p$topic) else sprintf("Week %d", p$num)
}

# A folder you already made for this week, e.g. "Week 4 Elections and accountability",
# whatever its exact name. NULL when there isn't one.
existing_week_folder <- function(dir, num) {
  if (!dir.exists(dir)) return(NULL)
  folders <- list.dirs(dir, full.names = FALSE, recursive = FALSE)
  match   <- folders[grepl(sprintf("^week\\s*%d(\\D|$)", num), folders, ignore.case = TRUE)]
  if (length(match) == 0) NULL else match[1]
}

# "4-9" -> 4:9, "3,5,7" -> c(3, 5, 7), "2-4,8" -> c(2, 3, 4, 8)
parse_week_numbers <- function(x) {
  parts <- trimws(strsplit(x, ",")[[1]])
  unlist(lapply(parts, function(p) {
    ends <- as.integer(strsplit(p, "-")[[1]])
    if (anyNA(ends) || !length(ends) %in% 1:2) stop("Can't read --weeks value: ", x)
    seq(ends[1], ends[length(ends)])
  }))
}

# "Krugman 1979", "Smith and Jones 2010", "Melitz et al 2003", plus the journal
# when given ("Gingerich 2013 BJPS").
# Falls back to the start of the citation when no authors were found.
note_title <- function(authors, year, raw, journal = "") {
  authors <- unlist(authors)
  base <- switch(
    as.character(min(length(authors), 3)),
    "0" = substr(raw, 1, 50),
    "1" = authors[1],
    "2" = paste(authors[1], "and", authors[2]),
    "3" = paste(authors[1], "et al")
  )
  if (!is.na(year) && nzchar(year)) base <- paste(base, year)
  if (!is.na(journal) && nzchar(journal)) base <- paste(base, journal)
  sanitize_file_name(base)
}

# Two readings with the same title in one week become "Smith 2010a", "Smith 2010b"
dedupe_titles <- function(titles) {
  dup <- titles %in% titles[duplicated(titles)]
  titles[dup] <- paste0(titles[dup],
                        ave(titles[dup], titles[dup], FUN = function(x) letters[seq_along(x)]))
  titles
}


# --- Author lookup ------------------------------------------------------------

# One Gemini call for every citation in the syllabus. Citations go from plain
# strings to list(raw, authors, year, journal).
add_author_names <- function(weeks) {
  raws <- unlist(lapply(weeks, function(w)
    vapply(w$citations, function(c) if (is.list(c)) c$raw else c, character(1))))

  if (length(raws) == 0) return(weeks)

  prompt <- sprintf(
    'For each numbered citation below, return the last names of ALL authors in the
order they are listed, the publication year, and a short journal abbreviation.

- Use only family names (e.g. "Krugman", "van der Ploeg", "García-Peñalosa").
  Do not include editors of an edited volume.
- For an organization as author, use its name (e.g. "World Bank").
- If there is no author, return an empty list. If there is no year, return "".
- Journal: ALWAYS abbreviate. Use the common short form a political scientist
  would use, e.g. "APSR", "AJPS", "JOP", "BJPS", "CPS", "IO", "QJE", "JDE",
  "RIO", "RIPE", "JEMS", "PoP", "QJPS", "ARPS", "World Dev", "Governance".
  If there is no well-known short form and the name is longer than two words,
  use the capital initials of its main words (skip "of", "and", "the"), e.g.
  "Comparative Migration Studies" -> "CMS". One- or two-word names may stay
  as they are (e.g. "Public Choice", "Electoral Studies"). If the reading is a
  book or a book chapter, or no journal is given, return "".

Return a JSON object with this exact structure, one entry per citation:
{"citations": [{"id": 1, "authors": ["Smith", "Jones"], "year": "2010", "journal": "APSR"}]}

CITATIONS:
%s',
    paste(sprintf("%d. %s", seq_along(raws), raws), collapse = "\n")
  )

  resp <- request("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent") |>
    req_url_query(key = Sys.getenv("GEMINI_API_KEY")) |>
    req_body_json(list(
      contents          = list(list(parts = list(list(text = prompt)))),
      generationConfig  = list(temperature = 0, responseMimeType = "application/json")
    )) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()

  if (resp_is_error(resp)) {
    stop("Gemini API error ", resp_status(resp), ": ", resp_body_string(resp))
  }

  raw_text <- resp |>
    resp_body_json() |>
    (\(r) r$candidates[[1]]$content$parts[[1]]$text)()

  # Index results by id so a skipped or reordered entry can't shift the rest
  found <- list()
  for (entry in fromJSON(raw_text, simplifyVector = FALSE)$citations %||% list()) {
    found[[as.character(entry$id)]] <- entry
  }

  i <- 0L
  lapply(weeks, function(w) {
    w$citations <- lapply(w$citations, function(c) {
      i     <<- i + 1L
      entry <- found[[as.character(i)]]
      list(raw     = raws[[i]],
           authors = unlist(entry$authors) %||% character(0),
           year    = as.character(entry$year %||% NA_character_),
           journal = as.character(entry$journal %||% ""))
    })
    w
  })
}


# --- Main function ------------------------------------------------------------

write_note <- function(path, text) {
  con <- file(path, "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(text, con)
}

# only_weeks: week numbers to handle (e.g. 4:9); NULL means every week.
# journal:    add a journal abbreviation to each note title.
create_week_folders <- function(weeks, dir, dry_run = FALSE, only_weeks = NULL,
                                journal = FALSE) {
  if (length(weeks) == 0) stop("No weeks found in syllabus.")

  # Number weeks before filtering, so unnumbered labels keep their position
  nums <- vapply(seq_along(weeks), function(i) week_parts(weeks[[i]]$label, i)$num, integer(1))
  for (i in seq_along(weeks)) weeks[[i]]$num <- nums[i]
  if (!is.null(only_weeks)) {
    weeks <- weeks[nums %in% only_weeks]
    if (length(weeks) == 0) stop("None of the requested weeks were found in the syllabus.")
  }

  message("Looking up author names...")
  weeks <- add_author_names(weeks)

  dir <- path.expand(dir)
  if (!dir.exists(dir) && !dry_run) {
    dir.create(dir, recursive = TRUE)
    message("Created ", dir)
  }

  n_folders <- 0L
  n_notes   <- 0L

  for (i in seq_along(weeks)) {
    # Reuse a folder you already made for this week number, whatever it's called
    name   <- existing_week_folder(dir, weeks[[i]]$num) %||%
                week_folder_name(weeks[[i]]$label, weeks[[i]]$num)
    folder <- file.path(dir, name)

    if (dir.exists(folder)) {
      message("\n  Exists:  ", name)
    } else if (dry_run) {
      message("\n  Would create: ", name)
    } else if (dir.create(folder, showWarnings = FALSE)) {
      message("\n  Created: ", name)
      n_folders <- n_folders + 1L
    } else {
      message("\n  Failed:  ", name, " (skipping its notes)")
      next
    }

    cits   <- weeks[[i]]$citations
    titles <- dedupe_titles(vapply(cits, function(c)
      note_title(c$authors, c$year, c$raw, if (journal) c$journal else ""), character(1)))

    for (j in seq_along(cits)) {
      note <- file.path(folder, paste0(titles[j], ".md"))
      if (file.exists(note)) {
        message("      Exists:  ", titles[j])
      } else if (dry_run) {
        message("      Would create: ", titles[j])
      } else {
        write_note(note, cits[[j]]$raw)
        message("      Created: ", titles[j])
        n_notes <- n_notes + 1L
      }
    }
  }

  if (!dry_run) {
    message(sprintf("\nDone. %d folder(s) and %d note(s) created in %s",
                    n_folders, n_notes, dir))
  }
  invisible(weeks)
}


# --- CLI ----------------------------------------------------------------------
if (!interactive() && sys.nframe() == 0) {
  opt_parser <- OptionParser(
    usage       = "Rscript %prog --dir <folder> [options] <syllabus.pdf|syllabus.docx>",
    description = paste(
      "Create one folder per syllabus week inside an Obsidian vault,",
      "with one note per reading."
    ),
    option_list = list(
      make_option("--dir", type = "character", default = NULL,
                  help = "Folder in your vault where week folders are created (required)"),
      make_option("--dry-run", action = "store_true", default = FALSE,
                  help = "Show the folder and note names without creating anything"),
      make_option("--weeks", type = "character", default = NULL,
                  help = "Only these week numbers, e.g. 4-9 or 3,5,7 (default: all)"),
      make_option("--required-only", action = "store_true", default = FALSE,
                  help = "Skip recommended / further readings"),
      make_option("--journal", action = "store_true", default = FALSE,
                  help = "Add a journal abbreviation to note titles, e.g. 'Gingerich 2013 BJPS'")
    )
  )

  args     <- parse_args(opt_parser, positional_arguments = 1)
  pdf_path <- args$args[[1]]
  dir      <- args$options$dir

  if (is.null(dir)) {
    message("Error: --dir is required, e.g. --dir ~/Vault/Classes/POL209")
    quit(status = 1)
  }

  if (!file.exists(pdf_path)) {
    message("Error: file not found: ", pdf_path)
    quit(status = 1)
  }

  if (!nzchar(Sys.getenv("GEMINI_API_KEY"))) {
    message("Error: GEMINI_API_KEY not set. Add it to a .env file or your environment.")
    quit(status = 1)
  }

  only_weeks <- if (is.null(args$options$weeks)) NULL else parse_week_numbers(args$options$weeks)

  message("Parsing syllabus...")
  weeks <- parse_syllabus(pdf_path, required_only = args$options$`required-only`)

  create_week_folders(weeks, dir,
                      dry_run    = args$options$`dry-run`,
                      only_weeks = only_weeks,
                      journal    = args$options$journal)
}

#!/usr/bin/env Rscript
# obsidian_folders.R — Create one folder per syllabus week inside an Obsidian vault.
#
# Folders are named "Week <n> - <topic>", e.g. "Week 1 - Demand Side of
# International Trade". Folders that already exist are left alone.
#
# Usage (terminal):
#   Rscript obsidian_folders.R path/to/syllabus.pdf --dir ~/Vault/Classes/POL209
#   Rscript obsidian_folders.R path/to/syllabus.pdf --dir ~/Vault/Classes/POL209 --dry-run
#
# Usage (RStudio):
#   source("obsidian_folders.R")
#   weeks <- parse_syllabus("syllabus.pdf")
#   create_week_folders(weeks, "~/Vault/Classes/POL209")

source("parser.R")  # only needs week labels, so no Crossref lookup


# --- Folder naming ------------------------------------------------------------

# Characters that macOS, Windows, or Obsidian links can't handle in a name
sanitize_folder_name <- function(x) {
  x <- gsub('[/\\\\:*?"<>|#^\\[\\]]', " ", x, perl = TRUE)
  x <- gsub("\\s+", " ", x)
  trimws(gsub("^[. ]+|[. ]+$", "", x))
}

# "Week 1: Demand Side of Trade" -> "Week 1 - Demand Side of Trade".
# Falls back to the week's position when the label has no number.
week_folder_name <- function(label, index) {
  pattern <- "^\\s*(week|session|module|unit|class|lecture|topic)\\s*(\\d+)\\s*[:.–—-]*\\s*(.*)$"
  m <- regmatches(label, regexec(pattern, label, ignore.case = TRUE, perl = TRUE))[[1]]

  if (length(m) > 0) {
    num   <- as.integer(m[3])
    topic <- m[4]
  } else {
    num   <- index
    topic <- label
  }

  topic <- sanitize_folder_name(topic)
  if (nzchar(topic)) sprintf("Week %d - %s", num, topic) else sprintf("Week %d", num)
}


# --- Main function ------------------------------------------------------------

create_week_folders <- function(weeks, dir, dry_run = FALSE) {
  if (length(weeks) == 0) stop("No weeks found in syllabus.")

  dir <- path.expand(dir)
  if (!dir.exists(dir) && !dry_run) {
    dir.create(dir, recursive = TRUE)
    message("Created ", dir)
  }

  names <- vapply(seq_along(weeks),
                  function(i) week_folder_name(weeks[[i]]$label, i),
                  character(1))

  n_created <- 0L
  for (name in names) {
    path <- file.path(dir, name)
    if (dir.exists(path)) {
      message("  Exists:  ", name)
    } else if (dry_run) {
      message("  Would create: ", name)
    } else if (dir.create(path, showWarnings = FALSE)) {
      message("  Created: ", name)
      n_created <- n_created + 1L
    } else {
      message("  Failed:  ", name)
    }
  }

  if (!dry_run) {
    message(sprintf("\nDone. %d folder(s) created in %s", n_created, dir))
  }
  invisible(file.path(dir, names))
}


# --- CLI ----------------------------------------------------------------------
if (!interactive() && sys.nframe() == 0) {
  opt_parser <- OptionParser(
    usage       = "Rscript %prog --dir <folder> [options] <syllabus.pdf|syllabus.docx>",
    description = "Create one folder per syllabus week inside an Obsidian vault.",
    option_list = list(
      make_option("--dir", type = "character", default = NULL,
                  help = "Folder in your vault where week folders are created (required)"),
      make_option("--dry-run", action = "store_true", default = FALSE,
                  help = "Show the folder names without creating anything")
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

  message("Parsing syllabus...")
  weeks <- parse_syllabus(pdf_path)

  create_week_folders(weeks, dir, dry_run = args$options$`dry-run`)
}

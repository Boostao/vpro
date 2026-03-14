herbarium_list_tables <- function(con) {
  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  if (!length(tables)) {
    return(character(0))
  }

  herb <- tables[grepl("(?i)_herbarium$", tables, perl = TRUE)]
  plain <- tables[tolower(tables) == "herbarium"]
  unique(c(plain, herb))
}

herbarium_table_to_base <- function(table_name) {
  nm <- trimws(as.character(table_name %||% ""))
  if (!nzchar(nm)) {
    return("")
  }
  sub("(?i)_herbarium$", "", nm, perl = TRUE)
}

herbarium_existing_bases <- function(con) {
  tables <- herbarium_list_tables(con)
  bases <- unique(vapply(tables, herbarium_table_to_base, character(1)))
  sort(bases[nzchar(bases) & !grepl("(?i)^usys", bases, perl = TRUE)])
}

herbarium_resolve_table <- function(con, selection) {
  pick <- trimws(as.character(selection %||% ""))
  if (!nzchar(pick)) {
    return("")
  }

  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  if (!length(tables)) {
    return("")
  }

  candidates <- unique(c(pick, paste0(pick, "_Herbarium")))
  for (candidate in candidates) {
    hit <- tables[tolower(tables) == tolower(candidate)]
    if (length(hit) > 0) {
      return(hit[[1]])
    }
  }

  ""
}

herbarium_read_records <- function(con, table_name) {
  if (!nzchar(table_name) || !DBI::dbExistsTable(con, table_name)) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  fields <- tolower(tryCatch(DBI::dbListFields(con, table_name), error = function(e) character(0)))
  if (!length(fields)) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  preferred <- c(
    "recid", "plotnumber", "species", "scientificnamerich", "_comments", "print",
    "habitat", "locationdescription", "specimenpreviousname", "collectors",
    "collectionnumber", "dateofcollection", "identifier", "flag01",
    "accessionnumber", "accessiondate", "permanentstoragelocation", "duplicatesentto",
    "generalremarks", "onloanto", "loandate", "provinceoforigin", "countryoforigin",
    "entryoperator", "entryoperatordate"
  )
  cols <- intersect(preferred, fields)
  sql <- paste(
    "SELECT", paste(cols, collapse = ", "),
    "FROM", as.character(DBI::dbQuoteIdentifier(con, table_name)),
    "ORDER BY recid"
  )
  tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data.frame(stringsAsFactors = FALSE))
}

herbarium_species_lookup <- function(con, code_value) {
  code_value <- trimws(as.character(code_value %||% ""))
  if (!nzchar(code_value)) {
    return(list(familycode = "", commonname = "", redbluelist = "", scientific = ""))
  }

  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  if (!length(tables)) {
    return(list(familycode = "", commonname = "", redbluelist = "", scientific = ""))
  }

  match_table <- function(candidates) {
    for (candidate in candidates) {
      hit <- tables[tolower(tables) == tolower(candidate)]
      if (length(hit) > 0) {
        return(hit[[1]])
      }
    }
    ""
  }

  spp_tbl <- match_table(c("lists.USysAllSpecs", "USysAllSpecs", "SppList", "SppListUnique"))
  att_tbl <- match_table(c("lists.USysSppAttributes", "USysSppAttributes", "USysSppAttributeSummary", "lists.USysSppAttributeSummary"))

  family <- ""
  common <- ""
  scientific <- ""
  redblue <- ""

  if (nzchar(spp_tbl)) {
    fields <- tolower(tryCatch(DBI::dbListFields(con, spp_tbl), error = function(e) character(0)))
    has <- function(x) x %in% fields

    code_col <- if (has("code")) "code" else if (has("species")) "species" else ""
    sci_col <- if (has("scientificname")) "scientificname" else if (has("scientificnamerich")) "scientificnamerich" else ""
    auth_col <- if (has("authority")) "authority" else ""
    fam_col <- if (has("familycode")) "familycode" else ""
    eng_col <- if (has("englishname")) "englishname" else if (has("commonname")) "commonname" else ""
    type_col <- if (has("codetype")) "codetype" else ""

    if (nzchar(code_col)) {
      select_cols <- c(code_col)
      if (nzchar(fam_col)) select_cols <- c(select_cols, fam_col)
      if (nzchar(eng_col)) select_cols <- c(select_cols, eng_col)
      if (nzchar(sci_col)) select_cols <- c(select_cols, sci_col)
      if (nzchar(auth_col)) select_cols <- c(select_cols, auth_col)
      if (nzchar(type_col)) select_cols <- c(select_cols, type_col)

      sql <- paste(
        "SELECT", paste(unique(select_cols), collapse = ", "),
        "FROM", as.character(DBI::dbQuoteIdentifier(con, spp_tbl)),
        "WHERE", code_col, "= ?",
        if (nzchar(type_col)) "AND COALESCE(codetype,'') <> 'S'" else "",
        "LIMIT 1"
      )

      row <- tryCatch(DBI::dbGetQuery(con, sql, list(code_value)), error = function(e) data.frame())
      if (nrow(row) > 0) {
        nms <- tolower(names(row))
        val <- function(col) {
          idx <- which(nms == col)
          if (!length(idx)) return("")
          as.character(row[[idx[[1]]]][[1]] %||% "")
        }
        family <- if (nzchar(fam_col)) val(fam_col) else ""
        common <- if (nzchar(eng_col)) val(eng_col) else ""
        sci <- if (nzchar(sci_col)) val(sci_col) else ""
        auth <- if (nzchar(auth_col)) val(auth_col) else ""
        scientific <- trimws(paste(sci, auth))
      }
    }
  }

  if (nzchar(att_tbl)) {
    fields <- tolower(tryCatch(DBI::dbListFields(con, att_tbl), error = function(e) character(0)))
    if ("code" %in% fields && "redbluelist" %in% fields) {
      sql <- paste(
        "SELECT redbluelist FROM", as.character(DBI::dbQuoteIdentifier(con, att_tbl)),
        "WHERE code = ? LIMIT 1"
      )
      row <- tryCatch(DBI::dbGetQuery(con, sql, list(code_value)), error = function(e) data.frame())
      if (nrow(row) > 0) {
        redblue <- as.character(row$redbluelist[[1]] %||% "")
      }
    }
  }

  list(familycode = family, commonname = common, redbluelist = redblue, scientific = scientific)
}

mod_herbarium_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
        shiny::tags$div(
          shiny::tags$div(class = "fw-semibold", "Herbarium - Add/Edit Data"),
          shiny::tags$div(class = "small text-muted", "Access parity block: frmHerbarium (ribbon sb02btn06)")
        ),
        shiny::actionButton(ns("btnClose"), "Close", class = "btn btn-outline-danger btn-sm")
      )
    ),
    bslib::card_body(
      bslib::layout_columns(
        shiny::selectInput(ns("HerbariumList"), "Select/Create Herbarium", choices = character(0)),
        shiny::textInput(ns("filter_species"), "Species Filter", placeholder = "e.g. ABIE"),
        shiny::actionButton(ns("btnSetReportRecsFromFilter"), "Set Report Records From Filter", class = "btn btn-outline-secondary"),
        shiny::actionButton(ns("btnPrintLabel"), "Print Label", class = "btn btn-outline-secondary"),
        col_widths = c(4, 3, 3, 2)
      ),
      DT::DTOutput(ns("herb_table")),
      bslib::layout_columns(
        shiny::textInput(ns("RecID"), "RecID"),
        shiny::textInput(ns("Code"), "Code"),
        shiny::textInput(ns("ScientificName"), "Scientific Name"),
        shiny::actionButton(ns("btnGetScientific"), "Get Scientific Name", class = "btn btn-outline-secondary"),
        shiny::actionButton(ns("btnSave"), "Save Record", class = "btn btn-primary"),
        col_widths = c(2, 2, 4, 2, 2)
      ),
      bslib::navset_tab(
        id = ns("herb_tabs"),
        bslib::nav_panel(
          "General",
          bslib::layout_columns(
            shiny::textInput(ns("FamilyCode"), "Family Code"),
            shiny::textInput(ns("CommonName"), "Common Name"),
            shiny::textInput(ns("RedBlueList"), "R/B List"),
            shiny::textInput(ns("PlotNumber"), "PlotNumber"),
            col_widths = c(3, 3, 3, 3)
          ),
          bslib::layout_columns(
            shiny::textInput(ns("Habitat"), "Habitat"),
            shiny::textInput(ns("LocationDescription"), "Location Description"),
            shiny::textInput(ns("SpecimenPreviousName"), "Original Label Name"),
            shiny::textInput(ns("Collectors"), "Collector"),
            col_widths = c(3, 3, 3, 3)
          ),
          bslib::layout_columns(
            shiny::textInput(ns("CollectionNumber"), "Collection Number"),
            shiny::textInput(ns("DateOfCollection"), "Date of Collection"),
            shiny::textInput(ns("Identifier"), "Determiner"),
            shiny::checkboxInput(ns("Flag01"), "Flag", value = FALSE),
            col_widths = c(3, 3, 3, 3)
          ),
          shiny::textAreaInput(ns("Comments"), "Comments", rows = 3)
        ),
        bslib::nav_panel(
          "Details",
          bslib::layout_columns(
            shiny::textInput(ns("AccessionNumber"), "Accession Number"),
            shiny::textInput(ns("AccessionDate"), "Accession Date"),
            shiny::textInput(ns("PermanentStorageLocation"), "Permanent Storage Location"),
            shiny::textInput(ns("DuplicateSentTo"), "Duplicate Sent To"),
            col_widths = c(3, 3, 3, 3)
          ),
          bslib::layout_columns(
            shiny::textInput(ns("GeneralRemarks"), "General Remarks"),
            shiny::textInput(ns("OnLoanTo"), "On Loan To"),
            shiny::textInput(ns("LoanDate"), "Loan Date"),
            shiny::textInput(ns("ProvinceOfOrigin"), "Province of Origin"),
            col_widths = c(3, 3, 3, 3)
          ),
          bslib::layout_columns(
            shiny::textInput(ns("CountryOfOrigin"), "Country of Origin"),
            shiny::textInput(ns("EntryOperator"), "Entry Operator"),
            shiny::textInput(ns("EntryOperatorDate"), "Entry Operator Date"),
            col_widths = c(4, 4, 4)
          )
        )
      ),
      shiny::textOutput(ns("status"))
    )
  )
}

mod_herbarium_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    rv <- shiny::reactiveValues(
      herb_table = "",
      status = "",
      loaded = data.frame(stringsAsFactors = FALSE),
      requested_special = ""
    )

    nz <- function(x) {
      x <- trimws(as.character(x %||% ""))
      if (!nzchar(x)) "" else x
    }

    qident <- function(name) as.character(DBI::dbQuoteIdentifier(con, name))

    current_herbarium_base <- function() {
      herbarium_table_to_base(rv$herb_table)
    }

    set_status <- function(text) {
      rv$status <- text
    }

    refresh_herbarium_choices <- function(selected = NULL) {
      tables <- herbarium_list_tables(con)
      bases <- herbarium_existing_bases(con)
      choices <- c("Attach", "New", "Unattach", "--------------------------------------", bases)
      if (!length(choices)) {
        choices <- c("Attach", "New", "Unattach", "--------------------------------------")
      }
      target <- nz(selected)
      if (!nzchar(target) || !(target %in% choices)) {
        target <- if (length(bases)) bases[[1]] else ""
      }
      shiny::updateSelectInput(session, "HerbariumList", choices = choices, selected = target)
      rv$herb_table <- herbarium_resolve_table(con, target)
      rv$loaded <- herbarium_read_records(con, rv$herb_table)
    }

    filtered_rows <- shiny::reactive({
      dat <- rv$loaded
      if (!nrow(dat)) {
        return(dat)
      }
      patt <- nz(input$filter_species)
      if (nzchar(patt) && "species" %in% names(dat)) {
        keep <- grepl(patt, as.character(dat$species %||% ""), ignore.case = TRUE)
        dat <- dat[keep, , drop = FALSE]
      }
      dat
    })

    output$herb_table <- DT::renderDT({
      dat <- filtered_rows()
      cols <- intersect(c("recid", "plotnumber", "species", "scientificnamerich", "familycode", "commonname", "redbluelist", "print"), names(dat))
      DT::datatable(dat[, cols, drop = FALSE], rownames = FALSE, selection = "single", options = list(pageLength = 12, scrollX = TRUE))
    })

    output$status <- shiny::renderText(rv$status)

    load_selected_record <- function() {
      dat <- filtered_rows()
      idx <- input$herb_table_rows_selected %||% integer(0)
      if (!length(idx) || nrow(dat) < idx[[1]]) {
        return(invisible(NULL))
      }
      row <- dat[idx[[1]], , drop = FALSE]

      rv_val <- function(col) {
        if (!(col %in% names(row))) {
          return("")
        }
        nz(row[[col]][[1]])
      }

      updateTextInput(session, "RecID", value = rv_val("recid"))
      updateTextInput(session, "Code", value = rv_val("species"))
      updateTextInput(session, "ScientificName", value = rv_val("scientificnamerich"))
      updateTextInput(session, "FamilyCode", value = "")
      updateTextInput(session, "CommonName", value = "")
      updateTextInput(session, "RedBlueList", value = "")
      updateTextInput(session, "Habitat", value = rv_val("habitat"))
      updateTextInput(session, "LocationDescription", value = rv_val("locationdescription"))
      updateTextInput(session, "SpecimenPreviousName", value = rv_val("specimenpreviousname"))
      updateTextInput(session, "Collectors", value = rv_val("collectors"))
      updateTextInput(session, "CollectionNumber", value = rv_val("collectionnumber"))
      updateTextInput(session, "DateOfCollection", value = rv_val("dateofcollection"))
      updateTextInput(session, "Identifier", value = rv_val("identifier"))
      updateTextAreaInput(session, "Comments", value = rv_val("_comments"))
      flag_val <- if ("flag01" %in% names(row)) row$flag01[[1]] else FALSE
      updateCheckboxInput(session, "Flag01", value = isTRUE(as.logical(flag_val)))
      updateTextInput(session, "PlotNumber", value = rv_val("plotnumber"))

      updateTextInput(session, "AccessionNumber", value = rv_val("accessionnumber"))
      updateTextInput(session, "AccessionDate", value = rv_val("accessiondate"))
      updateTextInput(session, "PermanentStorageLocation", value = rv_val("permanentstoragelocation"))
      updateTextInput(session, "DuplicateSentTo", value = rv_val("duplicatesentto"))
      updateTextInput(session, "GeneralRemarks", value = rv_val("generalremarks"))
      updateTextInput(session, "OnLoanTo", value = rv_val("onloanto"))
      updateTextInput(session, "LoanDate", value = rv_val("loandate"))
      updateTextInput(session, "ProvinceOfOrigin", value = rv_val("provinceoforigin"))
      updateTextInput(session, "CountryOfOrigin", value = rv_val("countryoforigin"))
      updateTextInput(session, "EntryOperator", value = rv_val("entryoperator"))
      updateTextInput(session, "EntryOperatorDate", value = rv_val("entryoperatordate"))

      info <- herbarium_species_lookup(con, nz(input$Code))
      if (nzchar(info$familycode)) updateTextInput(session, "FamilyCode", value = info$familycode)
      if (nzchar(info$commonname)) updateTextInput(session, "CommonName", value = info$commonname)
      if (nzchar(info$redbluelist)) updateTextInput(session, "RedBlueList", value = info$redbluelist)
    }

    observeEvent(TRUE, {
      state$CurrForm <- "frmHerbarium"
      state$sysCurrForm <- "frmHerbarium"
      set_pref(con, "Current", "DataFormName", "frmHerbarium")

      pref <- nz(get_pref(con, "Current", "CurrHerbarium", default = "Sample"))
      refresh_herbarium_choices(pref)
      set_status("Loaded Herbarium (frmHerbarium).")
    }, once = TRUE)

    observeEvent(input$HerbariumList, {
      selected <- nz(input$HerbariumList)

      if (selected %in% c("--------------------------------------", "Attach", "Unattach", "New")) {
        rv$requested_special <- selected
        prev <- nz(get_pref(con, "Current", "CurrHerbarium", default = current_herbarium_base()))
        if (nzchar(prev)) {
          shiny::updateSelectInput(session, "HerbariumList", selected = prev)
        }

        if (identical(selected, "Attach")) {
          shiny::showModal(shiny::modalDialog(
            title = "Attach Herbarium Table",
            shiny::textInput(session$ns("attach_db_path"), "Source DuckDB Path", value = ""),
            shiny::textInput(session$ns("attach_prefix"), "Herbarium Prefix", value = ""),
            shiny::checkboxInput(session$ns("attach_replace_existing"), "Replace existing table when present", value = FALSE),
            easyClose = TRUE,
            footer = shiny::tagList(
              shiny::modalButton("Cancel"),
              shiny::actionButton(session$ns("btn_confirm_attach_herbarium"), "Attach", class = "btn btn-primary")
            )
          ))
        } else if (identical(selected, "Unattach")) {
          choices <- herbarium_existing_bases(con)
          choices <- choices[!tolower(choices) %in% c("sample")]
          if (!length(choices)) {
            set_status("No detachable herbarium tables found.")
          } else {
            shiny::showModal(shiny::modalDialog(
              title = "Unattach Herbarium Table",
              shiny::selectInput(session$ns("unattach_prefix"), "Select Herbarium Prefix", choices = choices, selected = choices[[1]]),
              easyClose = TRUE,
              footer = shiny::tagList(
                shiny::modalButton("Cancel"),
                shiny::actionButton(session$ns("btn_confirm_unattach_herbarium"), "Unattach", class = "btn btn-danger")
              )
            ))
          }
        } else if (identical(selected, "New")) {
          bases <- herbarium_existing_bases(con)
          current_base <- current_herbarium_base()
          default_template <- if (nzchar(current_base) && current_base %in% bases) current_base else if ("Sample" %in% bases) "Sample" else if (length(bases)) bases[[1]] else "Sample"
          shiny::showModal(shiny::modalDialog(
            title = "Create Herbarium Table",
            shiny::textInput(session$ns("new_prefix"), "New Herbarium Prefix", value = ""),
            shiny::selectInput(session$ns("new_template_prefix"), "Template Prefix", choices = unique(c(default_template, bases)), selected = default_template),
            shiny::checkboxInput(session$ns("new_overwrite"), "Overwrite if exists", value = FALSE),
            easyClose = TRUE,
            footer = shiny::tagList(
              shiny::modalButton("Cancel"),
              shiny::actionButton(session$ns("btn_confirm_create_herbarium"), "Create", class = "btn btn-primary")
            )
          ))
        } else {
          set_status("Separator selected; keeping current herbarium table.")
        }
        return()
      }

      set_pref(con, "Current", "CurrHerbarium", selected)
      state$CurrHerbarium <- selected
      rv$herb_table <- herbarium_resolve_table(con, selected)
      rv$loaded <- herbarium_read_records(con, rv$herb_table)
      set_status(sprintf("Using herbarium table: %s", rv$herb_table))
    }, ignoreInit = TRUE)

    observeEvent(input$btn_confirm_attach_herbarium, {
      db_path <- nz(input$attach_db_path)
      prefix <- nz(input$attach_prefix)
      replace_existing <- isTRUE(input$attach_replace_existing)

      ok <- tryCatch({
        attach_prefixed_table(
          con = con,
          db_path = db_path,
          prefix = prefix,
          suffix = "_Herbarium",
          replace_existing = replace_existing,
          alias = "tmp_attach_herbarium"
        )
        TRUE
      }, error = function(e) {
        set_status(sprintf("Attach failed: %s", e$message))
        FALSE
      })

      shiny::removeModal()
      if (!ok) {
        return()
      }

      refresh_herbarium_choices(prefix)
      set_pref(con, "Current", "CurrHerbarium", prefix)
      state$CurrHerbarium <- prefix
      set_status(sprintf("Attached herbarium table: %s_Herbarium", prefix))
    })

    observeEvent(input$btn_confirm_create_herbarium, {
      prefix <- nz(input$new_prefix)
      template_prefix <- nz(input$new_template_prefix)
      overwrite <- isTRUE(input$new_overwrite)

      ok <- tryCatch({
        create_prefixed_table_from_template(
          con = con,
          prefix = prefix,
          suffix = "_Herbarium",
          template_prefix = if (nzchar(template_prefix)) template_prefix else "Sample",
          overwrite = overwrite
        )
        TRUE
      }, error = function(e) {
        set_status(sprintf("Create failed: %s", e$message))
        FALSE
      })

      shiny::removeModal()
      if (!ok) {
        return()
      }

      refresh_herbarium_choices(prefix)
      set_pref(con, "Current", "CurrHerbarium", prefix)
      state$CurrHerbarium <- prefix
      set_status(sprintf("Created herbarium table: %s_Herbarium", prefix))
    })

    observeEvent(input$btn_confirm_unattach_herbarium, {
      prefix <- nz(input$unattach_prefix)

      removed <- tryCatch({
        unattach_prefixed_table(
          con = con,
          prefix = prefix,
          suffix = "_Herbarium",
          protected_prefixes = c("Sample")
        )
      }, error = function(e) {
        set_status(sprintf("Unattach failed: %s", e$message))
        NULL
      })

      shiny::removeModal()
      if (is.null(removed)) {
        return()
      }

      bases <- herbarium_existing_bases(con)
      fallback <- if ("Sample" %in% bases) "Sample" else if (length(bases)) bases[[1]] else ""
      refresh_herbarium_choices(fallback)
      if (nzchar(fallback)) {
        set_pref(con, "Current", "CurrHerbarium", fallback)
        state$CurrHerbarium <- fallback
      }
      set_status(sprintf("Unattached herbarium table: %s", removed %||% paste0(prefix, "_Herbarium")))
    })

    observeEvent(input$herb_table_rows_selected, {
      load_selected_record()
    }, ignoreInit = TRUE)

    observeEvent(input$Code, {
      info <- herbarium_species_lookup(con, nz(input$Code))
      updateTextInput(session, "FamilyCode", value = nz(info$familycode))
      updateTextInput(session, "CommonName", value = nz(info$commonname))
      updateTextInput(session, "RedBlueList", value = nz(info$redbluelist))
    }, ignoreInit = TRUE)

    observeEvent(input$btnGetScientific, {
      info <- herbarium_species_lookup(con, nz(input$Code))
      if (!nzchar(info$scientific)) {
        set_status("No scientific name found for current code.")
        return()
      }

      current <- nz(input$ScientificName)
      if (!nzchar(current)) {
        updateTextInput(session, "ScientificName", value = info$scientific)
        set_status("Scientific name populated from species table.")
      } else {
        shiny::showModal(shiny::modalDialog(
          title = "VPro",
          sprintf("Replace Scientific Name with: %s ?", info$scientific),
          easyClose = TRUE,
          footer = shiny::tagList(
            shiny::modalButton("No"),
            shiny::actionButton(session$ns("btn_confirm_replace_scientific"), "Yes", class = "btn btn-primary")
          )
        ))
      }
    })

    observeEvent(input$btn_confirm_replace_scientific, {
      info <- herbarium_species_lookup(con, nz(input$Code))
      if (nzchar(info$scientific)) {
        updateTextInput(session, "ScientificName", value = info$scientific)
        set_status("Scientific name replaced.")
      }
      shiny::removeModal()
    })

    observeEvent(input$btnSave, {
      req(nzchar(rv$herb_table), DBI::dbExistsTable(con, rv$herb_table))
      recid <- suppressWarnings(as.integer(nz(input$RecID)))
      if (is.na(recid)) {
        set_status("Select a record before saving.")
        return()
      }

      fields <- list(
        species = nz(input$Code),
        scientificnamerich = nz(input$ScientificName),
        habitat = nz(input$Habitat),
        locationdescription = nz(input$LocationDescription),
        specimenpreviousname = nz(input$SpecimenPreviousName),
        collectors = nz(input$Collectors),
        collectionnumber = nz(input$CollectionNumber),
        dateofcollection = nz(input$DateOfCollection),
        identifier = nz(input$Identifier),
        `_comments` = nz(input$Comments),
        flag01 = as.integer(isTRUE(input$Flag01)),
        plotnumber = nz(input$PlotNumber),
        accessionnumber = nz(input$AccessionNumber),
        accessiondate = nz(input$AccessionDate),
        permanentstoragelocation = nz(input$PermanentStorageLocation),
        duplicatesentto = nz(input$DuplicateSentTo),
        generalremarks = nz(input$GeneralRemarks),
        onloanto = nz(input$OnLoanTo),
        loandate = nz(input$LoanDate),
        provinceoforigin = nz(input$ProvinceOfOrigin),
        countryoforigin = nz(input$CountryOfOrigin),
        entryoperator = nz(input$EntryOperator),
        entryoperatordate = nz(input$EntryOperatorDate)
      )

      existing <- tolower(tryCatch(DBI::dbListFields(con, rv$herb_table), error = function(e) character(0)))
      fields <- fields[names(fields) %in% existing]
      if (!length(fields)) {
        set_status("No writable fields found for selected herbarium table.")
        return()
      }

      set_clause <- paste(sprintf("%s = ?", vapply(names(fields), qident, character(1))), collapse = ", ")
      sql <- paste(
        "UPDATE", qident(rv$herb_table),
        "SET", set_clause,
        "WHERE recid = ?"
      )

      ok <- tryCatch({
        DBI::dbExecute(con, sql, c(unname(fields), list(recid)))
        TRUE
      }, error = function(e) FALSE)

      if (!ok) {
        set_status("Save failed for herbarium record.")
        return()
      }

      rv$loaded <- herbarium_read_records(con, rv$herb_table)
      set_status(sprintf("Saved record %s.", recid))
    })

    observeEvent(input$btnSetReportRecsFromFilter, {
      req(nzchar(rv$herb_table), DBI::dbExistsTable(con, rv$herb_table))
      dat <- filtered_rows()
      if (!nrow(dat) || !"recid" %in% names(dat)) {
        set_status("No records to list.")
        return()
      }

      tryCatch(DBI::dbExecute(con, paste("UPDATE", qident(rv$herb_table), "SET print = FALSE")), error = function(e) NULL)

      recids <- unique(as.integer(dat$recid))
      recids <- recids[!is.na(recids)]
      if (!length(recids)) {
        set_status("No records to list.")
        return()
      }

      sql <- paste("UPDATE", qident(rv$herb_table), "SET print = TRUE WHERE recid = ?")
      for (idv in recids) {
        tryCatch(DBI::dbExecute(con, sql, list(idv)), error = function(e) NULL)
      }

      rv$loaded <- herbarium_read_records(con, rv$herb_table)
      set_status(sprintf("Marked %d records for print.", length(recids)))
    })

    observeEvent(input$btnPrintLabel, {
      req(nzchar(rv$herb_table), DBI::dbExistsTable(con, rv$herb_table))

      has_print <- "print" %in% tolower(tryCatch(DBI::dbListFields(con, rv$herb_table), error = function(e) character(0)))
      if (!has_print) {
        set_status("Selected herbarium table has no print flag column.")
        return()
      }

      label_rows <- tryCatch(
        DBI::dbGetQuery(
          con,
          paste(
            "SELECT recid, plotnumber, species, scientificnamerich, collectionnumber, dateofcollection, collectors, locationdescription",
            "FROM", qident(rv$herb_table),
            "WHERE COALESCE(print, FALSE) = TRUE",
            "ORDER BY recid"
          )
        ),
        error = function(e) data.frame(stringsAsFactors = FALSE)
      )

      if (!nrow(label_rows)) {
        set_status("No records marked for print. Use 'Set Report Records From Filter' first.")
        return()
      }

      cards <- lapply(seq_len(nrow(label_rows)), function(i) {
        row <- label_rows[i, , drop = FALSE]
        shiny::tags$div(
          style = "border:1px solid #ddd; border-radius:4px; padding:10px; margin-bottom:10px; page-break-inside: avoid;",
          shiny::tags$div(style = "font-weight:700;", paste0("Specimen ", row$recid[[1]] %||% "")),
          shiny::tags$div(paste0("Species: ", row$species[[1]] %||% "")),
          shiny::tags$div(paste0("Scientific: ", row$scientificnamerich[[1]] %||% "")),
          shiny::tags$div(paste0("Plot: ", row$plotnumber[[1]] %||% "")),
          shiny::tags$div(paste0("Collection #: ", row$collectionnumber[[1]] %||% "")),
          shiny::tags$div(paste0("Date: ", row$dateofcollection[[1]] %||% "")),
          shiny::tags$div(paste0("Collector: ", row$collectors[[1]] %||% "")),
          shiny::tags$div(paste0("Location: ", row$locationdescription[[1]] %||% ""))
        )
      })

      shiny::showModal(shiny::modalDialog(
        title = "Herbarium Label Preview (rptSmithers8in1 equivalent)",
        shiny::tags$div(style = "max-height:65vh; overflow:auto;", cards),
        easyClose = TRUE,
        footer = shiny::tagList(
          shiny::modalButton("Close"),
          shiny::actionButton(session$ns("btn_print_labels_now"), "Print", class = "btn btn-primary")
        ),
        size = "l"
      ))
      set_status(sprintf("Prepared %d herbarium labels for preview.", nrow(label_rows)))
    })

    observeEvent(input$btn_print_labels_now, {
      shiny::removeModal()
      session$sendCustomMessage("vpro-print-window", list())
      set_status("Sent label preview to browser print dialog.")
    })

    observeEvent(input$btnClose, {
      bslib::nav_select("main_tabs", "Vegetation", session = session$parent)
    })
  })
}

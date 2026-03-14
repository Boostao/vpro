combine_species_list_lump_tables <- function(con) {
  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  if (length(tables) == 0) {
    return(character(0))
  }

  lump_like <- tables[grepl("(?i)_lump$", tables, perl = TRUE)]
  if (any(tolower(tables) == "lump")) {
    lump_like <- unique(c(lump_like, tables[tolower(tables) == "lump"]))
  }

  sort(unique(lump_like))
}

combine_species_resolve_lump_table <- function(con, selection) {
  selection <- trimws(as.character(selection %||% ""))
  if (!nzchar(selection) || identical(tolower(selection), "none")) {
    return("")
  }

  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  if (length(tables) == 0) {
    return("")
  }

  candidates <- unique(c(selection, paste0(selection, "_Lump")))
  for (candidate in candidates) {
    hit <- tables[tolower(tables) == tolower(candidate)]
    if (length(hit) > 0) {
      return(hit[[1]])
    }
  }

  ""
}

combine_species_lump_column_map <- function(con, table_name) {
  if (!nzchar(table_name)) {
    return(NULL)
  }

  schema <- tryCatch(DBI::dbGetQuery(con, paste("PRAGMA table_info('", table_name, "')", sep = "")), error = function(e) data.frame())
  if (!nrow(schema) || !"name" %in% names(schema)) {
    return(NULL)
  }

  cols <- schema$name
  cols_lower <- tolower(cols)

  pick_col <- function(candidates) {
    idx <- match(tolower(candidates), cols_lower)
    idx <- idx[!is.na(idx)]
    if (length(idx) == 0) "" else cols[[idx[[1]]]]
  }

  lump_col <- pick_col(c("lumpcode", "lump_code"))
  spp_col <- pick_col(c("sppcode", "spp_code", "code"))
  use_col <- pick_col(c("_use", "use", "active"))

  if (!nzchar(lump_col) || !nzchar(spp_col)) {
    return(NULL)
  }

  list(lump = lump_col, spp = spp_col, use = use_col)
}

combine_species_species_fields <- function(con) {
  schema <- tryCatch(DBI::dbGetQuery(con, "PRAGMA table_info('lists.USysAllSpecs')"), error = function(e) data.frame())
  if (!nrow(schema)) {
    return(c("code", "scientificname", "englishname"))
  }
  as.character(schema$name)
}

mod_combine_species_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center flex-wrap gap-2",
        shiny::tags$div(
          shiny::tags$div(class = "fw-semibold", "VPro Combine Species Codes"),
          shiny::tags$div(class = "small text-muted", "Access parity block: USysLumpMaster (ribbon sb01btn01b)")
        ),
        shiny::actionButton(ns("btnClose"), "Close", class = "btn btn-outline-danger btn-sm")
      )
    ),
    bslib::card_body(
      bslib::layout_columns(
        shiny::selectInput(ns("cmbLump"), "Lump table:", choices = "None", selected = "None"),
        shiny::textInput(ns("txtSaveAs"), "Save As (new base name)", placeholder = "e.g. MyProject"),
        shiny::actionButton(ns("btnSaveAs"), "Save As...", class = "btn btn-outline-secondary"),
        shiny::actionButton(ns("btnOpenTable"), "Table View", class = "btn btn-outline-secondary"),
        shiny::actionButton(ns("btnHelp"), "Hint", class = "btn btn-outline-secondary"),
        col_widths = c(3, 3, 2, 2, 2)
      ),
      bslib::layout_columns(
        shiny::selectInput(ns("FieldName"), "Field", choices = NULL),
        shiny::selectInput(ns("Like"), "Like", choices = c("=" = "=", ">" = ">", ">=" = ">=", "<" = "<", "<=" = "<=", "<>" = "<>", "Like" = "LIKE"), selected = "LIKE"),
        shiny::selectizeInput(ns("cmbCriteria"), "Criteria", choices = character(0), selected = character(0), options = list(create = TRUE, placeholder = "Enter criteria")),
        shiny::textInput(ns("SppPattern"), "Pattern"),
        shiny::actionButton(ns("btnLoadList"), "Reload", class = "btn btn-primary"),
        col_widths = c(3, 2, 3, 2, 2)
      ),
      bslib::layout_columns(
        bslib::card(
          bslib::card_header("Species List"),
          DT::DTOutput(ns("species_table")),
          shiny::tags$div(
            id = ns("species_drag_payload"),
            class = "btn btn-outline-primary btn-sm mt-2",
            draggable = "true",
            title = "Drag selected species onto a lump in the LumpTree",
            "Drag selected species to LumpTree"
          ),
          shiny::textInput(ns("selectedSpeciesCodes"), NULL, value = "", width = "1px")
        ),
        bslib::card(
          bslib::card_header(
            shiny::tags$div(
              class = "d-flex justify-content-between align-items-center",
              shiny::tags$span("Lump Mappings"),
              shiny::actionButton(ns("btnRefreshTree"), "Refresh", class = "btn btn-outline-secondary btn-sm")
            )
          ),
          shiny::tags$div(style = "height: 260px; overflow:auto; border: 1px solid #d9d9d9; border-radius: 4px; padding: 6px;", shinyTree::shinyTree(ns("lump_tree"), dragAndDrop = TRUE)),
          shiny::tags$div(
            id = ns("lump_tree_menu"),
            class = "vpro-lump-menu",
            style = "display:none; position:fixed; z-index:1055; background:#fff; border:1px solid #c8c8c8; border-radius:4px; box-shadow:0 2px 10px rgba(0,0,0,0.15); padding:4px;",
            shiny::tags$button(type = "button", class = "btn btn-sm btn-light w-100 text-start", `data-action` = "toggle", "Toggle Yes/No"),
            shiny::tags$button(type = "button", class = "btn btn-sm btn-light w-100 text-start", `data-action` = "set_yes", "Set All To Yes"),
            shiny::tags$button(type = "button", class = "btn btn-sm btn-light w-100 text-start", `data-action` = "set_no", "Set All To No")
          ),
          shiny::tags$style(sprintf("#%s{display:none;} .vpro-lump-menu button{border:none;} .vpro-lump-menu button:hover{background:#f3f7ff;}", ns("selectedSpeciesCodes"))),
          shiny::tags$script(shiny::HTML(sprintf("(function(){
            var treeId = '%s';
            var menuId = '%s';
            var dragId = '%s';
            var speciesInputId = '%s';
            var contextInput = '%s';
            var dblInput = '%s';
            var dropInput = '%s';

            function hideMenu(){
              var menu = document.getElementById(menuId);
              if (menu) menu.style.display = 'none';
            }

            function bindTreeEvents(){
              var treeEl = document.getElementById(treeId);
              if (!treeEl || !window.jQuery) return;
              var $tree = window.jQuery(treeEl);
              if ($tree.data('vproLumpBound')) return;
              $tree.data('vproLumpBound', true);

              $tree.on('dblclick.vpro', '.jstree-anchor', function(e){
                var inst = $tree.jstree(true);
                if (!inst) return;
                var node = inst.get_node(this);
                if (!node) return;
                Shiny.setInputValue(dblInput, { id: node.id, text: node.text, ts: Date.now() }, {priority:'event'});
              });

              $tree.on('contextmenu.vpro', '.jstree-anchor', function(e){
                e.preventDefault();
                var inst = $tree.jstree(true);
                if (!inst) return;
                var node = inst.get_node(this);
                if (!node) return;
                var menu = document.getElementById(menuId);
                if (!menu) return;
                menu.dataset.nodeId = node.id;
                menu.style.left = e.clientX + 'px';
                menu.style.top = e.clientY + 'px';
                menu.style.display = 'block';
              });

              $tree.on('dragover.vpro', '.jstree-anchor', function(e){
                e.preventDefault();
              });

              $tree.on('drop.vpro', '.jstree-anchor', function(e){
                e.preventDefault();
                var inst = $tree.jstree(true);
                if (!inst) return;
                var node = inst.get_node(this);
                if (!node) return;
                var speciesEl = document.getElementById(speciesInputId);
                var csv = speciesEl ? speciesEl.value : '';
                Shiny.setInputValue(dropInput, { id: node.id, codes: csv, ts: Date.now() }, {priority:'event'});
              });
            }

            function bindMenuEvents(){
              var menu = document.getElementById(menuId);
              if (!menu || menu.dataset.vproMenuBound === '1') return;
              menu.dataset.vproMenuBound = '1';
              menu.addEventListener('click', function(e){
                var btn = e.target.closest('button[data-action]');
                if (!btn) return;
                var nodeId = menu.dataset.nodeId || '';
                var action = btn.getAttribute('data-action') || '';
                Shiny.setInputValue(contextInput, { id: nodeId, action: action, ts: Date.now() }, {priority:'event'});
                hideMenu();
              });
              document.addEventListener('click', function(e){
                if (!e.target.closest('#' + menuId)) hideMenu();
              });
            }

            function bindDragSource(){
              var dragEl = document.getElementById(dragId);
              if (!dragEl || dragEl.dataset.vproDragBound === '1') return;
              dragEl.dataset.vproDragBound = '1';
              dragEl.addEventListener('dragstart', function(e){
                var speciesEl = document.getElementById(speciesInputId);
                var csv = speciesEl ? speciesEl.value : '';
                e.dataTransfer.setData('text/plain', csv);
              });
            }

            bindMenuEvents();
            bindDragSource();
            bindTreeEvents();

            var obs = new MutationObserver(function(){ bindTreeEvents(); bindDragSource(); });
            obs.observe(document.body, { childList: true, subtree: true });
          })();", ns("lump_tree"), ns("lump_tree_menu"), ns("species_drag_payload"), ns("selectedSpeciesCodes"), ns("lump_tree_context"), ns("lump_tree_dblclick"), ns("lump_tree_drop")))),
          bslib::layout_columns(
            shiny::textInput(ns("new_lump_code"), "Lump Code"),
            shiny::actionButton(ns("btnAddMapping"), "Add Selected Species", class = "btn btn-success"),
            shiny::actionButton(ns("btnToggleUse"), "Toggle Use", class = "btn btn-outline-secondary"),
            shiny::actionButton(ns("btnDeleteMapping"), "Delete Selected", class = "btn btn-outline-danger"),
            col_widths = c(4, 3, 2, 3)
          ),
          DT::DTOutput(ns("lump_table"))
        ),
        col_widths = c(6, 6)
      ),
      shiny::tags$div(class = "small text-muted", "Note: VPro lump lists are no longer restricted to unique codes. Use accordingly."),
      shiny::textOutput(ns("status"))
    )
  )
}

mod_combine_species_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    rv <- shiny::reactiveValues(
      lump_table = "",
      colmap = NULL,
      status = "",
      lump_tick = 0L,
      species_tick = 0L
    )

    normalize_text <- function(value) {
      value <- trimws(as.character(value %||% ""))
      if (!nzchar(value)) "" else value
    }

    set_status <- function(text) {
      rv$status <- text
    }

    bump_lump_tick <- function() {
      rv$lump_tick <- as.integer(rv$lump_tick %||% 0L) + 1L
    }

    bump_species_tick <- function() {
      rv$species_tick <- as.integer(rv$species_tick %||% 0L) + 1L
    }

    qident <- function(name) {
      as.character(DBI::dbQuoteIdentifier(con, name))
    }

    parse_tree_id <- function(node_id) {
      parts <- strsplit(normalize_text(node_id), "::", fixed = TRUE)[[1]]
      if (length(parts) >= 2 && identical(parts[[1]], "lump")) {
        return(list(type = "lump", lump = parts[[2]], spp = ""))
      }
      if (length(parts) >= 3 && identical(parts[[1]], "spp")) {
        return(list(type = "spp", lump = parts[[2]], spp = parts[[3]]))
      }
      list(type = "", lump = "", spp = "")
    }

    build_lump_tree <- function(rows) {
      if (!nrow(rows)) {
        return(list("No lump mappings" = ""))
      }

      rows$lumpcode <- as.character(rows$lumpcode %||% "")
      rows$sppcode <- as.character(rows$sppcode %||% "")
      rows$in_use <- suppressWarnings(as.integer(rows$in_use %||% 1L))
      rows <- rows[nzchar(rows$lumpcode), , drop = FALSE]
      if (!nrow(rows)) {
        return(list("No lump mappings" = ""))
      }

      tree <- list()
      lumps <- sort(unique(rows$lumpcode))
      for (lump in lumps) {
        chunk <- rows[rows$lumpcode == lump, , drop = FALSE]
        children <- list()
        if (nrow(chunk) == 0) {
          children[["(empty)"]] <- structure("", stid = paste0("spp::", lump, "::"))
        } else {
          base_labels <- ifelse(nzchar(chunk$sppcode), paste0(chunk$sppcode, " [", ifelse(chunk$in_use == 1L, "Y", "N"), "]"), "(null spp)")
          labels <- make.unique(base_labels, sep = " #")
          for (i in seq_len(nrow(chunk))) {
            children[[labels[[i]]]] <- structure("", stid = paste0("spp::", lump, "::", chunk$sppcode[[i]]))
          }
        }
        tree[[lump]] <- structure(children, stopened = TRUE, stid = paste0("lump::", lump))
      }
      tree
    }

    as_lump_base <- function(table_name) {
      nm <- normalize_text(table_name)
      if (!nzchar(nm)) {
        return("")
      }
      sub("(?i)_lump$", "", nm, perl = TRUE)
    }

    curr_lump_pref <- function() {
      normalize_text(get_pref(con, "Current", "CurrLump", default = "None"))
    }

    refresh_lump_choices <- function(selected = NULL) {
      tables <- combine_species_list_lump_tables(con)
      base_names <- unique(vapply(tables, as_lump_base, character(1)))
      base_names <- sort(base_names[nzchar(base_names) & !grepl("(?i)^usys", base_names, perl = TRUE)])
      choice_values <- c("Attach", "New", "Unattach", "--------------------------------------", "None", base_names)

      if (!length(base_names)) {
        shiny::updateSelectInput(session, "cmbLump", choices = c("Attach", "New", "Unattach", "--------------------------------------", "None"), selected = "None")
        rv$lump_table <- ""
        rv$colmap <- NULL
        return(invisible(NULL))
      }

      selected_base <- as_lump_base(selected %||% curr_lump_pref())
      target <- if (nzchar(selected_base) && selected_base %in% choice_values) selected_base else "None"
      shiny::updateSelectInput(session, "cmbLump", choices = choice_values, selected = target)

      rv$lump_table <- combine_species_resolve_lump_table(con, target)
      rv$colmap <- combine_species_lump_column_map(con, rv$lump_table)
      invisible(NULL)
    }

    refresh_species_fields <- function() {
      fields <- combine_species_species_fields(con)
      shiny::updateSelectInput(session, "FieldName", choices = fields, selected = if ("code" %in% fields) "code" else fields[[1]])
    }

    refresh_criteria_choices <- function(default_value = NULL, selected_value = NULL) {
      field_name <- normalize_text(input$FieldName)
      fields <- combine_species_species_fields(con)
      if (!nzchar(field_name) || !(field_name %in% fields)) {
        shiny::updateSelectizeInput(session, "cmbCriteria", choices = character(0), selected = character(0), server = TRUE)
        return(invisible(NULL))
      }

      sql <- paste(
        "SELECT DISTINCT", qident(field_name), "AS value",
        "FROM lists.USysAllSpecs",
        "WHERE code IS NOT NULL AND COALESCE(CodeType, '') <> 'S' AND", qident(field_name), "IS NOT NULL",
        "ORDER BY 1 LIMIT 500"
      )
      values <- tryCatch(DBI::dbGetQuery(con, sql)$value, error = function(e) character(0))
      values <- unique(as.character(values))

      picked <- normalize_text(selected_value %||% default_value)
      if (nzchar(picked) && !(picked %in% values)) {
        values <- c(values, picked)
      }

      shiny::updateSelectizeInput(session, "cmbCriteria", choices = values, selected = if (nzchar(picked)) picked else character(0), server = TRUE)
      invisible(NULL)
    }

    species_rows <- shiny::reactive({
      rv$species_tick
      field_name <- normalize_text(input$FieldName)
      op <- normalize_text(input$Like)
      criteria <- normalize_text(input$cmbCriteria)
      pattern <- normalize_text(input$SppPattern)

      fields <- combine_species_species_fields(con)
      if (!nzchar(field_name) || !(field_name %in% fields)) {
        return(data.frame(code = character(0), scientificname = character(0), englishname = character(0), stringsAsFactors = FALSE))
      }

      quoted_field <- DBI::dbQuoteIdentifier(con, field_name)
      sql <- paste(
        "SELECT code, scientificname, englishname",
        "FROM lists.USysAllSpecs",
        "WHERE code IS NOT NULL AND COALESCE(CodeType, '') <> 'S'"
      )
      params <- list()

      if (nzchar(criteria)) {
        if (identical(op, "LIKE")) {
          sql <- paste(sql, "AND", as.character(quoted_field), "LIKE ?")
          params <- c(params, list(paste0("%", criteria, "%")))
        } else {
          allowed_ops <- c("=", ">", ">=", "<", "<=", "<>")
          if (op %in% allowed_ops) {
            sql <- paste(sql, "AND", as.character(quoted_field), op, "?")
            params <- c(params, list(criteria))
          }
        }
      }

      if (nzchar(pattern)) {
        sql <- paste(sql, "AND code LIKE ?")
        params <- c(params, list(paste0("%", pattern, "%")))
      }

      sql <- paste(sql, "ORDER BY code LIMIT 400")
      tryCatch(DBI::dbGetQuery(con, sql, params), error = function(e) data.frame(code = character(0), scientificname = character(0), englishname = character(0), stringsAsFactors = FALSE))
    })

    lump_rows <- shiny::reactive({
      req(nzchar(rv$lump_table), rv$colmap)
      rv$lump_tick
      sql <- paste(
        "SELECT",
        qident(rv$colmap$lump), "AS lumpcode,",
        qident(rv$colmap$spp), "AS sppcode"
      )
      if (nzchar(rv$colmap$use)) {
        sql <- paste(sql, ",", qident(rv$colmap$use), "AS in_use")
      } else {
        sql <- paste(sql, ", 1 AS in_use")
      }
      sql <- paste(sql, "FROM", qident(rv$lump_table), "ORDER BY 1,2")
      tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data.frame(lumpcode = character(0), sppcode = character(0), in_use = integer(0), stringsAsFactors = FALSE))
    })

    output$species_table <- DT::renderDT({
      DT::datatable(species_rows(), rownames = FALSE, selection = "multiple", options = list(pageLength = 10, scrollX = TRUE))
    })

    output$lump_table <- DT::renderDT({
      rows <- if (nzchar(rv$lump_table) && !is.null(rv$colmap)) lump_rows() else data.frame(lumpcode = character(0), sppcode = character(0), in_use = integer(0), stringsAsFactors = FALSE)
      DT::datatable(rows, rownames = FALSE, selection = "multiple", options = list(pageLength = 10, scrollX = TRUE))
    })

    output$lump_tree <- shinyTree::renderTree({
      rows <- if (nzchar(rv$lump_table) && !is.null(rv$colmap)) lump_rows() else data.frame(lumpcode = character(0), sppcode = character(0), in_use = integer(0), stringsAsFactors = FALSE)
      build_lump_tree(rows)
    })

    output$status <- shiny::renderText(rv$status)

    observeEvent(TRUE, {
      state$CurrForm <- "USysLumpMaster"
      state$sysCurrForm <- "USysLumpMaster"
      set_pref(con, "Current", "DataFormName", "USysLumpMaster")

      refresh_species_fields()
      refresh_criteria_choices(default_value = "ABIE*")
      pref_lump <- normalize_text(get_pref(con, "Current", "CurrLump", default = "None"))
      refresh_lump_choices(selected = if (nzchar(pref_lump)) pref_lump else "None")
      bump_species_tick()
      if (nzchar(rv$lump_table)) {
        state$LumpingTable <- rv$lump_table
        state$sysLumpingTable <- rv$lump_table
      }
      set_status("Loaded Combine Species (USysLumpMaster).")
    }, once = TRUE)

    observeEvent(input$btnLoadList, {
      bump_species_tick()
      set_status("Species list reloaded.")
    })

    observeEvent(input$species_table_rows_selected, {
      rows <- species_rows()
      idx <- input$species_table_rows_selected %||% integer(0)
      codes <- if (length(idx)) unique(as.character(rows$code[idx])) else character(0)
      shiny::updateTextInput(session, "selectedSpeciesCodes", value = paste(codes, collapse = ","))
    }, ignoreInit = FALSE)

    observeEvent(input$FieldName, {
      refresh_criteria_choices(selected_value = NULL)
      bump_species_tick()
      set_status("Field changed; criteria list refreshed.")
    }, ignoreInit = TRUE)

    observeEvent(input$cmbCriteria, {
      bump_species_tick()
      set_status("Criteria updated; species list reloaded.")
    }, ignoreInit = TRUE)

    observeEvent(input$SppPattern, {
      bump_species_tick()
      set_status("Pattern updated; species list reloaded.")
    }, ignoreInit = TRUE)

    observeEvent(input$cmbLump, {
      selected <- normalize_text(input$cmbLump)

      if (identical(selected, "--------------------------------------")) {
        prev <- curr_lump_pref()
        shiny::updateSelectInput(session, "cmbLump", selected = if (nzchar(prev)) prev else "None")
        set_status("Separator selected; restored previous lump table.")
        return()
      }

      if (identical(selected, "Attach")) {
        prev <- curr_lump_pref()
        shiny::updateSelectInput(session, "cmbLump", selected = if (nzchar(prev)) prev else "None")
        set_status("Attach is not yet wired in Shiny; selection restored.")
        return()
      }

      if (identical(selected, "Unattach")) {
        prev <- curr_lump_pref()
        shiny::updateSelectInput(session, "cmbLump", selected = if (nzchar(prev)) prev else "None")
        set_status("Unattach is not yet wired in Shiny; selection restored.")
        return()
      }

      if (identical(selected, "New")) {
        prev <- curr_lump_pref()
        shiny::updateSelectInput(session, "cmbLump", selected = if (nzchar(prev)) prev else "None")
        set_status("Use Save As... to create a new lump table.")
        return()
      }

      set_pref(con, "Current", "CurrLump", selected)
      rv$lump_table <- combine_species_resolve_lump_table(con, selected)
      rv$colmap <- combine_species_lump_column_map(con, rv$lump_table)
      bump_lump_tick()

      if (!nzchar(rv$lump_table)) {
        state$LumpingTable <- "None_Lump"
        state$sysLumpingTable <- "None_Lump"
        set_status("No lump table selected.")
      } else {
        state$LumpingTable <- rv$lump_table
        state$sysLumpingTable <- rv$lump_table
        set_status(sprintf("Using lump table: %s", rv$lump_table))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$btnRefreshTree, {
      bump_lump_tick()
      set_status("Lump mappings refreshed.")
    })

    observeEvent(input$lump_tree_dblclick, {
      payload <- input$lump_tree_dblclick
      meta <- parse_tree_id(payload$id %||% "")
      if (!identical(meta$type, "spp") || !nzchar(meta$lump) || !nzchar(meta$spp)) {
        return()
      }
      req(nzchar(rv$lump_table), rv$colmap, nzchar(rv$colmap$use))

      current <- tryCatch(DBI::dbGetQuery(
        con,
        paste(
          "SELECT", qident(rv$colmap$use), "AS in_use FROM", qident(rv$lump_table),
          "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ? LIMIT 1"
        ),
        list(meta$lump, meta$spp)
      ), error = function(e) data.frame(in_use = integer(0), stringsAsFactors = FALSE))

      if (!nrow(current)) {
        return()
      }

      new_val <- ifelse(as.integer(current$in_use[[1]]) == 1L, 0L, 1L)
      tryCatch(DBI::dbExecute(
        con,
        paste(
          "UPDATE", qident(rv$lump_table),
          "SET", qident(rv$colmap$use), "= ?",
          "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ?"
        ),
        list(new_val, meta$lump, meta$spp)
      ), error = function(e) NULL)

      bump_lump_tick()
      set_status(sprintf("Toggled %s in lump %s.", meta$spp, meta$lump))
    })

    observeEvent(input$lump_tree_context, {
      payload <- input$lump_tree_context
      action <- normalize_text(payload$action %||% "")
      meta <- parse_tree_id(payload$id %||% "")
      req(nzchar(rv$lump_table), rv$colmap)

      if (identical(action, "toggle") && identical(meta$type, "spp") && nzchar(rv$colmap$use)) {
        current <- tryCatch(DBI::dbGetQuery(
          con,
          paste(
            "SELECT", qident(rv$colmap$use), "AS in_use FROM", qident(rv$lump_table),
            "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ? LIMIT 1"
          ),
          list(meta$lump, meta$spp)
        ), error = function(e) data.frame(in_use = integer(0), stringsAsFactors = FALSE))

        if (nrow(current)) {
          new_val <- ifelse(as.integer(current$in_use[[1]]) == 1L, 0L, 1L)
          tryCatch(DBI::dbExecute(
            con,
            paste(
              "UPDATE", qident(rv$lump_table),
              "SET", qident(rv$colmap$use), "= ?",
              "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ?"
            ),
            list(new_val, meta$lump, meta$spp)
          ), error = function(e) NULL)
          bump_lump_tick()
          set_status(sprintf("Toggled %s in lump %s.", meta$spp, meta$lump))
        }
        return()
      }

      if (identical(meta$type, "lump") && action %in% c("set_yes", "set_no") && nzchar(rv$colmap$use)) {
        new_val <- if (identical(action, "set_yes")) 1L else 0L
        tryCatch(DBI::dbExecute(
          con,
          paste(
            "UPDATE", qident(rv$lump_table),
            "SET", qident(rv$colmap$use), "= ?",
            "WHERE", qident(rv$colmap$lump), "= ?"
          ),
          list(new_val, meta$lump)
        ), error = function(e) NULL)
        bump_lump_tick()
        set_status(sprintf("Set all species in %s to %s.", meta$lump, ifelse(new_val == 1L, "Yes", "No")))
      }
    })

    observeEvent(input$lump_tree_drop, {
      payload <- input$lump_tree_drop
      meta <- parse_tree_id(payload$id %||% "")
      req(nzchar(rv$lump_table), rv$colmap)

      target_lump <- if (identical(meta$type, "lump")) meta$lump else if (identical(meta$type, "spp")) meta$lump else ""
      if (!nzchar(target_lump)) {
        set_status("Drop target must be a lump node.")
        return()
      }

      raw_codes <- normalize_text(payload$codes %||% "")
      codes <- unique(trimws(unlist(strsplit(raw_codes, ",", fixed = TRUE))))
      codes <- codes[nzchar(codes)]
      if (!length(codes)) {
        set_status("Select species first, then drag to a lump node.")
        return()
      }

      for (code in codes) {
        exists_row <- tryCatch(DBI::dbGetQuery(
          con,
          paste(
            "SELECT 1 AS hit FROM", qident(rv$lump_table),
            "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ? LIMIT 1"
          ),
          list(target_lump, code)
        ), error = function(e) data.frame(hit = integer(0), stringsAsFactors = FALSE))

        if (nrow(exists_row)) {
          next
        }

        cols <- c(rv$colmap$lump, rv$colmap$spp)
        vals <- list(target_lump, code)
        if (nzchar(rv$colmap$use)) {
          cols <- c(cols, rv$colmap$use)
          vals <- c(vals, list(1L))
        }

        tryCatch(DBI::dbExecute(
          con,
          paste(
            "INSERT INTO", qident(rv$lump_table),
            "(", paste(vapply(cols, qident, character(1)), collapse = ", "), ")",
            "VALUES (", paste(rep("?", length(cols)), collapse = ", "), ")"
          ),
          vals
        ), error = function(e) NULL)
      }

      bump_lump_tick()
      set_status(sprintf("Dropped %d selected species into lump %s.", length(codes), target_lump))
    })

    observeEvent(input$btnAddMapping, {
      req(nzchar(rv$lump_table), rv$colmap)
      rows <- species_rows()
      idx <- input$species_table_rows_selected %||% integer(0)
      if (!length(idx)) {
        set_status("Select one or more species to add.")
        return()
      }

      lump_code <- normalize_text(input$new_lump_code)
      if (!nzchar(lump_code)) {
        set_status("Enter a Lump Code before adding species.")
        return()
      }

      selected_codes <- unique(as.character(rows$code[idx]))
      for (code in selected_codes) {
        cols <- c(rv$colmap$lump, rv$colmap$spp)
        vals <- list(lump_code, code)
        if (nzchar(rv$colmap$use)) {
          cols <- c(cols, rv$colmap$use)
          vals <- c(vals, list(1L))
        }

        sql <- paste(
          "INSERT INTO", qident(rv$lump_table),
          "(", paste(vapply(cols, qident, character(1)), collapse = ", "), ")",
          "VALUES (", paste(rep("?", length(cols)), collapse = ", "), ")"
        )
        tryCatch(DBI::dbExecute(con, sql, vals), error = function(e) NULL)
      }

      bump_lump_tick()
      set_status(sprintf("Added %d mapping(s) to %s.", length(selected_codes), rv$lump_table))
    })

    observeEvent(input$btnToggleUse, {
      req(nzchar(rv$lump_table), rv$colmap, nzchar(rv$colmap$use))
      rows <- lump_rows()
      idx <- input$lump_table_rows_selected %||% integer(0)
      if (!length(idx)) {
        set_status("Select mapping rows to toggle use.")
        return()
      }

      for (i in idx) {
        row <- rows[i, , drop = FALSE]
        new_val <- ifelse(as.integer(row$in_use[[1]]) == 1L, 0L, 1L)
        sql <- paste(
          "UPDATE", qident(rv$lump_table),
          "SET", qident(rv$colmap$use), "= ?",
          "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ?"
        )
        tryCatch(DBI::dbExecute(con, sql, list(new_val, row$lumpcode[[1]], row$sppcode[[1]])), error = function(e) NULL)
      }

      bump_lump_tick()
      set_status("Toggled selected mapping(s).")
    })

    observeEvent(input$btnDeleteMapping, {
      req(nzchar(rv$lump_table), rv$colmap)
      rows <- lump_rows()
      idx <- input$lump_table_rows_selected %||% integer(0)
      if (!length(idx)) {
        set_status("Select mapping rows to delete.")
        return()
      }

      for (i in idx) {
        row <- rows[i, , drop = FALSE]
        sql <- paste(
          "DELETE FROM", qident(rv$lump_table),
          "WHERE", qident(rv$colmap$lump), "= ? AND", qident(rv$colmap$spp), "= ?"
        )
        tryCatch(DBI::dbExecute(con, sql, list(row$lumpcode[[1]], row$sppcode[[1]])), error = function(e) NULL)
      }

      bump_lump_tick()
      set_status("Deleted selected mapping(s).")
    })

    observeEvent(input$btnSaveAs, {
      base_name <- normalize_text(input$txtSaveAs)
      if (!nzchar(base_name)) {
        set_status("Enter a base name for Save As.")
        return()
      }

      new_table <- if (grepl("(?i)_lump$", base_name, perl = TRUE)) base_name else paste0(base_name, "_Lump")
      if (DBI::dbExistsTable(con, new_table)) {
        set_status(sprintf("Table %s already exists.", new_table))
        return()
      }

      source_table <- if (nzchar(rv$lump_table)) rv$lump_table else "Lump"
      sql <- paste("CREATE TABLE", qident(new_table), "AS SELECT * FROM", qident(source_table))
      ok <- tryCatch({
        DBI::dbExecute(con, sql)
        TRUE
      }, error = function(e) FALSE)

      if (!ok) {
        set_status(sprintf("Save As failed for %s.", new_table))
        return()
      }

      refresh_lump_choices(selected = new_table)
      set_pref(con, "Current", "CurrLump", new_table)
      state$LumpingTable <- new_table
      state$sysLumpingTable <- new_table
      bump_lump_tick()
      set_status(sprintf("Created and selected %s.", new_table))
    })

    observeEvent(input$btnOpenTable, {
      if (!nzchar(rv$lump_table)) {
        set_status("Select a table first.")
        return()
      }
      set_status(sprintf("Viewing table %s in this module.", rv$lump_table))
    })

    observeEvent(input$btnHelp, {
      shiny::showModal(shiny::modalDialog(
        title = "VPro",
        "L = lump code",
        shiny::tags$br(),
        "Check mark = species will be lumped",
        shiny::tags$br(),
        "X = species will not be lumped",
        shiny::tags$br(),
        "Drag code(s) from right pane onto lump code in left pane",
        shiny::tags$br(),
        "Right-click left pane codes for pop-up menu",
        shiny::tags$br(),
        "Double-click species codes in left pane to change status",
        shiny::tags$br(),
        "Don't use an existing species code as a lump code",
        easyClose = TRUE,
        footer = shiny::modalButton("Close")
      ))
    })

    observeEvent(input$btnClose, {
      bslib::nav_select("main_tabs", "Vegetation", session = session$parent)
    })
  })
}

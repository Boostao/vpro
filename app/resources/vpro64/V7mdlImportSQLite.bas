Attribute VB_Name = "V7mdlImportSQLite"
Option Compare Database
Option Explicit

' =============================================================================
' V7mdlImportSQLite - Import VPro 2.0 SQLite (.db) Projects into VPro64 (.accdb)
' =============================================================================
' Purpose:
'   Reads a VPro 2.0 SQLite database (.db, WAL or DELETE journal mode) via the
'   SQLite3 ODBC Driver (DSN-less, read-only) and creates a native VPro64 VP08
'   Access database (.accdb) using VPro64's canonical USys* template tables,
'   preserving exact field types, VP08 table Description stamps, leading-zero
'   PlotNumbers, AutoNumber IDs (Veg/Humus/Mineral/Other/Metadata/Hierarchy/
'   Herbarium), Memo fields (>255 chars), Booleans (-1/1/0/NULL), ISO dates,
'   VP08 relationships, and optional VPro64 table linking.
'
' Prerequisites (One-Time Setup on Windows):
'   1. Install the 64-bit SQLite3 ODBC Driver (matching 64-bit Access/VPro64):
'        http://www.ch-werner.de/sqliteodbc/sqliteodbc_w64.exe
'      (If running 32-bit Access, install sqliteodbc.exe instead.)
'      No ODBC DSN configuration is required; this module connects DSN-less.
'   2. Open VPro64.accdb, press Alt+F11 to open the VBA Editor, then choose:
'        File -> Import File... -> select V7mdlImportSQLite.bas
'   3. Press Debug -> Compile to verify, then save VPro64.accdb.
'
' Usage:
'   - Interactive GUI: Run `ImportSQLiteProject` (from Immediate Window, a
'     macro RunCode action, or a button on frmMainMenuFloat / ribbon).
'   - Driver check:    Run `TestSQLiteODBCDriver`
'   - Script / batch:  Call `ImportSQLiteDatabaseToAccdb(sqlitePath, accdbPath, ...)`
' =============================================================================

Private Const MSO_FILEDIALOG_SAVEAS As Long = 2
Private Const MSO_FILEDIALOG_FILEPICKER As Long = 3
Private Const COMMIT_BATCH_SIZE As Long = 2000
Private Const DB_AUTOINCR_ATTR As Long = 16       ' dbAutoIncrField
Private Const DB_VERSION_120 As Long = 128        ' Access 2007+ (.accdb)
Private Const SQLITE_DRIVER_NAME As String = "SQLite3 ODBC Driver"
Private Const SQLITE_DRIVER_URL As String = "http://www.ch-werner.de/sqliteodbc/sqliteodbc_w64.exe"
Private mLastImportError As String

Public Function GetLastSqliteImportError() As String
    GetLastSqliteImportError = mLastImportError
End Function

' -----------------------------------------------------------------------------
' Public Entry Point 1: Interactive GUI Import Wizard
' -----------------------------------------------------------------------------
Public Sub ImportSQLiteProject()
    On Error GoTo ErrHandler

    Dim sqlitePath As String
    Dim projects As Collection
    Dim companions As Collection
    Dim sourceProject As String
    Dim targetProject As String
    Dim targetAccdb As String
    Dim includeCompanions As Boolean
    Dim attachNow As Boolean
    Dim answer As VbMsgBoxResult
    Dim summary As String
    Dim defaultOut As String

    If Not TestSQLiteODBCDriver("") Then
        MsgBox "The '" & SQLITE_DRIVER_NAME & "' was not detected for this bitness of Microsoft Access." & vbCrLf & vbCrLf & _
               "One-time setup:" & vbCrLf & _
               "1. Download and run the 64-bit SQLite3 ODBC Driver installer:" & vbCrLf & _
               "   " & SQLITE_DRIVER_URL & vbCrLf & _
               "   (For 32-bit Access, use sqliteodbc.exe from the same site.)" & vbCrLf & _
               "2. Restart Microsoft Access and run ImportSQLiteProject again.", _
               vbExclamation, "VPro64 - SQLite ODBC Driver Required"
        Exit Sub
    End If

    sqlitePath = PickOpenSqliteFile("Select VPro 2.0 SQLite Database (.db) to Import")
    If Len(sqlitePath) = 0 Then Exit Sub

    Set projects = New Collection
    Set companions = New Collection
    DiscoverSqliteContents sqlitePath, projects, companions

    If projects.Count = 0 And companions.Count = 0 Then
        MsgBox "No VPro VP08 project tables (*_Env) or companion tables (*_SU, *_Hierarchy, *_Lump, *_Profile, *_Theme, *_Herbarium) were found in:" & vbCrLf & vbCrLf & sqlitePath, _
               vbInformation, "VPro64 - Import SQLite"
        Exit Sub
    End If

    sourceProject = ""
    targetProject = ""
    If projects.Count = 1 Then
        sourceProject = CStr(projects(1))
    ElseIf projects.Count > 1 Then
        sourceProject = PromptChooseProject(projects)
        If Len(sourceProject) = 0 Then Exit Sub
    End If

    If Len(sourceProject) > 0 Then
        targetProject = Trim$(InputBox( _
            "Source VPro 2.0 project detected: " & sourceProject & vbCrLf & vbCrLf & _
            "Enter the project name to use in Access (letters/numbers, no underscores, <= 31 characters for Excel report compatibility):", _
            "VPro64 - Target Project Name", sourceProject))
        If Len(targetProject) = 0 Then Exit Sub
        If Not IsValidVProPrefix(targetProject) Then
            MsgBox "Invalid project name '" & targetProject & "'. Use letters, digits, or spaces without underscores or punctuation.", _
                   vbExclamation, "VPro64 - Import SQLite"
            Exit Sub
        End If
    End If

    includeCompanions = False
    If companions.Count > 0 Then
        If Len(sourceProject) = 0 Then
            includeCompanions = True
        Else
            answer = MsgBox( _
                "Found " & companions.Count & " companion table(s) (*_SU, *_Hierarchy, *_Lump, *_Profile, *_Theme, *_Herbarium) in this SQLite file." & vbCrLf & vbCrLf & _
                "Import those companion tables into the Access database as well?", _
                vbYesNoCancel + vbQuestion, "VPro64 - Companion Tables")
            If answer = vbCancel Then Exit Sub
            includeCompanions = (answer = vbYes)
        End If
    End If

    If Len(targetProject) > 0 Then
        defaultOut = GetFolderPath(sqlitePath) & "\" & targetProject & ".accdb"
    Else
        defaultOut = GetFolderPath(sqlitePath) & "\" & GetBaseFileName(sqlitePath) & ".accdb"
    End If

    targetAccdb = PickSaveAccdbFile("Choose New or Existing Access Database (.accdb)", defaultOut)
    If Len(targetAccdb) = 0 Then Exit Sub
    If LCase$(Right$(targetAccdb, 6)) <> ".accdb" Then
        targetAccdb = targetAccdb & ".accdb"
    End If
    If StrComp(targetAccdb, CurrentDb.Name, vbTextCompare) = 0 Then
        MsgBox "You cannot import directly into VPro64.accdb itself. Please pick a separate project .accdb file.", _
               vbExclamation, "VPro64 - Import SQLite"
        Exit Sub
    End If

    answer = MsgBox( _
        "Attach (link) the imported tables into this VPro64 session after conversion?", _
        vbYesNoCancel + vbQuestion, "VPro64 - Attach Imported Tables")
    If answer = vbCancel Then Exit Sub
    attachNow = (answer = vbYes)

    summary = ImportSQLiteDatabaseToAccdb(sqlitePath, targetAccdb, sourceProject, targetProject, includeCompanions, attachNow, False)
    MsgBox summary, vbInformation, "VPro64 - SQLite Import Complete"
    Exit Sub

ErrHandler:
    On Error Resume Next
    DoCmd.Hourglass False
    SysCmd acSysCmdRemoveMeter
    MsgBox "SQLite import failed (Error " & Err.Number & "):" & vbCrLf & Err.Description, vbCritical, "VPro64 - Import SQLite"
End Sub

' -----------------------------------------------------------------------------
' Public Entry Point 2: Driver & Connection Diagnostic
' -----------------------------------------------------------------------------
Public Function TestSQLiteODBCDriver(Optional ByVal SampleSqlitePath As String = "") As Boolean
    On Error GoTo ErrHandler
    Dim cn As Object
    Dim rs As Object
    Dim dbTarget As String

    Set cn = CreateObject("ADODB.Connection")
    If Len(Trim$(SampleSqlitePath)) > 0 Then
        dbTarget = Trim$(SampleSqlitePath)
        cn.Open BuildSqliteConnectionString(dbTarget)
    Else
        cn.Open "Driver={" & SQLITE_DRIVER_NAME & "};Database=:memory:;Timeout=5000;"
    End If

    Set rs = cn.Execute("SELECT sqlite_version()")
    If Not rs.EOF Then
        TestSQLiteODBCDriver = True
    End If

Cleanup:
    On Error Resume Next
    If Not rs Is Nothing Then rs.Close
    If Not cn Is Nothing Then
        If cn.State <> 0 Then cn.Close
    End If
    Set rs = Nothing
    Set cn = Nothing
    Exit Function

ErrHandler:
    TestSQLiteODBCDriver = False
    Resume Cleanup
End Function

' -----------------------------------------------------------------------------
' Public Entry Point 3: Programmable / Batch / Automated Import API
' -----------------------------------------------------------------------------
Public Function ImportSQLiteDatabaseToAccdb( _
    ByVal SqlitePath As String, _
    ByVal TargetAccdbPath As String, _
    Optional ByVal SourceProjectName As String = "", _
    Optional ByVal TargetProjectName As String = "", _
    Optional ByVal IncludeCompanions As Boolean = True, _
    Optional ByVal AttachToCurrentVPro As Boolean = False, _
    Optional ByVal Silent As Boolean = False _
) As String
    On Error GoTo ErrHandler

    Dim startTick As Double
    Dim cnSrc As Object
    Dim dstDB As DAO.Database
    Dim projects As Collection
    Dim companions As Collection
    Dim copyPlan As Collection     ' Collection of Array(srcTable, dstTable, templateName, tableDesc, isHierarchy)
    Dim warnings As Collection
    Dim importedTables As Collection
    Dim i As Long
    Dim item As Variant
    Dim rowsCopied As Long
    Dim totalRows As Long
    Dim coreSuffixes As Variant
    Dim coreTemplates As Variant
    Dim coreDescs As Variant
    Dim srcTbl As String
    Dim dstTbl As String
    Dim compSuffix As String
    Dim compPrefix As String
    Dim compTemplate As String
    Dim compDesc As String
    Dim report As String

    startTick = Timer
    mLastImportError = ""

    If Len(Trim$(SqlitePath)) = 0 Or Dir$(SqlitePath) = "" Then
        Err.Raise vbObjectError + 601, "V7mdlImportSQLite", "SQLite database file not found: " & SqlitePath
    End If
    If Len(Trim$(TargetAccdbPath)) = 0 Then
        Err.Raise vbObjectError + 602, "V7mdlImportSQLite", "Target Access database path (.accdb) is required."
    End If
    If StrComp(Trim$(TargetAccdbPath), CurrentDb.Name, vbTextCompare) = 0 Then
        Err.Raise vbObjectError + 603, "V7mdlImportSQLite", "Target .accdb cannot be the currently open VPro64 front-end database."
    End If
    If Not TestSQLiteODBCDriver("") Then
        Err.Raise vbObjectError + 604, "V7mdlImportSQLite", _
            "SQLite3 ODBC Driver not found. Install " & SQLITE_DRIVER_URL & " and restart Access."
    End If

    If Not Silent Then DoCmd.Hourglass True

    Set projects = New Collection
    Set companions = New Collection
    Set copyPlan = New Collection
    Set warnings = New Collection
    Set importedTables = New Collection

    DiscoverSqliteContents SqlitePath, projects, companions

    If Len(SourceProjectName) = 0 And projects.Count > 0 Then
        SourceProjectName = CStr(projects(1))
    End If
    If Len(SourceProjectName) > 0 Then
        If Len(TargetProjectName) = 0 Then TargetProjectName = SourceProjectName
        If Not IsValidVProPrefix(TargetProjectName) Then
            Err.Raise vbObjectError + 605, "V7mdlImportSQLite", "Invalid target project prefix: " & TargetProjectName
        End If
    End If

    ' Open SQLite read-only connection
    Set cnSrc = CreateObject("ADODB.Connection")
    cnSrc.Open BuildSqliteConnectionString(SqlitePath)

    ' Build copy plan: 8 core VP08 tables first (Env before children for FK clarity)
    If Len(SourceProjectName) > 0 Then
        coreSuffixes = Array("_Env", "_Admin", "_Veg", "_Humus", "_Mineral", "_Other", "_Audit", "_Metadata")
        coreTemplates = Array("USysEnvTable", "USysAdminTable", "USysVegTable", "USysSoilHumusTable", _
                              "USysSoilMineralTable", "USysOtherTable", "USysAudit", "USysMetadataTable")
        coreDescs = Array("VP08", "VP08", "VP08", "VP08", "VP08", "VP08", "VP08", "VP08")

        For i = LBound(coreSuffixes) To UBound(coreSuffixes)
            srcTbl = FindSqliteTableExact(cnSrc, SourceProjectName & CStr(coreSuffixes(i)))
            dstTbl = TargetProjectName & CStr(coreSuffixes(i))
            If Len(srcTbl) > 0 Then
                copyPlan.Add Array(srcTbl, dstTbl, CStr(coreTemplates(i)), CStr(coreDescs(i)), False)
            Else
                ' Still create empty required VP08 table so VPro64 recognizes the 8-table project set
                copyPlan.Add Array("", dstTbl, CStr(coreTemplates(i)), CStr(coreDescs(i)), False)
                warnings.Add "Source SQLite table '" & SourceProjectName & CStr(coreSuffixes(i)) & "' was missing; created empty VP08 table '" & dstTbl & "'."
            End If
        Next i
    End If

    ' Add optional companion tables
    If IncludeCompanions And companions.Count > 0 Then
        For i = 1 To companions.Count
            srcTbl = CStr(companions(i))
            If ResolveCompanionSpec(srcTbl, compPrefix, compSuffix, compTemplate, compDesc) Then
                If Len(SourceProjectName) > 0 And StrComp(compPrefix, SourceProjectName, vbTextCompare) = 0 Then
                    dstTbl = TargetProjectName & compSuffix
                Else
                    dstTbl = srcTbl
                End If
                copyPlan.Add Array(srcTbl, dstTbl, compTemplate, compDesc, (StrComp(compSuffix, "_Hierarchy", vbTextCompare) = 0))
            End If
        Next i
    End If

    If copyPlan.Count = 0 Then
        Err.Raise vbObjectError + 606, "V7mdlImportSQLite", "No importable VPro tables found in " & SqlitePath
    End If

    ' Create target .accdb if it does not yet exist
    If Dir$(TargetAccdbPath) = "" Then
        Set dstDB = DBEngine.Workspaces(0).CreateDatabase(TargetAccdbPath, dbLangGeneral, DB_VERSION_120)
        dstDB.Close
        Set dstDB = Nothing
    End If

    ' Validate target database does not already contain conflicting table names
    Set dstDB = DBEngine.Workspaces(0).OpenDatabase(TargetAccdbPath)
    For i = 1 To copyPlan.Count
        item = copyPlan(i)
        If TableExistsInDb(dstDB, CStr(item(1))) Then
            dstDB.Close
            Set dstDB = Nothing
            Err.Raise vbObjectError + 607, "V7mdlImportSQLite", _
                "Target table '" & CStr(item(1)) & "' already exists in " & TargetAccdbPath & ". Choose a new .accdb file or a different target project name."
        End If
    Next i
    dstDB.Close
    Set dstDB = Nothing

    ' Stage 1: Copy canonical USys* template structures into TargetAccdbPath
    If Not Silent Then SysCmd acSysCmdInitMeter, "Creating VPro64 Access tables...", copyPlan.Count
    For i = 1 To copyPlan.Count
        item = copyPlan(i)
        CreateTableFromTemplate TargetAccdbPath, CStr(item(1)), CStr(item(2)), CStr(item(3)), CBool(item(4))
        If Not Silent Then SysCmd acSysCmdUpdateMeter, i
    Next i
    If Not Silent Then SysCmd acSysCmdRemoveMeter

    ' Stage 2: Stream data from SQLite -> Access target tables
    Set dstDB = DBEngine.Workspaces(0).OpenDatabase(TargetAccdbPath)
    totalRows = 0
    report = "VPro 2.0 SQLite -> VPro64 Access Import Summary" & vbCrLf & _
             "Source: " & SqlitePath & vbCrLf & _
             "Target: " & TargetAccdbPath & vbCrLf

    If Not Silent Then SysCmd acSysCmdInitMeter, "Importing SQLite records...", copyPlan.Count
    For i = 1 To copyPlan.Count
        item = copyPlan(i)
        srcTbl = CStr(item(0))
        dstTbl = CStr(item(1))
        If Len(srcTbl) > 0 Then
            rowsCopied = CopySqliteTableToAccess(cnSrc, dstDB, srcTbl, dstTbl, warnings)
        Else
            rowsCopied = 0
        End If
        totalRows = totalRows + rowsCopied
        importedTables.Add dstTbl
        report = report & "  - " & dstTbl & ": " & rowsCopied & " row(s)" & vbCrLf
        If Not Silent Then SysCmd acSysCmdUpdateMeter, i
    Next i
    If Not Silent Then SysCmd acSysCmdRemoveMeter

    ' Stage 3: Establish canonical VP08 relationships on TargetAccdbPath
    If Len(TargetProjectName) > 0 Then
        CreateVP08Relationships dstDB, TargetProjectName, warnings
    End If

    dstDB.Close
    Set dstDB = Nothing
    cnSrc.Close
    Set cnSrc = Nothing

    ' Stage 4: Optionally attach (link) imported tables into CurrentDb (VPro64.accdb)
    If AttachToCurrentVPro Then
        AttachImportedTables TargetAccdbPath, importedTables, warnings
    End If

    report = report & "Total rows imported: " & totalRows & " (" & Format$(Timer - startTick, "0.0") & " s)"
    If AttachToCurrentVPro Then
        report = report & vbCrLf & "Tables linked into current VPro64 database."
    End If
    If warnings.Count > 0 Then
        report = report & vbCrLf & vbCrLf & "Warnings (" & warnings.Count & "):"
        For i = 1 To warnings.Count
            If i <= 15 Then
                report = report & vbCrLf & "  * " & CStr(warnings(i))
            Else
                report = report & vbCrLf & "  * ... and " & (warnings.Count - 15) & " more warning(s)."
                Exit For
            End If
        Next i
    End If

    If Not Silent Then DoCmd.Hourglass False
    ImportSQLiteDatabaseToAccdb = report
    Exit Function

ErrHandler:
    Dim errNum As Long
    Dim errDesc As String
    errNum = Err.Number
    errDesc = Err.Description
    mLastImportError = "Error " & errNum & ": " & errDesc
    On Error Resume Next
    If Not Silent Then
        DoCmd.Hourglass False
        SysCmd acSysCmdRemoveMeter
    End If
    If Not dstDB Is Nothing Then dstDB.Close
    If Not cnSrc Is Nothing Then
        If cnSrc.State <> 0 Then cnSrc.Close
    End If
    Set dstDB = Nothing
    Set cnSrc = Nothing
    Err.Raise errNum, "V7mdlImportSQLite.ImportSQLiteDatabaseToAccdb", errDesc
End Function

' =============================================================================
' Discovery & Schema Helpers
' =============================================================================

Private Function BuildSqliteConnectionString(ByVal SqlitePath As String) As String
    Dim safePath As String
    safePath = Trim$(SqlitePath)
    If InStr(safePath, ";") > 0 Then
        safePath = "{" & safePath & "}"
    End If
    ' ShortNames=1 + LongNames=0 ensures clean column names (not "Table.Col").
    ' BigInt=0 avoids ADODB 64-bit Decimal coercion pitfalls in VBA.
    BuildSqliteConnectionString = _
        "Driver={" & SQLITE_DRIVER_NAME & "};" & _
        "Database=" & safePath & ";" & _
        "NoCreat=1;" & _
        "LongNames=0;" & _
        "ShortNames=1;" & _
        "SyncPragma=OFF;" & _
        "NoTXN=1;" & _
        "BigInt=0;" & _
        "Timeout=10000;"
End Function

Private Sub DiscoverSqliteContents(ByVal SqlitePath As String, ByRef projects As Collection, ByRef companions As Collection)
    Dim cn As Object
    Dim rs As Object
    Dim tblName As String
    Dim prefix As String
    Dim suffix As String
    Dim tmpl As String
    Dim desc As String

    Set cn = CreateObject("ADODB.Connection")
    cn.Open BuildSqliteConnectionString(SqlitePath)

    Set rs = cn.Execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    Do While Not rs.EOF
        tblName = CStr(rs.Fields.Item(0).Value)
        If Not IsInternalSqliteTable(tblName) Then
            If Len(tblName) > 4 And StrComp(Right$(tblName, 4), "_Env", vbTextCompare) = 0 Then
                prefix = Left$(tblName, Len(tblName) - 4)
                If StrComp(prefix, "Filtered", vbTextCompare) <> 0 And _
                   StrComp(Left$(prefix, 4), "USys", vbTextCompare) <> 0 Then
                    projects.Add prefix
                End If
            ElseIf ResolveCompanionSpec(tblName, prefix, suffix, tmpl, desc) Then
                companions.Add tblName
            End If
        End If
        rs.MoveNext
    Loop

    rs.Close
    cn.Close
    Set rs = Nothing
    Set cn = Nothing
End Sub

Private Function IsInternalSqliteTable(ByVal TableName As String) As Boolean
    Dim lowerName As String
    lowerName = LCase$(TableName)
    If Left$(lowerName, 7) = "sqlite_" Then
        IsInternalSqliteTable = True
    ElseIf Left$(lowerName, 7) = "__vpro_" Then
        IsInternalSqliteTable = True
    ElseIf lowerName = "_table_metadata" Then
        IsInternalSqliteTable = True
    ElseIf Left$(lowerName, 4) = "usys" Then
        IsInternalSqliteTable = True
    ElseIf lowerName = "filtered_env" Then
        IsInternalSqliteTable = True
    End If
End Function

Private Function ResolveCompanionSpec( _
    ByVal TableName As String, _
    ByRef Prefix As String, _
    ByRef Suffix As String, _
    ByRef TemplateName As String, _
    ByRef TableDesc As String _
) As Boolean
    Dim specs As Variant
    Dim i As Long
    Dim sfx As String

    ' Format: Array(suffix, VPro64 USys template name, default table Description)
    specs = Array( _
        Array("_SU", "USysSuTable", "VP04"), _
        Array("_Hierarchy", "USysHierarchyTable", "VP04"), _
        Array("_Lump", "USysLumpTable", "VP05"), _
        Array("_Profile", "USysProfileTable", "VP05-2"), _
        Array("_Theme", "USysThemeTable", "VP04"), _
        Array("_Herbarium", "USysHerbarium", "02Apr2014") _
    )

    For i = LBound(specs) To UBound(specs)
        sfx = CStr(specs(i)(0))
        If Len(TableName) > Len(sfx) Then
            If StrComp(Right$(TableName, Len(sfx)), sfx, vbTextCompare) = 0 Then
                Prefix = Left$(TableName, Len(TableName) - Len(sfx))
                If StrComp(Left$(Prefix, 4), "USys", vbTextCompare) <> 0 Then
                    Suffix = sfx
                    TemplateName = CStr(specs(i)(1))
                    TableDesc = CStr(specs(i)(2))
                    ResolveCompanionSpec = True
                    Exit Function
                End If
            End If
        End If
    Next i
End Function

Private Function FindSqliteTableExact(ByVal cnSrc As Object, ByVal DesiredName As String) As String
    Dim rs As Object
    Dim tblName As String
    Set rs = cnSrc.Execute("SELECT name FROM sqlite_master WHERE type='table'")
    Do While Not rs.EOF
        tblName = CStr(rs.Fields.Item(0).Value)
        If StrComp(tblName, DesiredName, vbTextCompare) = 0 Then
            FindSqliteTableExact = tblName
            Exit Do
        End If
        rs.MoveNext
    Loop
    rs.Close
    Set rs = Nothing
End Function

Private Function TableExistsInDb(ByVal db As DAO.Database, ByVal TableName As String) As Boolean
    Dim td As DAO.TableDef
    For Each td In db.TableDefs
        If StrComp(td.Name, TableName, vbTextCompare) = 0 Then
            TableExistsInDb = True
            Exit Function
        End If
    Next td
End Function

Private Sub CreateTableFromTemplate( _
    ByVal TargetAccdbPath As String, _
    ByVal DstTableName As String, _
    ByVal TemplateName As String, _
    ByVal TableDesc As String, _
    ByVal IsHierarchy As Boolean _
)
    Dim curDb As DAO.Database
    Dim dstDB As DAO.Database
    Dim td As DAO.TableDef

    Set curDb = CurrentDb
    If Not TableExistsInDb(curDb, TemplateName) Then
        Err.Raise vbObjectError + 608, "V7mdlImportSQLite", _
            "Required VPro64 template table '" & TemplateName & "' was not found in the open database (" & curDb.Name & "). " & _
            "Please run this module from inside VPro64.accdb."
    End If

    DoCmd.CopyObject TargetAccdbPath, DstTableName, acTable, TemplateName

    ' Clear any template seed rows (e.g. USysHierarchyTable has 1 seed row; USysThemeTable has 10)
    Set dstDB = DBEngine.Workspaces(0).OpenDatabase(TargetAccdbPath)
    dstDB.Execute "DELETE FROM [" & DstTableName & "]", dbFailOnError

    ' Ensure Description property ("VP08", "VP04", etc.) and Hierarchy Parent RowSource are stamped cleanly
    Set td = dstDB.TableDefs(DstTableName)
    If Len(TableDesc) > 0 Then
        SetOrCreateTableProperty td, "Description", dbText, TableDesc
    End If
    If IsHierarchy Then
        On Error Resume Next
        td.Fields("Parent").Properties("RowSource").Value = DstTableName
        On Error GoTo 0
    End If
    dstDB.Close
    Set td = Nothing
    Set dstDB = Nothing
    Set curDb = Nothing
End Sub

Private Sub SetOrCreateTableProperty(ByVal td As DAO.TableDef, ByVal PropName As String, ByVal PropType As Integer, ByVal PropVal As Variant)
    On Error Resume Next
    td.Properties(PropName).Value = PropVal
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        td.Properties.Append td.CreateProperty(PropName, PropType, PropVal)
    End If
    On Error GoTo 0
End Sub

' =============================================================================
' Core Data Transfer Engine (AutoNumber-Preserving + Batched Transactions)
' =============================================================================

Private Function CopySqliteTableToAccess( _
    ByVal cnSrc As Object, _
    ByVal dstDB As DAO.Database, _
    ByVal SrcTableName As String, _
    ByVal DstTableName As String, _
    ByRef warnings As Collection _
) As Long
    Dim tdDst As DAO.TableDef
    Dim srcCols As Collection
    Dim matchedSrc() As String
    Dim matchedDst() As String
    Dim matchedFields() As DAO.Field
    Dim matchCount As Long
    Dim autoColIdx As Long
    Dim i As Long
    Dim colName As String
    Dim dstFld As DAO.Field
    Dim selectSql As String
    Dim rsSrc As Object

    Set tdDst = dstDB.TableDefs(DstTableName)
    Set srcCols = GetSqliteColumnNames(cnSrc, SrcTableName)

    matchCount = 0
    autoColIdx = -1
    ReDim matchedSrc(0 To srcCols.Count - 1)
    ReDim matchedDst(0 To srcCols.Count - 1)
    ReDim matchedFields(0 To srcCols.Count - 1)

    For i = 1 To srcCols.Count
        colName = CStr(srcCols(i))
        Set dstFld = FindDaoFieldInsensitive(tdDst, colName)
        If Not dstFld Is Nothing Then
            matchedSrc(matchCount) = colName
            matchedDst(matchCount) = dstFld.Name
            Set matchedFields(matchCount) = dstFld
            If (dstFld.Attributes And DB_AUTOINCR_ATTR) <> 0 Then
                autoColIdx = matchCount
            End If
            matchCount = matchCount + 1
        Else
            warnings.Add SrcTableName & "." & colName & " does not exist in VPro64 template '" & DstTableName & "' (skipped)."
        End If
    Next i

    If matchCount = 0 Then
        CopySqliteTableToAccess = 0
        Exit Function
    End If

    ReDim Preserve matchedSrc(0 To matchCount - 1)
    ReDim Preserve matchedDst(0 To matchCount - 1)
    ReDim Preserve matchedFields(0 To matchCount - 1)

    ' Build explicit quoted SQLite SELECT list so column ordinals are deterministic.
    ' IMPORTANT:
    '   - SQLite3 ODBC Driver treats declared BOOLEAN columns with -1 (VPro 2.0 True)
    '     as False! Normalizing booleans in SQLite SQL via CASE -> 1/0 preserves both
    '     VPro 2.0 (-1) and legacy (1) True values losslessly.
    '   - Casting dbDate columns to TEXT bypasses ODBC locale-dependent date parsing
    '     so ParseSqliteDate handles ISO-8601 consistently on all Windows locales.
    selectSql = "SELECT "
    For i = 0 To matchCount - 1
        If i > 0 Then selectSql = selectSql & ", "
        If matchedFields(i).Type = dbBoolean Then
            selectSql = selectSql & BuildSqliteBoolSelectExpr(matchedSrc(i))
        ElseIf matchedFields(i).Type = dbDate Then
            selectSql = selectSql & "CAST(" & QuoteSqliteIdent(matchedSrc(i)) & " AS TEXT)"
        Else
            selectSql = selectSql & QuoteSqliteIdent(matchedSrc(i))
        End If
    Next i
    selectSql = selectSql & " FROM " & QuoteSqliteIdent(SrcTableName)

    Set rsSrc = CreateObject("ADODB.Recordset")
    ' adOpenForwardOnly (0), adLockReadOnly (1)
    rsSrc.Open selectSql, cnSrc, 0, 1

    If rsSrc.EOF Then
        rsSrc.Close
        Set rsSrc = Nothing
        CopySqliteTableToAccess = 0
        Exit Function
    End If

    If autoColIdx >= 0 Then
        CopySqliteTableToAccess = CopyRowsWithAutoNumber( _
            rsSrc, dstDB, DstTableName, matchedDst, matchedFields, matchCount, autoColIdx, warnings)
    Else
        CopySqliteTableToAccess = CopyRowsViaRecordset( _
            rsSrc, dstDB, DstTableName, matchedDst, matchedFields, matchCount, warnings)
    End If

    rsSrc.Close
    Set rsSrc = Nothing
End Function

Private Function CopyRowsViaRecordset( _
    ByVal rsSrc As Object, _
    ByVal dstDB As DAO.Database, _
    ByVal DstTableName As String, _
    ByRef matchedDst() As String, _
    ByRef matchedFields() As DAO.Field, _
    ByVal matchCount As Long, _
    ByRef warnings As Collection _
) As Long
    On Error GoTo ErrHandler

    Dim ws As DAO.Workspace
    Dim rsDst As DAO.Recordset
    Dim dstOrdinals() As Integer
    Dim i As Long
    Dim rowCount As Long
    Dim batchCount As Long
    Dim inTx As Boolean
    Dim coerced As Variant

    Set ws = DBEngine.Workspaces(0)
    Set rsDst = dstDB.OpenRecordset(DstTableName, dbOpenTable)

    ReDim dstOrdinals(0 To matchCount - 1)
    For i = 0 To matchCount - 1
        dstOrdinals(i) = rsDst.Fields(matchedDst(i)).OrdinalPosition
    Next i

    ws.BeginTrans
    inTx = True
    rowCount = 0
    batchCount = 0

    Do While Not rsSrc.EOF
        rsDst.AddNew
        For i = 0 To matchCount - 1
            coerced = CoerceToAccessValue(rsSrc.Fields.Item(i).Value, matchedFields(i), DstTableName, rowCount + 1, warnings)
            rsDst.Fields(matchedDst(i)).Value = coerced
        Next i
        rsDst.Update

        rowCount = rowCount + 1
        batchCount = batchCount + 1
        If batchCount >= COMMIT_BATCH_SIZE Then
            ws.CommitTrans
            ws.BeginTrans
            batchCount = 0
            DoEvents
        End If
        rsSrc.MoveNext
    Loop

    If inTx Then
        ws.CommitTrans
        inTx = False
    End If

    rsDst.Close
    Set rsDst = Nothing
    CopyRowsViaRecordset = rowCount
    Exit Function

ErrHandler:
    Dim errNum As Long
    Dim errDesc As String
    errNum = Err.Number
    errDesc = Err.Description
    mLastImportError = "Error " & errNum & ": " & errDesc
    On Error Resume Next
    If inTx Then ws.Rollback
    If Not rsDst Is Nothing Then rsDst.Close
    Set rsDst = Nothing
    Err.Raise errNum, "V7mdlImportSQLite.CopyRowsViaRecordset", _
        "Failed copying table '" & DstTableName & "' at row " & (rowCount + 1) & ": " & errDesc
End Function

Private Function CopyRowsWithAutoNumber( _
    ByVal rsSrc As Object, _
    ByVal dstDB As DAO.Database, _
    ByVal DstTableName As String, _
    ByRef matchedDst() As String, _
    ByRef matchedFields() As DAO.Field, _
    ByVal matchCount As Long, _
    ByVal autoColIdx As Long, _
    ByRef warnings As Collection _
) As Long
    On Error GoTo ErrHandler

    Dim ws As DAO.Workspace
    Dim qd As DAO.QueryDef
    Dim rsFallback As DAO.Recordset
    Dim paramDecls As String
    Dim colList As String
    Dim valList As String
    Dim paramNames() As String
    Dim includeInInsert() As Boolean
    Dim deferredCols() As Long
    Dim deferredCount As Long
    Dim deferredVals() As Variant
    Dim hasDeferredNonNull As Boolean
    Dim i As Long
    Dim d As Long
    Dim colIdx As Long
    Dim rowCount As Long
    Dim batchCount As Long
    Dim inTx As Boolean
    Dim rawAuto As Variant
    Dim coerced As Variant
    Dim pkVal As Long

    ' Prepare a single parameterized INSERT QueryDef so Access preserves exact AutoNumber IDs.
    ' Note: ACE/DAO PARAMETERS cannot bind Memo (>255 chars) or LongBinary (OLE), so Memo/OLE
    ' columns are deferred and written via DAO.Recordset immediately after each row insert.
    ReDim paramNames(0 To matchCount - 1)
    ReDim includeInInsert(0 To matchCount - 1)
    ReDim deferredCols(0 To matchCount - 1)
    deferredCount = 0

    For i = 0 To matchCount - 1
        If matchedFields(i).Type = dbMemo Or matchedFields(i).Type = dbLongBinary Then
            includeInInsert(i) = False
            deferredCols(deferredCount) = i
            deferredCount = deferredCount + 1
        Else
            includeInInsert(i) = True
            paramNames(i) = "[p" & i & "]"
            If Len(paramDecls) > 0 Then
                paramDecls = paramDecls & ", "
                colList = colList & ", "
                valList = valList & ", "
            End If
            paramDecls = paramDecls & paramNames(i) & " " & DaoParamTypeDecl(matchedFields(i).Type)
            colList = colList & "[" & matchedDst(i) & "]"
            valList = valList & paramNames(i)
        End If
    Next i

    If deferredCount > 0 Then
        ReDim Preserve deferredCols(0 To deferredCount - 1)
        ReDim deferredVals(0 To deferredCount - 1)
    End If

    Set qd = dstDB.CreateQueryDef("", _
        "PARAMETERS " & paramDecls & "; " & _
        "INSERT INTO [" & DstTableName & "] (" & colList & ") VALUES (" & valList & ");")

    Set ws = DBEngine.Workspaces(0)
    ws.BeginTrans
    inTx = True
    rowCount = 0
    batchCount = 0

    Do While Not rsSrc.EOF
        rawAuto = rsSrc.Fields.Item(autoColIdx).Value
        If IsNull(rawAuto) Or IsEmpty(rawAuto) Then
            ' Legacy row with NULL AutoNumber: insert via Recordset so Access assigns a fresh ID
            If rsFallback Is Nothing Then
                Set rsFallback = dstDB.OpenRecordset(DstTableName, dbOpenTable)
            End If
            rsFallback.AddNew
            For i = 0 To matchCount - 1
                If i <> autoColIdx Then
                    coerced = CoerceToAccessValue(rsSrc.Fields.Item(i).Value, matchedFields(i), DstTableName, rowCount + 1, warnings)
                    rsFallback.Fields(matchedDst(i)).Value = coerced
                End If
            Next i
            rsFallback.Update
        Else
            For i = 0 To matchCount - 1
                If includeInInsert(i) Then
                    coerced = CoerceToAccessValue(rsSrc.Fields.Item(i).Value, matchedFields(i), DstTableName, rowCount + 1, warnings)
                    qd.Parameters("p" & i).Value = coerced
                End If
            Next i
            qd.Execute dbFailOnError

            ' Write any non-null Memo / OLE fields via DAO.Recordset (zero 255-char truncation)
            If deferredCount > 0 Then
                hasDeferredNonNull = False
                For d = 0 To deferredCount - 1
                    colIdx = deferredCols(d)
                    coerced = CoerceToAccessValue(rsSrc.Fields.Item(colIdx).Value, matchedFields(colIdx), DstTableName, rowCount + 1, warnings)
                    deferredVals(d) = coerced
                    If Not IsNull(coerced) And Not IsEmpty(coerced) Then
                        hasDeferredNonNull = True
                    End If
                Next d
                If hasDeferredNonNull Then
                    pkVal = CLng(rawAuto)
                    UpdateDeferredFieldsByPk dstDB, DstTableName, matchedDst(autoColIdx), pkVal, matchedDst, deferredCols, deferredVals, deferredCount
                End If
            End If
        End If

        rowCount = rowCount + 1
        batchCount = batchCount + 1
        If batchCount >= COMMIT_BATCH_SIZE Then
            ws.CommitTrans
            ws.BeginTrans
            batchCount = 0
            DoEvents
        End If
        rsSrc.MoveNext
    Loop

    If inTx Then
        ws.CommitTrans
        inTx = False
    End If

    If Not rsFallback Is Nothing Then rsFallback.Close
    qd.Close
    Set rsFallback = Nothing
    Set qd = Nothing
    CopyRowsWithAutoNumber = rowCount
    Exit Function

ErrHandler:
    Dim errNum As Long
    Dim errDesc As String
    errNum = Err.Number
    errDesc = Err.Description
    mLastImportError = "Error " & errNum & ": " & errDesc
    On Error Resume Next
    If inTx Then ws.Rollback
    If Not rsFallback Is Nothing Then rsFallback.Close
    If Not qd Is Nothing Then qd.Close
    Set rsFallback = Nothing
    Set qd = Nothing
    Err.Raise errNum, "V7mdlImportSQLite.CopyRowsWithAutoNumber", _
        "Failed copying table '" & DstTableName & "' at row " & (rowCount + 1) & ": " & errDesc
End Function

Private Sub UpdateDeferredFieldsByPk( _
    ByVal dstDB As DAO.Database, _
    ByVal TableName As String, _
    ByVal PkCol As String, _
    ByVal PkVal As Long, _
    ByRef matchedDst() As String, _
    ByRef deferredCols() As Long, _
    ByRef deferredVals() As Variant, _
    ByVal deferredCount As Long _
)
    Dim rs As DAO.Recordset
    Dim selCols As String
    Dim d As Long

    selCols = "[" & PkCol & "]"
    For d = 0 To deferredCount - 1
        selCols = selCols & ", [" & matchedDst(deferredCols(d)) & "]"
    Next d

    Set rs = dstDB.OpenRecordset( _
        "SELECT " & selCols & " FROM [" & TableName & "] WHERE [" & PkCol & "] = " & PkVal, _
        dbOpenDynaset)
    If Not rs.EOF Then
        rs.Edit
        For d = 0 To deferredCount - 1
            If Not IsNull(deferredVals(d)) And Not IsEmpty(deferredVals(d)) Then
                rs.Fields(d + 1).Value = deferredVals(d)
            End If
        Next d
        rs.Update
    End If
    rs.Close
    Set rs = Nothing
End Sub

Private Function DaoParamTypeDecl(ByVal FieldType As Integer) As String
    Select Case FieldType
        Case dbBoolean:     DaoParamTypeDecl = "Bit"
        Case dbByte:        DaoParamTypeDecl = "Byte"
        Case dbInteger:     DaoParamTypeDecl = "Short"
        Case dbLong:        DaoParamTypeDecl = "Long"
        Case dbCurrency:    DaoParamTypeDecl = "Currency"
        Case dbSingle:      DaoParamTypeDecl = "IEEEDouble"
        Case dbDouble:      DaoParamTypeDecl = "IEEEDouble"
        Case dbDate:        DaoParamTypeDecl = "DateTime"
        Case dbText:        DaoParamTypeDecl = "Text (255)"
        Case dbMemo:        DaoParamTypeDecl = "Memo"
        Case dbLongBinary:  DaoParamTypeDecl = "LongBinary"
        Case Else:          DaoParamTypeDecl = "Memo"
    End Select
End Function

' =============================================================================
' Strict Type Coercion (SQLite -> Access DAO)
' =============================================================================

Private Function CoerceToAccessValue( _
    ByVal RawVal As Variant, _
    ByVal DstField As DAO.Field, _
    ByVal TableName As String, _
    ByVal RowNum As Long, _
    ByRef warnings As Collection _
) As Variant
    Dim s As String
    Dim dt As Variant

    ' Access Yes/No (dbBoolean) fields cannot store Null
    If DstField.Type = dbBoolean Then
        CoerceToAccessValue = CoerceToBool(RawVal)
        Exit Function
    End If

    If IsNull(RawVal) Or IsEmpty(RawVal) Then
        CoerceToAccessValue = Null
        Exit Function
    End If

    Select Case DstField.Type
        Case dbText
            s = CStr(RawVal)
            If Len(s) = 0 And Not DstField.AllowZeroLength Then
                CoerceToAccessValue = Null
            ElseIf DstField.Size > 0 And Len(s) > DstField.Size Then
                warnings.Add TableName & "." & DstField.Name & " row " & RowNum & " truncated from " & Len(s) & " to " & DstField.Size & " chars."
                CoerceToAccessValue = Left$(s, DstField.Size)
            Else
                CoerceToAccessValue = s
            End If

        Case dbMemo
            s = CStr(RawVal)
            If Len(s) = 0 And Not DstField.AllowZeroLength Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = s
            End If

        Case dbDate
            dt = ParseSqliteDate(RawVal)
            If IsNull(dt) Then
                warnings.Add TableName & "." & DstField.Name & " row " & RowNum & " could not parse date '" & CStr(RawVal) & "' (set to Null)."
            End If
            CoerceToAccessValue = dt

        Case dbByte
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CByte(CLng(CDbl(RawVal)))
            End If

        Case dbInteger
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CInt(CDbl(RawVal))
            End If

        Case dbLong
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CLng(CDbl(RawVal))
            End If

        Case dbSingle
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CSng(CDbl(RawVal))
            End If

        Case dbDouble
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CDbl(RawVal)
            End If

        Case dbCurrency
            s = Trim$(CStr(RawVal))
            If Len(s) = 0 Then
                CoerceToAccessValue = Null
            Else
                CoerceToAccessValue = CCur(RawVal)
            End If

        Case dbLongBinary
            CoerceToAccessValue = RawVal

        Case Else
            CoerceToAccessValue = RawVal
    End Select
End Function

Private Function CoerceToBool(ByVal RawVal As Variant) As Boolean
    Dim u As String
    If IsNull(RawVal) Or IsEmpty(RawVal) Then
        CoerceToBool = False
    ElseIf VarType(RawVal) = vbBoolean Then
        CoerceToBool = CBool(RawVal)
    ElseIf IsNumeric(RawVal) Then
        ' Handles both VPro 2.0 (-1) and SQLite/legacy (1) as True; 0 as False
        CoerceToBool = (CDbl(RawVal) <> 0#)
    Else
        u = UCase$(Trim$(CStr(RawVal)))
        CoerceToBool = (u = "TRUE" Or u = "YES" Or u = "T" Or u = "Y" Or u = "-1" Or u = "1")
    End If
End Function

Private Function ParseSqliteDate(ByVal RawVal As Variant) As Variant
    Dim s As String
    Dim y As Integer, m As Integer, d As Integer
    Dim h As Integer, n As Integer, sec As Integer
    Dim sepPos As Long
    Dim datePartStr As String
    Dim timePartStr As String
    Dim dotPos As Long
    Dim tzPos As Long

    If IsNull(RawVal) Or IsEmpty(RawVal) Then
        ParseSqliteDate = Null
        Exit Function
    End If
    If VarType(RawVal) = vbDate Then
        ParseSqliteDate = CDate(RawVal)
        Exit Function
    End If

    s = Trim$(CStr(RawVal))
    If Len(s) = 0 Then
        ParseSqliteDate = Null
        Exit Function
    End If

    ' Locale-independent ISO-8601 parser: YYYY-MM-DD[T| HH:NN[:SS][.fff][Z|+-HH:MM]]
    If Len(s) >= 10 Then
        If Mid$(s, 5, 1) = "-" And Mid$(s, 8, 1) = "-" Then
            datePartStr = Left$(s, 10)
            If IsNumeric(Left$(datePartStr, 4)) And IsNumeric(Mid$(datePartStr, 6, 2)) And IsNumeric(Mid$(datePartStr, 9, 2)) Then
                y = CInt(Left$(datePartStr, 4))
                m = CInt(Mid$(datePartStr, 6, 2))
                d = CInt(Mid$(datePartStr, 9, 2))
                h = 0: n = 0: sec = 0

                If Len(s) > 10 Then
                    timePartStr = Trim$(Mid$(s, 12))
                    If Right$(UCase$(timePartStr), 1) = "Z" Then
                        timePartStr = Left$(timePartStr, Len(timePartStr) - 1)
                    End If
                    tzPos = InStr(2, timePartStr, "+")
                    If tzPos = 0 Then tzPos = InStr(2, timePartStr, "-")
                    If tzPos > 0 Then timePartStr = Left$(timePartStr, tzPos - 1)
                    dotPos = InStr(1, timePartStr, ".")
                    If dotPos > 0 Then timePartStr = Left$(timePartStr, dotPos - 1)

                    If Len(timePartStr) >= 5 And Mid$(timePartStr, 3, 1) = ":" Then
                        h = CInt(Left$(timePartStr, 2))
                        n = CInt(Mid$(timePartStr, 4, 2))
                        If Len(timePartStr) >= 8 And Mid$(timePartStr, 6, 1) = ":" Then
                            sec = CInt(Mid$(timePartStr, 7, 2))
                        End If
                    End If
                End If

                ParseSqliteDate = DateSerial(y, m, d) + TimeSerial(h, n, sec)
                Exit Function
            End If
        End If
    End If

    On Error Resume Next
    If IsDate(s) Then
        ParseSqliteDate = CDate(s)
    Else
        ParseSqliteDate = Null
    End If
    On Error GoTo 0
End Function

' =============================================================================
' Relationships & VPro64 Attachment Helpers
' =============================================================================

Private Sub CreateVP08Relationships(ByVal dstDB As DAO.Database, ByVal ProjectName As String, ByRef warnings As Collection)
    ' Creates the 6 valid VP08 relationships (omitting legacy dead Env.StartDate -> Metadata)
    Dim specs As Variant
    Dim i As Long
    Dim relName As String
    Dim childTbl As String
    Dim fkCol As String
    Dim attrs As Long

    specs = Array( _
        Array(ProjectName & "1", ProjectName & "_Veg", "PlotNumber", dbRelationUpdateCascade + dbRelationDeleteCascade), _
        Array(ProjectName & "2", ProjectName & "_Humus", "PlotNumber", dbRelationUpdateCascade + dbRelationDeleteCascade), _
        Array(ProjectName & "3", ProjectName & "_Mineral", "PlotNumber", dbRelationUpdateCascade + dbRelationDeleteCascade), _
        Array(ProjectName & "4", ProjectName & "_Other", "PlotNumber", dbRelationUpdateCascade + dbRelationDeleteCascade), _
        Array(ProjectName & "5", ProjectName & "_Audit", "PlotNumber", dbRelationUpdateCascade + dbRelationDeleteCascade), _
        Array(ProjectName & "7", ProjectName & "_Admin", "Plot", dbRelationUpdateCascade + dbRelationDeleteCascade + dbRelationUnique) _
    )

    For i = LBound(specs) To UBound(specs)
        relName = CStr(specs(i)(0))
        childTbl = CStr(specs(i)(1))
        fkCol = CStr(specs(i)(2))
        attrs = CLng(specs(i)(3))

        If TableExistsInDb(dstDB, ProjectName & "_Env") And TableExistsInDb(dstDB, childTbl) Then
            AppendRelationSafe dstDB, relName, ProjectName & "_Env", childTbl, "PlotNumber", fkCol, attrs, warnings
        End If
    Next i
End Sub

Private Sub AppendRelationSafe( _
    ByVal dstDB As DAO.Database, _
    ByVal RelName As String, _
    ByVal ParentTbl As String, _
    ByVal ChildTbl As String, _
    ByVal PkCol As String, _
    ByVal FkCol As String, _
    ByVal Attrs As Long, _
    ByRef warnings As Collection _
)
    On Error GoTo ErrHandler
    Dim rel As DAO.Relation
    Dim fld As DAO.Field

    On Error Resume Next
    dstDB.Relations.Delete RelName
    On Error GoTo ErrHandler

    Set rel = dstDB.CreateRelation(RelName, ParentTbl, ChildTbl, Attrs)
    Set fld = rel.CreateField(PkCol)
    fld.ForeignName = FkCol
    rel.Fields.Append fld
    dstDB.Relations.Append rel
    Exit Sub

ErrHandler:
    warnings.Add "Could not enforce relationship " & RelName & " (" & ParentTbl & " -> " & ChildTbl & "): " & Err.Description
End Sub

Private Sub AttachImportedTables(ByVal TargetAccdbPath As String, ByVal TableNames As Collection, ByRef warnings As Collection)
    Dim curDb As DAO.Database
    Dim i As Long
    Dim tbl As String

    Set curDb = CurrentDb
    For i = 1 To TableNames.Count
        tbl = CStr(TableNames(i))
        If TableExistsInDb(curDb, tbl) Then
            warnings.Add "Table '" & tbl & "' already exists in VPro64.accdb; skipped linking."
        Else
            DoCmd.TransferDatabase acLink, "Microsoft Access", TargetAccdbPath, acTable, tbl, tbl
        End If
    Next i

    On Error Resume Next
    If CurrentProject.AllForms("frmMainMenuFloat").IsLoaded Then
        Forms![frmMainMenuFloat].btnRefresh_Click
    End If
    On Error GoTo 0
    Set curDb = Nothing
End Sub

' =============================================================================
' SQLite / DAO Utility & File Dialog Helpers
' =============================================================================

Private Function GetSqliteColumnNames(ByVal cnSrc As Object, ByVal TableName As String) As Collection
    Dim cols As New Collection
    Dim rs As Object
    Set rs = cnSrc.Execute("PRAGMA table_info(" & QuoteSqliteIdent(TableName) & ")")
    Do While Not rs.EOF
        ' PRAGMA table_info columns: 0=cid, 1=name, 2=type, 3=notnull, 4=dflt_value, 5=pk
        cols.Add CStr(rs.Fields.Item(1).Value)
        rs.MoveNext
    Loop
    rs.Close
    Set rs = Nothing
    Set GetSqliteColumnNames = cols
End Function

Private Function FindDaoFieldInsensitive(ByVal td As DAO.TableDef, ByVal FieldName As String) As DAO.Field
    Dim f As DAO.Field
    For Each f In td.Fields
        If StrComp(f.Name, FieldName, vbTextCompare) = 0 Then
            Set FindDaoFieldInsensitive = f
            Exit Function
        End If
    Next f
End Function

Private Function QuoteSqliteIdent(ByVal Name As String) As String
    QuoteSqliteIdent = """" & Replace$(Name, """", """""") & """"
End Function

Private Function BuildSqliteBoolSelectExpr(ByVal ColName As String) As String
    Dim q As String
    q = QuoteSqliteIdent(ColName)
    BuildSqliteBoolSelectExpr = _
        "CASE WHEN " & q & " IS NULL THEN 0 " & _
        "WHEN typeof(" & q & ") IN ('integer','real') THEN CASE WHEN " & q & " <> 0 THEN 1 ELSE 0 END " & _
        "WHEN lower(trim(CAST(" & q & " AS TEXT))) IN ('1','-1','true','t','yes','y') THEN 1 ELSE 0 END"
End Function

Private Function IsValidVProPrefix(ByVal Prefix As String) As Boolean
    Dim i As Long
    Dim ch As String
    If Len(Prefix) = 0 Or Len(Prefix) > 40 Then Exit Function
    If InStr(Prefix, "_") > 0 Then Exit Function
    For i = 1 To Len(Prefix)
        ch = Mid$(Prefix, i, 1)
        If Not ((ch >= "A" And ch <= "Z") Or (ch >= "a" And ch <= "z") Or _
                (ch >= "0" And ch <= "9") Or ch = " " Or ch = "-") Then
            Exit Function
        End If
    Next i
    IsValidVProPrefix = True
End Function

Private Function PromptChooseProject(ByVal projects As Collection) As String
    Dim msg As String
    Dim i As Long
    Dim raw As String
    Dim idx As Long

    msg = "Multiple VPro projects were found in this SQLite database:" & vbCrLf & vbCrLf
    For i = 1 To projects.Count
        msg = msg & "  " & i & ". " & CStr(projects(i)) & vbCrLf
    Next i
    msg = msg & vbCrLf & "Enter the number or exact name of the project to import:"

    raw = Trim$(InputBox(msg, "VPro64 - Choose Project", "1"))
    If Len(raw) = 0 Then Exit Function

    If IsNumeric(raw) Then
        idx = CLng(raw)
        If idx >= 1 And idx <= projects.Count Then
            PromptChooseProject = CStr(projects(idx))
            Exit Function
        End If
    End If

    For i = 1 To projects.Count
        If StrComp(CStr(projects(i)), raw, vbTextCompare) = 0 Then
            PromptChooseProject = CStr(projects(i))
            Exit Function
        End If
    Next i
End Function

Private Function PickOpenSqliteFile(ByVal Title As String) As String
    Dim fd As Object
    Set fd = Application.FileDialog(MSO_FILEDIALOG_FILEPICKER)
    fd.Title = Title
    fd.AllowMultiSelect = False
    fd.Filters.Clear
    fd.Filters.Add "VPro SQLite Databases (*.db; *.sqlite)", "*.db; *.sqlite; *.sqlite3"
    fd.Filters.Add "All Files (*.*)", "*.*"
    If fd.Show = -1 Then
        PickOpenSqliteFile = CStr(fd.SelectedItems(1))
    End If
End Function

Private Function PickSaveAccdbFile(ByVal Title As String, ByVal DefaultFilePath As String) As String
    Dim fd As Object
    Set fd = Application.FileDialog(MSO_FILEDIALOG_SAVEAS)
    fd.Title = Title
    fd.InitialFileName = DefaultFilePath
    If fd.Show = -1 Then
        PickSaveAccdbFile = CStr(fd.SelectedItems(1))
    End If
End Function

Private Function GetFolderPath(ByVal FullPath As String) As String
    Dim pos As Long
    pos = InStrRev(FullPath, "\")
    If pos > 0 Then
        GetFolderPath = Left$(FullPath, pos - 1)
    Else
        GetFolderPath = CurDir$
    End If
End Function

Private Function GetBaseFileName(ByVal FullPath As String) As String
    Dim pos As Long
    Dim dotPos As Long
    Dim fname As String
    pos = InStrRev(FullPath, "\")
    If pos > 0 Then fname = Mid$(FullPath, pos + 1) Else fname = FullPath
    dotPos = InStrRev(fname, ".")
    If dotPos > 1 Then
        GetBaseFileName = Left$(fname, dotPos - 1)
    Else
        GetBaseFileName = fname
    End If
End Function

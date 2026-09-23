Option Compare Database
Option Explicit

Private mOutput As String

Private Sub LogValue(ByVal phase As String, ByVal key As String, ByVal value As Variant)
    Dim handle As Integer
    handle = FreeFile
    Open mOutput For Append As #handle
    Print #handle, phase & vbTab & key & vbTab & Replace(CStr(Nz(value, "<NULL>")), vbTab, " ")
    Close #handle
End Sub

Private Sub AddVeg(ByVal db As DAO.Database, ByVal plot As String, ByVal species As String, ByVal id As Long, ByVal year As Integer, Optional ByVal cover1 As Variant, Optional ByVal cover2 As Variant, Optional ByVal cover7 As Variant)
    Dim rs As DAO.Recordset
    Set rs = db.OpenRecordset("Oracle_Veg", dbOpenDynaset)
    rs.AddNew
    rs!PlotNumber = plot
    rs!Species = species
    rs!ID = id
    rs!SuccessionYear = year
    If Not IsMissing(cover1) Then rs!Cover1 = cover1
    If Not IsMissing(cover2) Then rs!Cover2 = cover2
    If Not IsMissing(cover7) Then rs!Cover7 = cover7
    rs.Update
    rs.Close
End Sub

Private Sub DumpRows(ByVal phase As String, ByVal plot As String)
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset("SELECT ID, Species, SuccessionYear, Cover1, Cover2, Cover7, Layer, TotalA, Collected FROM Oracle_Veg WHERE PlotNumber='" & plot & "' AND SuccessionYear IS NOT NULL ORDER BY SuccessionYear, Species, ID", dbOpenSnapshot)
    Do Until rs.EOF
        LogValue phase, "row", Nz(rs!ID, "<NULL>") & ";" & rs!Species & ";" & rs!SuccessionYear & ";" & Nz(rs!Cover1, "<NULL>") & ";" & Nz(rs!Cover2, "<NULL>") & ";" & Nz(rs!Cover7, "<NULL>") & ";" & Nz(rs!Layer, "<NULL>") & ";" & Nz(rs!TotalA, "<NULL>") & ";" & Nz(rs!Collected, "<NULL>")
        rs.MoveNext
    Loop
    rs.Close
End Sub

Public Function RunSuccessionCopyOracle(ByVal outputPath As String, ByVal backendPath As String, ByVal scenario As String) As String
    On Error GoTo Failed
    Dim db As DAO.Database, backend As DAO.Database, td As DAO.TableDef, suffix As Variant
    Dim rs As DAO.Recordset, plot As String, answer As Boolean
    mOutput = outputPath
    Open mOutput For Output As #1
    Close #1
    Set db = CurrentDb
    Set backend = DBEngine.CreateDatabase(backendPath, dbLangGeneral)
    backend.Close
    For Each suffix In Array("Admin", "Audit", "Env", "Humus", "Metadata", "Mineral", "Other", "Veg")
        DoCmd.CopyObject backendPath, "Oracle_" & suffix, acTable, "Sample_" & suffix
        Set td = db.CreateTableDef("Oracle_" & suffix)
        td.SourceTableName = "Oracle_" & suffix
        td.Connect = ";DATABASE=" & backendPath
        db.TableDefs.Append td
    Next suffix
    db.TableDefs.Refresh
    Set backend = DBEngine.OpenDatabase(backendPath)
    backend.TableDefs("Oracle_Veg").Fields.Append backend.TableDefs("Oracle_Veg").CreateField("SuccessionYear", dbInteger)
    Set rs = db.OpenRecordset("SELECT TOP 1 PlotNumber FROM Oracle_Env ORDER BY PlotNumber", dbOpenSnapshot)
    plot = rs!PlotNumber
    rs.Close
    LogValue "Setup", "scenario", scenario
    LogValue "Setup", "plot", plot
    LogValue "Setup", "backend", backendPath
    SetCurrentProject "Oracle"
    LogValue "Setup", "active", CurrProject()
    Select Case scenario
        Case "covers"
            AddVeg db, plot, "ZORAA", 900001, 2020, 15, 22, 31
            AddVeg db, plot, "ZORBB", 900002, 2020, , 18, 4
            AddVeg db, plot, "ZORCC", 900003, 2020
        Case "duplicate"
            AddVeg db, plot, "ZORAA", 900001, 2020, 15
            AddVeg db, plot, "ZORBB", 900002, 2020, 12
            AddVeg db, plot, "ZORAA", 900003, 2021, 33
        Case "duplicate-after"
            AddVeg db, plot, "ZORBB", 900001, 2020, 12
            AddVeg db, plot, "ZORAA", 900002, 2020, 15
            AddVeg db, plot, "ZORCC", 900003, 2020, 9
            AddVeg db, plot, "ZORAA", 900004, 2021, 33
        Case "same-year"
            AddVeg db, plot, "ZORAA", 900001, 2020, 15
            AddVeg db, plot, "ZORBB", 900002, 2020, 12
        Case "missing"
            AddVeg db, plot, "ZORAA", 900001, 2020, 15
        Case Else
            Err.Raise vbObjectError + 617, "SuccessionCopyProbe", "Unsupported scenario"
    End Select
    DumpRows "Before", plot
    Set rs = db.OpenRecordset("SELECT Count(*) AS n FROM Oracle_Audit WHERE PlotNumber='" & plot & "'", dbOpenSnapshot)
    LogValue "Before", "audit_rows", rs!n
    rs.Close
    OracleCopyError = ""
    OracleSourceYear = IIf(scenario = "missing", 2019, 2020)
    answer = OracleCopySuccessionData(plot, IIf(scenario = "same-year", 2020, 2021))
    LogValue "Call", "returned", answer
    LogValue "Call", "captured_error", OracleCopyError
    DumpRows "After", plot
    Set rs = db.OpenRecordset("SELECT Count(*) AS n FROM Oracle_Audit WHERE PlotNumber='" & plot & "'", dbOpenSnapshot)
    LogValue "After", "audit_rows", rs!n
    rs.Close
    backend.Close
    RunSuccessionCopyOracle = outputPath
    Exit Function
Failed:
    LogValue "Probe", "error", Err.Number & ":" & Err.Description
    On Error Resume Next
    If Not backend Is Nothing Then backend.Close
    RunSuccessionCopyOracle = outputPath
End Function

Option Compare Database
Option Explicit

Private mOutput As String

Private Sub LogValue(ByVal phase As String, ByVal key As String, ByVal value As Variant)
    Dim handle As Integer
    handle = FreeFile
    Open mOutput For Append As #handle
    Print #handle, phase & vbTab & key & vbTab & Replace(Nz(value, "<NULL>"), vbTab, " ")
    Close #handle
End Sub

Private Function HasField(ByVal db As DAO.Database, ByVal table As String, ByVal field As String) As Boolean
    Dim f As DAO.Field
    On Error Resume Next
    Set f = db.TableDefs(table).Fields(field)
    HasField = (Err.Number = 0)
    Err.Clear
    On Error GoTo 0
End Function

Private Function CountBackendRows(ByVal db As DAO.Database, ByVal table As String) As Long
    Dim rs As DAO.Recordset
    Set rs = db.OpenRecordset("SELECT Count(*) FROM [" & table & "]", dbOpenSnapshot)
    CountBackendRows = rs.Fields(0).Value
    rs.Close
End Function

Private Function CountRows(ByVal sql As String) As Long
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset(sql, dbOpenSnapshot)
    CountRows = rs.Fields(0).Value
    rs.Close
End Function

Public Function RunSuccessionReattachOracle(ByVal outputPath As String, ByVal backendPath As String) As String
    On Error GoTo Failed
    Dim db As DAO.Database
    Dim backend As DAO.Database
    Dim td As DAO.TableDef
    Dim suffix As Variant
    Dim view As Variant
    Dim sql As String
    Dim rs As DAO.Recordset
    mOutput = outputPath
    Open mOutput For Output As #1
    Close #1
    Set db = CurrentDb
    Set backend = DBEngine.OpenDatabase(backendPath)
    LogValue "Before", "CurrProject", GetSetting("VPro64", "Current", "CurrProject", "<UNSET>")
    LogValue "Before", "BackendVegYear", HasField(backend, "Oracle_Veg", "SuccessionYear")
    LogValue "Before", "BackendEnvFlag", HasField(backend, "Oracle_Env", "SuccessionPlot")
    LogValue "Before", "BackendVegRows", CountBackendRows(backend, "Oracle_Veg")
    backend.Close
    For Each suffix In Array("Admin", "Audit", "Env", "Humus", "Metadata", "Mineral", "Other", "Veg")
        Set td = db.CreateTableDef("Oracle_" & suffix)
        td.SourceTableName = "Oracle_" & suffix
        td.Connect = ";DATABASE=" & backendPath
        db.TableDefs.Append td
    Next suffix
    db.TableDefs.Refresh
    LogValue "Attach", "LinkedVegRows", CountRows("SELECT Count(*) FROM Oracle_Veg")
    LogValue "Attach", "LinkedEnvRows", CountRows("SELECT Count(*) FROM Oracle_Env")
    LogValue "Attach", "SuccessionProject", SuccessionProject("Oracle")
    SetCurrentProject "Oracle"
    LogValue "Activate", "CurrProject", GetSetting("VPro64", "Current", "CurrProject", "<UNSET>")
    LogValue "Activate", "ProjectPath", GetSetting("VPro64", "Current", "ProjectPath", "<UNSET>")
    For Each view In Array("USysVeg", "USysVegA", "USysVegB", "USysVegC", "USysVegD", "USysEnv")
        sql = db.QueryDefs(CStr(view)).SQL
        LogValue "View", CStr(view) & "HasYear", InStr(1, sql, "SuccessionYear", vbTextCompare) > 0
        On Error Resume Next
        Set rs = db.OpenRecordset("SELECT TOP 1 * FROM [" & view & "]", dbOpenSnapshot)
        If Err.Number <> 0 Then
            LogValue "View", CStr(view) & "Error", Err.Number & ":" & Err.Description
            Err.Clear
        Else
            LogValue "View", CStr(view) & "Opened", True
            rs.Close
        End If
        On Error GoTo Failed
    Next view
    OracleConversionError = ""
    OracleConversionStage = "not entered"
    OracleConvert2Succession "Oracle"
    LogValue "Retry", "Stage", OracleConversionStage
    LogValue "Retry", "Message", OracleConversionError
    LogValue "Retry", "CurrProject", GetSetting("VPro64", "Current", "CurrProject", "<UNSET>")
    Set backend = DBEngine.OpenDatabase(backendPath)
    LogValue "After", "BackendVegYear", HasField(backend, "Oracle_Veg", "SuccessionYear")
    LogValue "After", "BackendEnvFlag", HasField(backend, "Oracle_Env", "SuccessionPlot")
    backend.Close
    RunSuccessionReattachOracle = outputPath
    Exit Function
Failed:
    LogValue "Probe", "Error", Err.Number & ":" & Err.Description
    On Error Resume Next
    If Not backend Is Nothing Then backend.Close
    RunSuccessionReattachOracle = outputPath
End Function

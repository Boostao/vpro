Option Compare Database
Option Explicit

Private mOutput As String

Private Sub LogValue(ByVal Phase As String, ByVal Key As String, ByVal Value As Variant)
    Dim handle As Integer
    handle = FreeFile
    Open mOutput For Append As #handle
    Print #handle, Phase & vbTab & Key & vbTab & Replace(Nz(Value, "<NULL>"), vbTab, " ")
    Close #handle
End Sub

Private Function Scalar(ByVal SqlText As String) As Variant
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset(SqlText, dbOpenSnapshot)
    Scalar = rs.Fields(0).Value
    rs.Close
End Function

Private Sub FieldInfo(ByVal phase As String, ByVal db As DAO.Database, ByVal table As String, ByVal field As String)
    Dim f As DAO.Field
    On Error Resume Next
    Set f = db.TableDefs(table).Fields(field)
    If Err.Number <> 0 Then
        LogValue phase, field, "<ABSENT>"
        Err.Clear
    Else
        LogValue phase, field, "type=" & f.Type & ";size=" & f.Size & ";default=" & Nz(f.DefaultValue, "<NULL>") & ";required=" & f.Required
    End If
    On Error GoTo 0
End Sub

Private Function HasField(ByVal db As DAO.Database, ByVal table As String, ByVal field As String) As Boolean
    Dim f As DAO.Field
    On Error Resume Next
    Set f = db.TableDefs(table).Fields(field)
    HasField = (Err.Number = 0)
    Err.Clear
    On Error GoTo 0
End Function

Private Sub Snapshot(ByVal phase As String, ByVal db As DAO.Database)
    Dim rs As DAO.Recordset
    LogValue phase, "CurrProject", GetSetting("VPro64", "Current", "CurrProject", "<UNSET>")
    LogValue phase, "ProjectPath", GetSetting("VPro64", "Current", "ProjectPath", "<UNSET>")
    LogValue phase, "VegRows", Scalar("SELECT Count(*) FROM Oracle_Veg")
    LogValue phase, "EnvRows", Scalar("SELECT Count(*) FROM Oracle_Env")
    FieldInfo phase, db, "Oracle_Veg", "SuccessionYear"
    FieldInfo phase, db, "Oracle_Env", "SuccessionPlot"
    Set rs = db.OpenRecordset("SELECT Count(*) AS n, Min(ID) AS lowID, Max(ID) AS highID FROM Oracle_Veg", dbOpenSnapshot)
    LogValue phase, "VegIdentity", rs!n & ":" & Nz(rs!lowID, "<NULL>") & ":" & Nz(rs!highID, "<NULL>")
    rs.Close
    If phase = "After" And HasField(db, "Oracle_Veg", "SuccessionYear") Then
        Set rs = db.OpenRecordset("SELECT SuccessionYear, Count(*) AS n FROM Oracle_Veg GROUP BY SuccessionYear", dbOpenSnapshot)
        Do Until rs.EOF
            LogValue phase, "YearCount", Nz(rs!SuccessionYear, "<NULL>") & ":" & rs!n
            rs.MoveNext
        Loop
        rs.Close
    End If
    If phase = "After" And HasField(db, "Oracle_Env", "SuccessionPlot") Then
        LogValue phase, "NullPlotFlags", Scalar("SELECT Count(*) FROM Oracle_Env WHERE SuccessionPlot IS NULL")
        Set rs = db.OpenRecordset("SELECT SuccessionPlot, Count(*) AS n FROM Oracle_Env GROUP BY SuccessionPlot", dbOpenSnapshot)
        Do Until rs.EOF
            LogValue phase, "PlotFlagCount", Nz(rs!SuccessionPlot, "<NULL>") & ":" & rs!n
            rs.MoveNext
        Loop
        rs.Close
    End If
    If phase = "After" Then
        LogValue phase, "SuccessionView", InStr(1, CurrentDb.QueryDefs("USysVegA").SQL, "SuccessionYear", vbTextCompare) > 0
    End If
End Sub

Public Function RunSuccessionConversionOracle(ByVal outputPath As String, ByVal backendPath As String) As String
    On Error GoTo Failed
    Dim db As DAO.Database
    Dim backend As DAO.Database
    Dim suffix As Variant
    Dim td As DAO.TableDef
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
    LogValue "Setup", "Backend", backendPath
    LogValue "Setup", "VegConnection", db.TableDefs("Oracle_Veg").Connect
    LogValue "Setup", "OriginalSampleVegRows", Scalar("SELECT Count(*) FROM Sample_Veg")
    Snapshot "Before", backend
    SetCurrentProject "Oracle"
    LogValue "Activate", "CurrProject", GetSetting("VPro64", "Current", "CurrProject", "<UNSET>")
    OracleConversionError = ""
    OracleConversionStage = "not entered"
    LogValue "Activate", "CurrProjectFunction", CurrProject()
    LogValue "Activate", "PrecheckSuccessional", OracleSuccessionProject("Oracle")
    OracleConvert2Succession "Oracle"
    LogValue "Convert", "Stage", OracleConversionStage
    LogValue "Convert", "CapturedError", OracleConversionError
    backend.Close
    Set backend = DBEngine.OpenDatabase(backendPath)
    backend.TableDefs.Refresh
    Snapshot "After", backend
    LogValue "After", "OriginalSampleVegRows", Scalar("SELECT Count(*) FROM Sample_Veg")
    RunSuccessionConversionOracle = outputPath
    backend.Close
    Exit Function
Failed:
    LogValue "Probe", "Error", Err.Number & ":" & Err.Description
    On Error Resume Next
    If Not backend Is Nothing Then backend.Close
    RunSuccessionConversionOracle = outputPath
End Function

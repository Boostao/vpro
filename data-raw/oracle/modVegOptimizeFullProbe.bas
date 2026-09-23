Option Compare Database
Option Explicit

Private mOutput As String
Private mPlot As String

Private Sub DumpAudit(ByVal Phase As String)
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset("SELECT a.[Table], a.EditField, a.ID, a.BeforeEdit, a.AfterEdit, v.ID AS MatchingVegID FROM Sample_Audit AS a LEFT JOIN zOracle_Veg AS v ON a.PlotNumber=v.PlotNumber AND a.ID=v.ID WHERE a.[User]='zOracleVegAudit' AND a.PlotNumber='" & Replace(mPlot, "'", "''") & "' ORDER BY a.ID", dbOpenSnapshot)
    Do Until rs.EOF
        LogResult Phase, "Audit", rs.Fields(0).Value & ":" & rs.Fields(1).Value & ":" & rs.Fields(2).Value & ":" & Nz(rs.Fields(3).Value, "<NULL>") & ":" & Nz(rs.Fields(4).Value, "<NULL>") & ":" & Nz(rs.Fields(5).Value, "<NO VEG MATCH>")
        rs.MoveNext
    Loop
    rs.Close
End Sub

Private Sub LogResult(ByVal Phase As String, ByVal Key As String, ByVal Value As Variant)
    Dim n As Integer
    n = FreeFile
    Open mOutput For Append As #n
    Print #n, Phase & vbTab & Key & vbTab & Replace(Nz(Value, "<NULL>"), vbTab, " ")
    Close #n
End Sub

Private Function CountRows(ByVal SqlText As String) As Variant
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset(SqlText, dbOpenSnapshot)
    CountRows = rs.Fields(0).Value
    rs.Close
End Function

Private Sub DumpSchema(ByVal Phase As String, ByVal TableName As String)
    Dim sourceDb As DAO.Database
    Dim td As DAO.TableDef
    Dim f As DAO.Field
    Dim ix As DAO.Index
    Dim i As Long
    Set sourceDb = CurrentDb()
    Set td = sourceDb.TableDefs(TableName)
    LogResult Phase, "FieldCount", td.Fields.Count
    For i = 0 To td.Fields.Count - 1
        Set f = td.Fields(i)
        LogResult Phase, "Field" & CStr(i), f.Name & ":" & f.Type & ":" & f.Attributes
        If f.Name = "ID" Then
            On Error Resume Next
            LogResult Phase, "IDDefault", f.DefaultValue
            If Err.Number <> 0 Then LogResult Phase, "IDDefaultError", Err.Number & ":" & Err.Description
            Err.Clear
            On Error GoTo 0
        End If
    Next i
    For Each ix In td.Indexes
        LogResult Phase, "Index", ix.Name & ":" & ix.Primary & ":" & ix.Unique
    Next ix
End Sub

Private Sub DumpRows(ByVal Phase As String)
    Dim rs As DAO.Recordset
    Set rs = CurrentDb.OpenRecordset("SELECT PlotNumber, Species, Layer, ID, Cover1, Cover4, Cover8, Collected, Flag, Cultural1 FROM zOracle_Veg ORDER BY Species, ID", dbOpenSnapshot)
    Do Until rs.EOF
        LogResult Phase, "Row", rs!PlotNumber & ":" & rs!Species & ":" & Nz(rs!Layer, "<NULL>") & ":" & Nz(rs!ID, "<NULL>") & ":" & Nz(rs!Cover1, "<NULL>") & ":" & Nz(rs!Cover4, "<NULL>") & ":" & Nz(rs!Cover8, "<NULL>") & ":" & Nz(rs!Collected, "<NULL>") & ":" & Nz(rs!Flag, "<NULL>") & ":" & Nz(rs!Cultural1, "<NULL>")
        rs.MoveNext
    Loop
    rs.Close
End Sub

Public Function RunVegOptimizeFullOracle(ByVal OutputPath As String, ByVal DoRun As Boolean) As String
    On Error GoTo OracleError
    Dim db As DAO.Database
    Dim oldSql As String
    Dim newSql As String
    Dim result As Variant
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    Set db = CurrentDb()
    DumpSchema "Template", "USysVegTable"
    DumpSchema "Original", "Sample_Veg"
    LogResult "Setup", "OriginalSampleRows", CountRows("SELECT Count(*) FROM Sample_Veg")
    If Not DoRun Then
        RunVegOptimizeFullOracle = mOutput
        Exit Function
    End If
    On Error Resume Next
    DoCmd.DeleteObject acTable, "zOracle_Veg"
    DoCmd.DeleteObject acTable, "xxxtblTempVeg"
    DoCmd.DeleteObject acQuery, "xxxqryTempVeg"
    On Error GoTo OracleError
    DoCmd.CopyObject , "zOracle_Veg", acTable, "USysVegTable"
    DumpSchema "Scratch", "zOracle_Veg"
    mPlot = "108050"
    If CountRows("SELECT Count(*) FROM Sample_Env WHERE PlotNumber='108050'") <> 1 Then Err.Raise vbObjectError + 512, , "Fixture plot unavailable"
    db.Execute "INSERT INTO zOracle_Veg (PlotNumber, Species, ID, Layer, Cover1, Collected, Flag, Cultural1) VALUES ('108050', 'ORCVEG', 101, '1', 1, 'Y', True, 11)", dbFailOnError
    db.Execute "INSERT INTO zOracle_Veg (PlotNumber, Species, ID, Layer, Cover4, Collected, Flag, Cultural1) VALUES ('108050', 'ORCVEG', 202, '4', 4, 'N', False, 22)", dbFailOnError
    db.Execute "INSERT INTO zOracle_Veg (PlotNumber, Species, ID, Layer, Cover8, Collected, Cultural1) VALUES ('108050', 'ORCSOLO', 303, '8', 8, 'N', 33)", dbFailOnError
    db.Execute "INSERT INTO Sample_Audit ([Project], [User], PlotNumber, [Table], EditField, EditWhen, BeforeEdit, AfterEdit, ID) VALUES ('Sample', 'zOracleVegAudit', '108050', '_Veg', 'Cover1', Now(), '0', '1', 101)", dbFailOnError
    db.Execute "INSERT INTO Sample_Audit ([Project], [User], PlotNumber, [Table], EditField, EditWhen, BeforeEdit, AfterEdit, ID) VALUES ('Sample', 'zOracleVegAudit', '108050', '_Veg', 'Cover4', Now(), '0', '4', 202)", dbFailOnError
    db.Execute "INSERT INTO Sample_Audit ([Project], [User], PlotNumber, [Table], EditField, EditWhen, BeforeEdit, AfterEdit, ID) VALUES ('Sample', 'zOracleVegAudit', '108050', '_Veg', 'Cover8', Now(), '0', '8', 303)", dbFailOnError
    LogResult "Before", "Rows", CountRows("SELECT Count(*) FROM zOracle_Veg")
    LogResult "Before", "AuditCount", CountRows("SELECT Count(*) FROM Sample_Audit WHERE [User]='zOracleVegAudit'")
    DumpRows "Before"
    DumpAudit "Before"
    oldSql = db.QueryDefs("USysAllVeg").SQL
    newSql = Replace(oldSql, "UsysVeg", "zOracle_Veg", , , vbTextCompare)
    db.QueryDefs("USysAllVeg").SQL = newSql
    LogResult "Setup", "ScratchQueryRepointed", True
    LogResult "Setup", "DiagnosticOnScratch", CountRows("SELECT Count(*) FROM (SELECT PlotNumber, Species, MyLayer, Count(Cover) AS n FROM USysAllVeg GROUP BY PlotNumber, Species, MyLayer HAVING Count(Cover)>1)")
    LogResult "Optimize", "Starting", True
    result = OracleOptimizeVeg("zOracle_Veg", True)
    LogResult "Optimize", "Returned", True
    LogResult "After", "Rows", CountRows("SELECT Count(*) FROM zOracle_Veg")
    DumpRows "After"
    LogResult "After", "AuditCount", CountRows("SELECT Count(*) FROM Sample_Audit WHERE [User]='zOracleVegAudit'")
    DumpAudit "After"
    LogResult "After", "OriginalSampleRows", CountRows("SELECT Count(*) FROM Sample_Veg")
    LogResult "After", "TemporaryTableExists", CBool(CountRows("SELECT Count(*) FROM MSysObjects WHERE Name='xxxtblTempVeg' AND Type=1") > 0)
    LogResult "After", "TemporaryQueryExists", CBool(CountRows("SELECT Count(*) FROM MSysObjects WHERE Name='xxxqryTempVeg' AND Type=5") > 0)
    RunVegOptimizeFullOracle = mOutput
    Exit Function
OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    On Error Resume Next
    LogResult "AfterError", "Rows", CountRows("SELECT Count(*) FROM zOracle_Veg")
    DumpRows "AfterError"
    RunVegOptimizeFullOracle = mOutput
End Function

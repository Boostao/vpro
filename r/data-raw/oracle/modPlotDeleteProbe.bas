Option Compare Database
Option Explicit

Private mOutput As String

Private Sub LogResult(ByVal TestName As String, ByVal PropertyName As String, ByVal Value As Variant)
    Dim FileNumber As Integer
    FileNumber = FreeFile
    Open mOutput For Append As #FileNumber
    Print #FileNumber, TestName & vbTab & PropertyName & vbTab & Replace(Nz(Value, "<NULL>"), vbTab, " ")
    Close #FileNumber
End Sub

Private Function Scalar(ByVal SqlText As String) As Variant
    Dim MyRS As DAO.Recordset
    Set MyRS = CurrentDb.OpenRecordset(SqlText, dbOpenSnapshot)
    If MyRS.EOF Then
        Scalar = Null
    Else
        Scalar = MyRS.Fields(0).Value
    End If
    MyRS.Close
End Function

Private Function Quoted(ByVal Value As String) As String
    Quoted = "'" & Replace(Value, "'", "''") & "'"
End Function

Private Function SourcePlot() As String
    SourcePlot = CStr(Scalar( _
        "SELECT TOP 1 env.PlotNumber " & _
        "FROM ((((((Sample_Env AS env INNER JOIN Sample_Admin AS admin ON env.PlotNumber=admin.Plot) " & _
        "INNER JOIN Sample_SU AS su ON env.PlotNumber=su.PlotNumber) " & _
        "INNER JOIN Sample_Audit AS audit ON env.PlotNumber=audit.PlotNumber) " & _
        "INNER JOIN Sample_Veg AS veg ON env.PlotNumber=veg.PlotNumber) " & _
        "INNER JOIN Sample_Humus AS humus ON env.PlotNumber=humus.PlotNumber) " & _
        "INNER JOIN Sample_Mineral AS mineral ON env.PlotNumber=mineral.PlotNumber) " & _
        "INNER JOIN Sample_Other AS otherdata ON env.PlotNumber=otherdata.PlotNumber " & _
        "ORDER BY env.PlotNumber" _
    ))
End Function

Private Sub LogState(ByVal TestName As String, ByVal PlotNumber As String)
    Dim Suffix As Variant
    LogResult TestName, "EnvRows", Scalar("SELECT Count(*) FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
    LogResult TestName, "AdminRows", Scalar("SELECT Count(*) FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber))
    LogResult TestName, "JoinedRows", Scalar("SELECT Count(*) FROM USysEnv WHERE PlotNumber=" & Quoted(PlotNumber))
    LogResult TestName, "SURows", Scalar("SELECT Count(*) FROM Sample_SU WHERE PlotNumber=" & Quoted(PlotNumber))
    LogResult TestName, "AuditRows", Scalar("SELECT Count(*) FROM Sample_Audit WHERE PlotNumber=" & Quoted(PlotNumber))
    For Each Suffix In Array("Veg", "Humus", "Mineral", "Other")
        LogResult TestName, CStr(Suffix) & "Rows", Scalar("SELECT Count(*) FROM Sample_" & CStr(Suffix) & " WHERE PlotNumber=" & Quoted(PlotNumber))
    Next Suffix
End Sub

Private Sub ProbeDAO(ByVal TestName As String, ByVal PlotNumber As String)
    On Error GoTo ProbeError
    Dim DB As DAO.Database
    Dim RS As DAO.Recordset
    Dim AuditBefore As Long
    Set DB = CurrentDb
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    Set RS = DB.OpenRecordset("SELECT * FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber), dbOpenDynaset)
    If RS.EOF Then Err.Raise vbObjectError + 2201, "ProbeDAO", "Source plot does not exist"
    RS.Delete
    RS.Close
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    RS.Close
End Sub

Private Sub ProbeForm(ByVal TestName As String, ByVal PlotNumber As String)
    On Error GoTo ProbeError
    Dim F As Form
    Dim RS As DAO.Recordset
    Dim AuditBefore As Long
    DoCmd.OpenForm "FS882-8x6XL"
    Set F = Forms("FS882-8x6XL")
    Set RS = F.RecordsetClone
    RS.FindFirst "PlotNumber=" & Quoted(PlotNumber)
    If RS.NoMatch Then Err.Raise vbObjectError + 2202, "ProbeForm", "Source plot is not visible in FS882-8x6XL"
    F.Bookmark = RS.Bookmark
    LogResult TestName, "RecordSource", F.RecordSource
    LogResult TestName, "AllowDeletions", F.AllowDeletions
    LogResult TestName, "AllowEdits", F.AllowEdits
    LogResult TestName, "PlotNumber", F.Controls("PlotNumber").Value
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    DoCmd.SetWarnings False
    DoCmd.RunCommand acCmdDeleteRecord
    DoCmd.SetWarnings True
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    DoCmd.SetWarnings True
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
End Sub

Public Function RunPlotDeleteOracle(ByVal OutputPath As String, ByVal Mode As String) As String
    On Error GoTo OracleError
    Dim PlotNumber As String
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    PlotNumber = SourcePlot()
    LogResult "Oracle", "Mode", Mode
    LogResult "Oracle", "PlotNumber", PlotNumber
    LogResult "Oracle", "CurrProject", CurrProject()
    LogResult "Oracle", "CurrPlotlist", CurrPlotlist()
    LogResult "Oracle", "CurrHierarchy", CurrHierarchy()
    LogResult "Oracle", "InitialAuditStrength", clsVProReg.AuditStrength
    clsVProReg.AuditStrength = 2
    LogState Mode & ".Before", PlotNumber
    If Mode = "dao-success" Then
        ProbeDAO Mode, PlotNumber
    ElseIf Mode = "form-success" Then
        ProbeForm Mode, PlotNumber
    Else
        Err.Raise vbObjectError + 2203, "RunPlotDeleteOracle", "Unknown mode: " & Mode
    End If
    LogState Mode & ".After", PlotNumber
    LogResult "Oracle.After", "CurrProject", CurrProject()
    LogResult "Oracle.After", "CurrPlotlist", CurrPlotlist()
    LogResult "Oracle.After", "CurrHierarchy", CurrHierarchy()
    RunPlotDeleteOracle = mOutput
    Exit Function

OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    RunPlotDeleteOracle = mOutput
End Function

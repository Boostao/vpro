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

Private Sub LogPlotState(ByVal TestName As String, ByVal PlotNumber As String)
    Dim Suffix As Variant
    LogResult TestName, "EnvRows", Scalar("SELECT Count(*) FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
    LogResult TestName, "AdminRows", Scalar("SELECT Count(*) FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber))
    LogResult TestName, "JoinedRows", Scalar("SELECT Count(*) FROM USysEnv WHERE PlotNumber=" & Quoted(PlotNumber))
    LogResult TestName, "AuditRows", Scalar("SELECT Count(*) FROM Sample_Audit WHERE PlotNumber=" & Quoted(PlotNumber))
    For Each Suffix In Array("Veg", "Humus", "Mineral", "Other")
        LogResult TestName, CStr(Suffix) & "Rows", Scalar("SELECT Count(*) FROM Sample_" & CStr(Suffix) & " WHERE PlotNumber=" & Quoted(PlotNumber))
    Next Suffix
    If Scalar("SELECT Count(*) FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber)) > 0 Then
        LogResult TestName, "EnvProjectID", Scalar("SELECT ProjectID FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
        LogResult TestName, "EnvLocation", Scalar("SELECT Location FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
        LogResult TestName, "EnvDate", Scalar("SELECT [Date] FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
        LogResult TestName, "EnvFloodPlain", Scalar("SELECT SV_FloodPlain FROM Sample_Env WHERE PlotNumber=" & Quoted(PlotNumber))
    End If
    If Scalar("SELECT Count(*) FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber)) > 0 Then
        LogResult TestName, "AdminStartDate", Scalar("SELECT StartDate FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber))
        LogResult TestName, "AdminPlotType", Scalar("SELECT PlotType FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber))
        LogResult TestName, "AdminOfficeNotes", Scalar("SELECT OfficeNotes FROM Sample_Admin WHERE Plot=" & Quoted(PlotNumber))
    End If
End Sub

Private Sub ProbeCreate(ByVal TestName As String, ByVal PlotNumber As String, ByVal PopulateEnv As Boolean, ByVal PopulateAdmin As Boolean)
    On Error GoTo ProbeError
    Dim F As Form
    Dim AuditBefore As Long
    DoCmd.OpenForm "FS882-8x6XL"
    Set F = Forms("FS882-8x6XL")
    LogResult TestName, "RecordSource", F.RecordSource
    LogResult TestName, "AllowAdditions", F.AllowAdditions
    LogResult TestName, "DataEntry", F.DataEntry
    LogPlotState TestName & ".Before", PlotNumber
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    DoCmd.GoToRecord acDataForm, "FS882-8x6XL", acNewRec
    LogResult TestName, "NewRecordBeforeEntry", F.NewRecord
    F.Controls("PlotNumber").Value = PlotNumber
    LogResult TestName, "DirtyAfterPlotNumber", F.Dirty
    LogResult TestName, "NewRecordAfterPlotNumber", F.NewRecord
    If PopulateEnv Then F.Controls("Location").Value = "ORACLE CREATE"
    If PopulateAdmin Then
        F.Controls("PlotType").Value = "4"
        F.Controls("OfficeNotes").Value = "ORACLE ADMIN"
    End If
    If F.Dirty Then F.Dirty = False
    LogResult TestName, "DirtyAfterCommit", F.Dirty
    LogResult TestName, "NewRecordAfterCommit", F.NewRecord
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    LogPlotState TestName & ".After", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    LogPlotState TestName & ".AfterError", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
End Sub

Private Sub ProbeLeavePlotNumber(ByVal TestName As String, ByVal PlotNumber As String)
    On Error GoTo ProbeError
    Dim F As Form
    Dim AuditBefore As Long
    DoCmd.OpenForm "FS882-8x6XL"
    Set F = Forms("FS882-8x6XL")
    LogPlotState TestName & ".Before", PlotNumber
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    DoCmd.GoToRecord acDataForm, "FS882-8x6XL", acNewRec
    F.Controls("PlotNumber").SetFocus
    F.Controls("PlotNumber").Value = PlotNumber
    LogResult TestName, "DirtyBeforeLeavingKey", F.Dirty
    F.Controls("Location").SetFocus
    DoEvents
    LogResult TestName, "DirtyAfterLeavingKey", F.Dirty
    LogResult TestName, "NewRecordAfterLeavingKey", F.NewRecord
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    LogPlotState TestName & ".After", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    LogPlotState TestName & ".AfterError", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
End Sub

Private Sub ProbeCancel(ByVal TestName As String, ByVal PlotNumber As String)
    On Error GoTo ProbeError
    Dim F As Form
    Dim AuditBefore As Long
    DoCmd.OpenForm "FS882-8x6XL"
    Set F = Forms("FS882-8x6XL")
    LogPlotState TestName & ".Before", PlotNumber
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    DoCmd.GoToRecord acDataForm, "FS882-8x6XL", acNewRec
    F.Controls("PlotNumber").Value = PlotNumber
    F.Controls("Location").Value = "ORACLE CANCEL"
    LogResult TestName, "DirtyBeforeUndo", F.Dirty
    DoCmd.RunCommand acCmdUndo
    LogResult TestName, "DirtyAfterUndo", F.Dirty
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    LogPlotState TestName & ".After", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    LogPlotState TestName & ".AfterError", PlotNumber
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
End Sub

Public Function RunPlotCreateOracle(ByVal OutputPath As String, ByVal Mode As String, ByVal PlotNumber As String) As String
    On Error GoTo OracleError
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    LogResult "Oracle", "Mode", Mode
    LogResult "Oracle", "PlotNumber", PlotNumber
    LogResult "Oracle", "CurrProject", CurrProject()
    LogResult "Oracle", "InitialAuditStrength", clsVProReg.AuditStrength
    clsVProReg.AuditStrength = 2
    If Mode = "key-only" Then
        ProbeCreate Mode, PlotNumber, False, False
    ElseIf Mode = "env-only" Then
        ProbeCreate Mode, PlotNumber, True, False
    ElseIf Mode = "admin-only" Then
        ProbeCreate Mode, PlotNumber, False, True
    ElseIf Mode = "both-tables" Then
        ProbeCreate Mode, PlotNumber, True, True
    ElseIf Mode = "leave-key" Then
        ProbeLeavePlotNumber Mode, PlotNumber
    ElseIf Mode = "cancel-dirty" Then
        ProbeCancel Mode, PlotNumber
    Else
        Err.Raise vbObjectError + 2001, "RunPlotCreateOracle", "Unknown mode: " & Mode
    End If
    RunPlotCreateOracle = mOutput
    Exit Function

OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    RunPlotCreateOracle = mOutput
End Function

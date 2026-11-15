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
        "FROM ((Sample_Env AS env INNER JOIN Sample_Admin AS admin ON env.PlotNumber=admin.Plot) " & _
        "INNER JOIN Sample_SU AS su ON env.PlotNumber=su.PlotNumber) " & _
        "INNER JOIN Sample_Veg AS veg ON env.PlotNumber=veg.PlotNumber " & _
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

Private Sub ProbeForm(ByVal TestName As String, ByVal OldPlot As String, ByVal NewPlot As String, ByVal UndoChange As Boolean)
    On Error GoTo ProbeError
    Dim F As Form
    Dim RS As DAO.Recordset
    Dim AuditBefore As Long
    DoCmd.OpenForm "FS882-8x6XL"
    Set F = Forms("FS882-8x6XL")
    Set RS = F.RecordsetClone
    RS.FindFirst "PlotNumber=" & Quoted(OldPlot)
    If RS.NoMatch Then Err.Raise vbObjectError + 2101, "ProbeForm", "Source plot is not visible in FS882-8x6XL"
    F.Bookmark = RS.Bookmark
    LogResult TestName, "RecordSource", F.RecordSource
    LogResult TestName, "AllowEdits", F.AllowEdits
    LogResult TestName, "ControlLocked", F.Controls("PlotNumber").Locked
    LogResult TestName, "ControlEnabled", F.Controls("PlotNumber").Enabled
    LogResult TestName, "OldControlValue", F.Controls("PlotNumber").Value
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    F.Controls("PlotNumber").SetFocus
    F.Controls("PlotNumber").Value = NewPlot
    LogResult TestName, "DirtyAfterChange", F.Dirty
    If UndoChange Then
        DoCmd.RunCommand acCmdUndo
        LogResult TestName, "DirtyAfterUndo", F.Dirty
        LogResult TestName, "ControlAfterUndo", F.Controls("PlotNumber").Value
    Else
        F.Dirty = False
        LogResult TestName, "DirtyAfterCommit", F.Dirty
        LogResult TestName, "ControlAfterCommit", F.Controls("PlotNumber").Value
    End If
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    If Not F Is Nothing Then
        LogResult TestName, "DirtyAfterError", F.Dirty
        If F.Dirty Then DoCmd.RunCommand acCmdUndo
    End If
    DoCmd.Close acForm, "FS882-8x6XL", acSaveNo
End Sub

Private Sub ProbeDAO(ByVal TestName As String, ByVal OldPlot As String, ByVal NewPlot As String)
    On Error GoTo ProbeError
    Dim DB As DAO.Database
    Dim RS As DAO.Recordset
    Dim AuditBefore As Long
    Set DB = CurrentDb
    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    Set RS = DB.OpenRecordset("SELECT * FROM Sample_Env WHERE PlotNumber=" & Quoted(OldPlot), dbOpenDynaset)
    If RS.EOF Then Err.Raise vbObjectError + 2102, "ProbeDAO", "Source plot does not exist"
    RS.Edit
    RS!PlotNumber = NewPlot
    RS.Update
    RS.Close
    LogResult TestName, "AuditDeltaTotal", Scalar("SELECT Count(*) FROM Sample_Audit") - AuditBefore
    Exit Sub

ProbeError:
    LogResult TestName, "ErrorNumber", Err.Number
    LogResult TestName, "ErrorDescription", Err.Description
    On Error Resume Next
    RS.CancelUpdate
    RS.Close
End Sub

Public Function RunPlotRenumberOracle(ByVal OutputPath As String, ByVal Mode As String, ByVal NewPlot As String) As String
    On Error GoTo OracleError
    Dim OldPlot As String
    Dim CollisionPlot As String
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    OldPlot = SourcePlot()
    CollisionPlot = CStr(Scalar("SELECT TOP 1 PlotNumber FROM Sample_Env WHERE PlotNumber<>" & Quoted(OldPlot) & " ORDER BY PlotNumber"))
    LogResult "Oracle", "Mode", Mode
    LogResult "Oracle", "OldPlot", OldPlot
    LogResult "Oracle", "RequestedNewPlot", NewPlot
    LogResult "Oracle", "CollisionPlot", CollisionPlot
    LogResult "Oracle", "CurrProject", CurrProject()
    LogResult "Oracle", "InitialAuditStrength", clsVProReg.AuditStrength
    clsVProReg.AuditStrength = 2
    LogState Mode & ".Old.Before", OldPlot
    LogState Mode & ".New.Before", IIf(InStr(Mode, "collision") > 0, CollisionPlot, NewPlot)
    If Mode = "form-success" Then
        ProbeForm Mode, OldPlot, NewPlot, False
    ElseIf Mode = "form-cancel" Then
        ProbeForm Mode, OldPlot, NewPlot, True
    ElseIf Mode = "form-collision" Then
        ProbeForm Mode, OldPlot, CollisionPlot, False
    ElseIf Mode = "dao-success" Then
        ProbeDAO Mode, OldPlot, NewPlot
    ElseIf Mode = "dao-collision" Then
        ProbeDAO Mode, OldPlot, CollisionPlot
    Else
        Err.Raise vbObjectError + 2103, "RunPlotRenumberOracle", "Unknown mode: " & Mode
    End If
    LogState Mode & ".Old.After", OldPlot
    LogState Mode & ".New.After", IIf(InStr(Mode, "collision") > 0, CollisionPlot, NewPlot)
    RunPlotRenumberOracle = mOutput
    Exit Function

OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    RunPlotRenumberOracle = mOutput
End Function

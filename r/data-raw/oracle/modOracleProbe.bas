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

Private Sub ProbeFormCreateDelete(ByVal FormName As String, ByVal TableName As String, ByVal MarkerField As String, ByVal Marker As String, ByVal PlotNumber As String, Optional ByVal ValueField As String = "", Optional ByVal FieldValue As Variant)
    On Error GoTo ProbeError
    Dim F As Form
    Dim NewID As Variant
    Dim AuditBefore As Long
    Dim AuditAfterCreate As Long
    Dim AuditAfterDelete As Long

    DoCmd.OpenForm FormName
    Set F = Forms(FormName)
    LogResult FormName, "AllowAdditions", F.AllowAdditions
    LogResult FormName, "AllowDeletions", F.AllowDeletions
    LogResult FormName, "RecordSource", F.RecordSource
    LogResult FormName, "BeforeDelConfirm", F.BeforeDelConfirm
    LogResult FormName, "AfterDelConfirm", F.AfterDelConfirm

    AuditBefore = Scalar("SELECT Count(*) FROM Sample_Audit")
    DoCmd.GoToRecord acDataForm, FormName, acNewRec
    F.Controls("PlotNumber").Value = PlotNumber
    F.Controls(MarkerField).Value = Marker
    If Len(ValueField) > 0 Then F.Controls(ValueField).Value = FieldValue
    LogResult FormName, "IDWhileDirty", F.Controls("ID").Value
    If F.Dirty Then F.Dirty = False
    NewID = F.Controls("ID").Value
    LogResult FormName, "IDAfterCommit", NewID
    LogResult FormName, "StoredRowsAfterCreate", Scalar("SELECT Count(*) FROM [" & TableName & "] WHERE PlotNumber='" & Replace(PlotNumber, "'", "''") & "' AND [" & MarkerField & "]='" & Replace(Marker, "'", "''") & "'")
    If TableName = "Sample_Veg" Then
        F.Controls("Species").Value = "ORCLVE2"
        If F.Dirty Then F.Dirty = False
        LogResult FormName, "IDAfterSpeciesEdit", F.Controls("ID").Value
        LogResult FormName, "RowsWithEditedSpecies", Scalar("SELECT Count(*) FROM Sample_Veg WHERE PlotNumber='" & Replace(PlotNumber, "'", "''") & "' AND Species='ORCLVE2'")
        Marker = "ORCLVE2"
    End If
    AuditAfterCreate = Scalar("SELECT Count(*) FROM Sample_Audit")
    LogResult FormName, "AuditDeltaCreate", AuditAfterCreate - AuditBefore

    F.RecordsetClone.FindFirst "PlotNumber='" & Replace(PlotNumber, "'", "''") & "' AND [" & MarkerField & "]='" & Replace(Marker, "'", "''") & "'"
    If Not F.RecordsetClone.NoMatch Then F.Bookmark = F.RecordsetClone.Bookmark
    DoCmd.SetWarnings False
    DoCmd.RunCommand acCmdDeleteRecord
    DoCmd.SetWarnings True
    AuditAfterDelete = Scalar("SELECT Count(*) FROM Sample_Audit")
    LogResult FormName, "StoredRowsAfterDelete", Scalar("SELECT Count(*) FROM [" & TableName & "] WHERE PlotNumber='" & Replace(PlotNumber, "'", "''") & "' AND [" & MarkerField & "]='" & Replace(Marker, "'", "''") & "'")
    LogResult FormName, "AuditDeltaDelete", AuditAfterDelete - AuditAfterCreate
    DoCmd.Close acForm, FormName, acSaveNo
    Exit Sub

ProbeError:
    DoCmd.SetWarnings True
    LogResult FormName, "ErrorNumber", Err.Number
    LogResult FormName, "ErrorDescription", Err.Description
    On Error Resume Next
    DoCmd.Close acForm, FormName, acSaveNo
End Sub

Public Function RunChildOracle(ByVal OutputPath As String) As String
    On Error GoTo OracleError
    Dim PlotNumber As String
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    PlotNumber = CStr(Scalar("SELECT TOP 1 PlotNumber FROM Sample_Env ORDER BY PlotNumber"))
    LogResult "Oracle", "PlotNumber", PlotNumber
    LogResult "Oracle", "CurrProject", CurrProject()
    Dim PreviousAuditStrength As Variant
    PreviousAuditStrength = clsVProReg.AuditStrength
    clsVProReg.AuditStrength = 2
    LogResult "Oracle", "AuditStrength", clsVProReg.AuditStrength
    On Error Resume Next
    LogResult "Oracle", "GenUniqueID", Eval("GenUniqueID()")
    LogResult "Oracle", "GenUniqueIDError", Err.Number & ": " & Err.Description
    Err.Clear
    On Error GoTo OracleError

    ProbeFormCreateDelete "SubOtherXL", "Sample_Other", "DataName", "ORACLE_OTHER_FORM", PlotNumber, "DataItem", "created"
    ProbeFormCreateDelete "SoilHumusXL", "Sample_Humus", "Horizon", "ORCLH", PlotNumber, "Comment", "created"
    ProbeFormCreateDelete "SoilMineralXL", "Sample_Mineral", "Horizon", "ORCLM", PlotNumber, "Comments", "created"
    ProbeFormCreateDelete "SubVegAXL", "Sample_Veg", "Species", "ORCLVEG", PlotNumber, "Cover1", 1

    DoCmd.OpenForm "SubOtherXL"
    With Forms("SubOtherXL")
        DoCmd.GoToRecord acDataForm, "SubOtherXL", acNewRec
        .Controls("PlotNumber").Value = PlotNumber
        .Controls("DataName").Value = "ORACLE_CANCEL"
        LogResult "SubOtherXL", "CancelIDWhileDirty", .Controls("ID").Value
        DoCmd.RunCommand acCmdUndo
    End With
    DoCmd.Close acForm, "SubOtherXL", acSaveNo
    LogResult "SubOtherXL", "RowsAfterCancel", Scalar("SELECT Count(*) FROM Sample_Other WHERE PlotNumber='" & Replace(PlotNumber, "'", "''") & "' AND DataName='ORACLE_CANCEL'")
    clsVProReg.AuditStrength = PreviousAuditStrength
    RunChildOracle = mOutput
    Exit Function

OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    RunChildOracle = mOutput
End Function

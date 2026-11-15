Option Compare Database
Option Explicit

Private Sub Emit(ByVal outputPath As String, ByVal phase As String, ByVal species As String, ByVal unit As String, ByVal value As String)
    Dim handle As Integer
    handle = FreeFile
    Open outputPath For Append As #handle
    Print #handle, phase & vbTab & species & vbTab & unit & vbTab & value
    Close #handle
End Sub

Public Function RunDiagnosticClassificationProbe(ByVal outputPath As String) As String
    On Error GoTo Failed
    Dim db As DAO.Database
    Dim rs As DAO.Recordset
    Dim fieldIndex As Integer
    Dim observed As Variant
    Set db = CurrentDb()
    db.Execute "CREATE TABLE MyRS5 ([Species] TEXT(60), [UnitB] TEXT(10), [UnitA] TEXT(10), [UnitC] TEXT(10))", dbFailOnError
    db.Execute "CREATE TABLE Diagnostic ([Species] TEXT(60), [Unit] TEXT(10), [Diagnosis] TEXT(40))", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('D_CD','5 - 5','1 - 1',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('D_C','5 - +','1 - +',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('DD_TIE','5 - 8','5 - 1',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('CONSTANT','5 - 4','4 - 4',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('DD','2 - 7','2 - 1',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('D','3 - 4','1 - 1',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('NONE','1 - +','1 - 1',Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('ALL_NULL',Null,Null,Null)", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('NULL_FIRST',Null,'5 - 9','3 - 8')", dbFailOnError
    db.Execute "INSERT INTO MyRS5 VALUES ('IC_CHECK','2 - +','1 - +','1 - +')", dbFailOnError
    Open outputPath For Output As #1
    Print #1, "phase" & vbTab & "species" & vbTab & "unit" & vbTab & "value"
    Close #1
    Set rs = db.OpenRecordset("MyRS5", dbOpenSnapshot)
    Do Until rs.EOF
        For fieldIndex = 1 To rs.Fields.Count - 1
            Emit outputPath, "input", CStr(rs.Fields(0).Value), rs.Fields(fieldIndex).Name, Nz(rs.Fields(fieldIndex).Value, "<NULL>")
        Next fieldIndex
        rs.MoveNext
    Loop
    rs.Close
    observed = Eval("Diagnostic()")
    Set rs = db.OpenRecordset("SELECT Species, Unit, Diagnosis FROM Diagnostic ORDER BY Species", dbOpenSnapshot)
    Do Until rs.EOF
        Emit outputPath, "diagnosis", CStr(rs!Species), CStr(rs!Unit), CStr(rs!Diagnosis)
        rs.MoveNext
    Loop
    rs.Close
    RunDiagnosticClassificationProbe = outputPath
    Exit Function
Failed:
    On Error Resume Next
    Emit outputPath, "error", "", CStr(Err.Number), Err.Description
    RunDiagnosticClassificationProbe = "ERROR"
End Function

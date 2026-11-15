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

Private Sub LogFirst(ByVal TestName As String, ByVal TableName As String)
    Dim MyRS As DAO.Recordset
    Set MyRS = CurrentDb.OpenRecordset( _
        "SELECT PlotNumber, Species, Max(Cover1) AS MaxCover1, Max(Cover4) AS MaxCover4, " & _
        "First(Collected) AS FirstCollected, First(Flag) AS FirstFlag, " & _
        "First(Cultural1) AS FirstCultural1 " & _
        "FROM [" & TableName & "] GROUP BY PlotNumber, Species " & _
        "ORDER BY PlotNumber, Species", dbOpenSnapshot)
    If Not MyRS.EOF Then
        LogResult TestName, "MaxCover1", MyRS!MaxCover1
        LogResult TestName, "MaxCover4", MyRS!MaxCover4
        LogResult TestName, "FirstCollected", MyRS!FirstCollected
        LogResult TestName, "FirstFlag", MyRS!FirstFlag
        LogResult TestName, "FirstCultural1", MyRS!FirstCultural1
    End If
    MyRS.Close
End Sub

Private Sub ProbeOrder(ByVal TestName As String, ByVal IndexSql As String, Optional ByVal ReverseInsertion As Boolean = False)
    Dim MyDB As DAO.Database
    Dim MyRS As DAO.Recordset
    Set MyDB = CurrentDb()
    MyDB.Execute "DROP TABLE zOracleVegMerge", dbFailOnError
    MyDB.Execute "CREATE TABLE zOracleVegMerge ([PlotNumber] TEXT(7), [Species] TEXT(8), [Cover1] DOUBLE, [Cover4] DOUBLE, [Collected] TEXT(20), [Flag] TEXT(20), [Cultural1] TEXT(20))", dbFailOnError
    If ReverseInsertion Then
        MyDB.Execute "INSERT INTO zOracleVegMerge (PlotNumber, Species, Cover1, Cover4, Collected, Flag, Cultural1) VALUES ('ORC1234', 'ORCVEG', 2, 4, 'SECOND', 'SECOND', 'SECOND')", dbFailOnError
        MyDB.Execute "INSERT INTO zOracleVegMerge (PlotNumber, Species, Cover1, Collected, Flag, Cultural1) VALUES ('ORC1234', 'ORCVEG', 1, 'FIRST', 'FIRST', 'FIRST')", dbFailOnError
    Else
        MyDB.Execute "INSERT INTO zOracleVegMerge (PlotNumber, Species, Cover1, Collected, Flag, Cultural1) VALUES ('ORC1234', 'ORCVEG', 1, 'FIRST', 'FIRST', 'FIRST')", dbFailOnError
        MyDB.Execute "INSERT INTO zOracleVegMerge (PlotNumber, Species, Cover1, Cover4, Collected, Flag, Cultural1) VALUES ('ORC1234', 'ORCVEG', 2, 4, 'SECOND', 'SECOND', 'SECOND')", dbFailOnError
    End If
    If Len(IndexSql) > 0 Then MyDB.Execute IndexSql, dbFailOnError
    Set MyRS = MyDB.OpenRecordset("SELECT Collected FROM zOracleVegMerge", dbOpenSnapshot)
    If Not MyRS.EOF Then LogResult TestName, "ScanFirst", MyRS!Collected
    MyRS.Close
    LogFirst TestName, "zOracleVegMerge"
End Sub

Public Function RunVegOptimizeOracle(ByVal OutputPath As String) As String
    On Error GoTo OracleError
    Dim MyDB As DAO.Database
    Dim MyRS As DAO.Recordset
    mOutput = OutputPath
    Open mOutput For Output As #1
    Close #1
    Set MyDB = CurrentDb()
    LogResult "Query", "Filter", MyDB.QueryDefs("USysAllVeg").Properties("Filter").Value
    LogResult "Query", "FilterOnLoad", MyDB.QueryDefs("USysAllVeg").Properties("FilterOnLoad").Value
    LogResult "Query", "SQLHasLayer4", InStr(1, MyDB.QueryDefs("USysAllVeg").SQL, "Cover4", vbTextCompare) > 0
    On Error Resume Next
    MyDB.Execute "DROP TABLE zOracleVegMerge", dbFailOnError
    On Error GoTo OracleError
    MyDB.Execute "CREATE TABLE zOracleVegMerge ([PlotNumber] TEXT(7), [Species] TEXT(8), [Cover1] DOUBLE, [Cover4] DOUBLE, [Collected] TEXT(20), [Flag] TEXT(20), [Cultural1] TEXT(20))", dbFailOnError
    LogResult "Query", "ScratchCreated", True
    MyDB.Execute "INSERT INTO zOracleVegMerge (PlotNumber, Species, Cover1, Cover4, Collected) VALUES ('ORC1234', 'ORCVEG', 1, 4, 'FIRST')", dbFailOnError
    LogResult "Query", "ScratchInserted", True
    'Isolate the filter question with a two-layer scratch UNION.
    MyDB.CreateQueryDef "zOracleAllVeg", _
        "SELECT PlotNumber, '1' AS MyLayer, Species, Cover1 AS Cover FROM zOracleVegMerge WHERE Cover1 IS NOT NULL " & _
        "UNION SELECT PlotNumber, '4' AS MyLayer, Species, Cover4 AS Cover FROM zOracleVegMerge WHERE Cover4 IS NOT NULL"
    LogResult "Query", "ScratchQueryCreated", True
    LogResult "Query", "ScratchDirectLayer4", Scalar("SELECT Count(*) FROM zOracleAllVeg WHERE MyLayer='4'")
    LogResult "Query", "SavedSQLLayer4", Scalar("SELECT Count(*) FROM USysAllVeg WHERE MyLayer='4'")
    Set MyRS = MyDB.OpenRecordset("zOracleAllVeg", dbOpenSnapshot)
    LogResult "Query", "ScratchRecordsetLayer", MyRS!MyLayer
    MyRS.Close
    'The original query is inspected separately to avoid depending on its current data content.
    Set MyRS = MyDB.OpenRecordset("USysAllVeg", dbOpenSnapshot)
    If Not MyRS.EOF Then LogResult "Query", "SavedRecordsetFirstLayer", MyRS!MyLayer
    MyRS.Close
    ProbeOrder "InsertionOrder", ""
    ProbeOrder "DescendingIndex", "CREATE INDEX zOracleDescending ON zOracleVegMerge (PlotNumber, Species, Collected DESC)"
    ProbeOrder "AscendingIndex", "CREATE INDEX zOracleAscending ON zOracleVegMerge (PlotNumber, Species, Collected ASC)"
    ProbeOrder "ReverseInsertion", "", True
    RunVegOptimizeOracle = mOutput
    Exit Function
OracleError:
    LogResult "Oracle", "ErrorNumber", Err.Number
    LogResult "Oracle", "ErrorDescription", Err.Description
    RunVegOptimizeOracle = mOutput
End Function

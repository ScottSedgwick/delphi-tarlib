unit TestTarLib;
{

  Delphi DUnit Test Case
  ----------------------
  This unit contains a skeleton test case class generated by the Test Case Wizard.
  Modify the generated code to correctly setup and call the methods from the unit 
  being tested.

}

interface

uses
  TestFramework,
  System.Classes,
  TarLib;

type
  // Test methods for class TTarReader
  TestTTarReader = class(TTestCase)
  strict private
    FTarFile: TStream;
    FTarReader: TTarReader;
  private
    procedure CheckStreamsEqual(expected, actual: TStream);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHeaderCount;
    procedure TestHeaderOne;
    procedure TestHeaderTwo;
    procedure TestContentOne;
    procedure TestContentTwo;
  end;


  // Test methods for class TTarWriter
  TestTTarWriter = class(TTestCase)
  private
    procedure CheckStreamsEqual(expected, actual: TStream);
  published
    procedure TestGeneratedTarFile;
  end;

implementation

uses
  System.DateUtils,
  System.SysUtils;

{ TestTTarReader }

procedure TestTTarReader.CheckStreamsEqual(expected, actual: TStream);
var
  bE, bA: Byte;
begin
  CheckEquals(expected.Size, actual.Size);
  expected.Position := 0;
  actual.Position := 0;
  while expected.Position < expected.Size do
  begin
    expected.Read(bE, 1);
    actual.Read(bA, 1);
    CheckEquals(bE, bA);
  end;
end;

procedure TestTTarReader.SetUp;
begin
  FTarFile := TFileStream.Create('../../datafiles/testTarFile.tar', fmOpenRead);
  FTarReader := TTarReader.Create(FTarFile);
end;

procedure TestTTarReader.TearDown;
begin
  FTarReader.Free;
  FTarReader := nil;
  FTarFile.Free;
  FTarFile := nil;
end;

procedure TestTTarReader.TestContentOne;
var
  expected: TStringStream;
  actual: TMemoryStream;
begin
  expected := TStringStream.Create;
  try
    expected.WriteString('This is the top level file.' + Chr(10));
    actual := TMemoryStream.Create;
    try
      FTarReader.CopyFileTo(0, actual);
      CheckStreamsEqual(expected, actual);
    finally
      actual.Free;
    end;
  finally
    expected.Free;
  end;
end;

procedure TestTTarReader.TestContentTwo;
var
  expected: TStringStream;
  actual: TMemoryStream;
begin
  expected := TStringStream.Create;
  try
    expected.WriteString('This is the file in the subdirectory.' + Chr(10));
    actual := TMemoryStream.Create;
    try
      FTarReader.CopyFileTo(1, actual);
      CheckStreamsEqual(expected, actual);
    finally
      actual.Free;
    end;
  finally
    expected.Free;
  end;
end;

procedure TestTTarReader.TestHeaderCount;
begin
  CheckEquals(2, FTarReader.Count);
end;

procedure TestTTarReader.TestHeaderOne;
var
  entry: TTarEntry;
  d: TDateTime;
begin
  d := EncodeDateTime(2018, 11, 7, 15, 17, 31, 0);
  entry := FTarReader.Header[0];
  CheckEquals('file1.txt', entry.filename);
  Check(mRW = entry.mode.UserMode);
  Check(mR = entry.mode.GroupMode);
  Check(mR = entry.mode.GlobalMode);
  CheckEquals(767, entry.uid);
  CheckEquals(24, entry.gid);
  CheckEquals(d, entry.mtime);
  CheckEquals('ssedgwick', entry.uname);
  CheckEquals('staff', entry.gname);
  CheckEquals(28, entry.size);
end;

procedure TestTTarReader.TestHeaderTwo;
var
  entry: TTarEntry;
  d: TDateTime;
begin
  d := EncodeDateTime(2018, 11, 7, 15, 17, 59, 0);
  entry := FTarReader.Header[1];
  CheckEquals('subdir1/file2.txt', entry.filename);
  Check(mRW = entry.mode.UserMode);
  Check(mR = entry.mode.GroupMode);
  Check(mR = entry.mode.GlobalMode);
  CheckEquals(767, entry.uid);
  CheckEquals(24, entry.gid);
  CheckEquals(d, entry.mtime);
  CheckEquals('ssedgwick', entry.uname);
  CheckEquals('staff', entry.gname);
  CheckEquals(38, entry.size);
end;

{ TestTTarWriter }

procedure TestTTarWriter.CheckStreamsEqual(expected, actual: TStream);
var
  bE, bA: Byte;
begin
  CheckEquals(expected.Size, actual.Size);
  expected.Position := 0;
  actual.Position := 0;
  while expected.Position < expected.Size do
  begin
    expected.Read(bE, 1);
    actual.Read(bA, 1);
    CheckEquals(bE, bA);
  end;
end;

procedure TestTTarWriter.TestGeneratedTarFile;
var
  FTarFile, FTestFile: TFileStream;
  FTarWriter: TTarWriter;
  m: TFileMode;
  d: TDateTime;
  strm: TStringStream;
begin
  FTarFile := TFileStream.Create('../../datafiles/tempTarFile.tar', fmCreate);
  FTarWriter := TTarWriter.Create(FTarFile);
  try
    m := Mode(mRW, mR, mR);
    // Add file1
    strm := TStringStream.Create('This is the top level file.' + Chr(10));
    try
      d := EncodeDateTime(2018, 11, 7, 15, 17, 31, 0);
      FTarWriter.AddEntry('file1.txt', m, 767, 24, d, 'ssedgwick', 'staff', strm);
    finally
      strm.Free;
    end;
    //Add file2
    strm := TStringStream.Create('This is the file in the subdirectory.' + Chr(10));
    try
      d := EncodeDateTime(2018, 11, 7, 15, 17, 59, 0);
      FTarWriter.AddEntry('subdir1/file2.txt', m, 767, 24, d, 'ssedgwick', 'staff', strm);
    finally
      strm.Free;
    end;
  finally
    FTarWriter.Free;
    FTarFile.Free;
  end;

  FTarFile := TFileStream.Create('../../datafiles/tempTarFile.tar', fmOpenRead);
  FTestFile := TFileStream.Create('../../datafiles/testTarFile.tar', fmOpenRead);
  try
    CheckStreamsEqual(FTarFile, FTestFile);
  finally
    FTarFile.Free;
    FTestFile.Free;
  end;
end;

initialization
  // Register any test cases with the test runner
  RegisterTest(TestTTarReader.Suite);
  RegisterTest(TestTTarWriter.Suite);
end.


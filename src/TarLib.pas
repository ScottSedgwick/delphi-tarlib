unit TarLib;

interface

uses
  System.Classes;

type
  TUserFileMode = (mR, mW, mX, mRW, mRX, mWX, mRWX);

  TFileMode = record
    UserMode, GroupMode, GlobalMode: TUserFileMode;
    function Be(const AUserMode, AGroupMode, AGlobalMode: TUserFileMode): TFileMode;
  end;

  TTarEntry = record
    filename: string;
    mode: TFileMode;
    uid: Integer;
    gid: Integer;
    mtime: TDateTime;
    uname: string;
    gname: string;
    size: Int64;
  end;

  TTarReader = class
  private
    FTarStream: TStream;
    FHeaders: TArray<TTarEntry>;
    procedure AddHeader(header: TTarEntry);
    procedure ReadFileHeaders;
    function GetHeader(Index: Integer): TTarEntry;
    function GetCount: Integer;
  public
    constructor Create(ATarStream: TStream);
    procedure CopyFileTo(FileIndex: Integer; AStream: TStream);
    property Count: Integer read GetCount;
    property Header[Index: Integer]: TTarEntry read GetHeader;
  end;

  TTarWriter = class
  private
    FTarStream: TStream;
    FClosed: Boolean;
  public
    constructor Create(ATarStream: TStream);
    destructor Destroy; override;
    procedure AddEntry(AFilename: string; AMode: TFileMode; AUid, AGid: Integer;
      AMTime: TDateTime; AUName, AGName: string; AContent: TStream); overload;
    procedure AddEntry(AEntry: TTarEntry; AContent: TStream); overload;
    procedure Close;
  end;

function Mode(AUserMode, AGroupMode, AGlobalMode: TUserFileMode): TFileMode;

implementation

uses
  System.DateUtils,
  System.SysUtils;

const
  BLOCK_SIZE = 512;

type
  TFileModeHelper = record helper for TFileMode
    procedure FromString(Value: string);
    function ToString: string;
  end;

  TUserFileModeHelper = record helper for TUserFileMode
    procedure FromInt(Value: Integer);
    function ToInt: Integer;
  end;

function IntToOct(Value: Integer; PadToLength: Integer = 0): string;
var
  I: Integer;
begin
  if (Value < 0) then
    raise Exception.CreateFmt('Invalid argument passed to IntToOct (negative). Value: %d', [Value]);
  if (Value = 0) then
    Result := '0'
  else
  begin
    Result := '';
    while Value > 0 do
    begin
      Result := IntToStr(Value mod 8) + Result;
      Value := Value div 8;
    end;
  end;
  if (PadToLength > Length(Result)) then
  begin
    for I := 1 to (PadToLength - Length(Result)) do
      Result := '0' + Result;
  end;
end;

function Mode(AUserMode, AGroupMode, AGlobalMode: TUserFileMode): TFileMode;
begin
  Result.Be(AUserMode, AGroupMode, AGlobalMode);
end;

function OctToInt(const Value: string): Int64;
var
  s: string;
  I: Integer;
begin
  s := Trim(Value);
  Result := 0;
  for I := 1 to Length(s) do
    Result := Result * 8 + Ord(s[I]) - Ord('0');
end;

function PadSize(const Value, BlockSize: Int64): Int64;
begin
  Result := BlockSize - (Value mod BlockSize);
end;

function PadTo(const Value, BlockSize: Int64): Int64;
begin
  Result := Value + PadSize(Value, BlockSize);
end;

function ReadString(AStream: TStream; const Length: Integer): string;
var
  buf: TArray<Byte>;
begin
  SetLength(buf, Length);
  AStream.Read(buf, Length);
  Result := Trim(TEncoding.ASCII.GetString(buf));
end;

procedure WriteString(s: TStream; const Value: string; const Size: Integer = 0);
var
  b: TArray<byte>;
  initSize, tgtSize, I: Integer;
begin
  if Size <> 0 then
    tgtSize := Size;
  b := TEncoding.ASCII.GetBytes(Value);
  initSize := Length(b);
  if tgtSize <> initSize then
  begin
    SetLength(b, tgtSize);
    for I := initSize to tgtSize - 1 do
      b[I] := 0;
  end;
  s.Write(b, 0, Length(b));
end;

{ TTarWriter }

procedure TTarWriter.AddEntry(AFilename: string; AMode: TFileMode; AUid,
  AGid: Integer; AMTime: TDateTime; AUName, AGName: string; AContent: TStream);
var
  ms: TMemoryStream;
  iCheckSum: Int64;
  b: Byte;
  size, chksum: string;
begin
  if not Assigned(AContent) then
    raise Exception.Create('TTarWriter.AddEntry: Uninitialized stream passed in as content.');
  ms := TMemoryStream.Create;
  try
    // Write file header to stream
    size := IntToOct(AContent.Size, 11) + ' ';
    WriteString(ms, AFilename, 100);
    WriteString(ms, AMode.ToString, 8);
    WriteString(ms, Format('%.6d ', [AUid]), 8);
    WriteString(ms, Format('%.6d ', [AGid]), 8);
    WriteString(ms, size, 12);
    WriteString(ms, IntToOct(DateTimeToUnix(AMTime, False), 11) + ' ', 12);
    WriteString(ms, '       ', 7); // CheckSum.  Calculate below.
    WriteString(ms, ' ', 1);       // Old link indicator. Not used for UStar format.
    WriteString(ms, '0', 1);       // Type flag. Hard coded to Normal File for now.
    WriteString(ms, '', 100);      // Link name. Hard coded to empty, because all files are normal.
    WriteString(ms, 'ustar', 6);   // UStar tar format
    WriteString(ms, '00', 2);      // Version
    WriteString(ms, AUName, 32);
    WriteString(ms, AGName, 32);
    WriteString(ms, '000000 ', 8); // DevMajor
    WriteString(ms, '000000 ', 8); // DevMinor
    WriteString(ms, '', 155);      // Prefix

    // Calculate checksum of header and overwrite it
    ms.Position := 0;
    iCheckSum := 0;
    while (ms.Position < ms.Size) do
    begin
      ms.Read(b, 1);
      iCheckSum := iCheckSum + b;
    end;
    chksum := IntToOct(iCheckSum, 6);
    ms.Position := 148;
    WriteString(ms, chksum, 7);
    ms.Position := ms.Size;

    // Tar pads to 512 byte boundary on the header.
    WriteString(ms, '', 12);

    // Write file contents to stream
    ms.CopyFrom(AContent, AContent.Size);

    // Pad end of file to 512 byte boundary
    WriteString(ms, '', PadSize(AContent.Size, BLOCK_SIZE));
    ms.Position := 0;

    // Copy to output stream
    FTarStream.CopyFrom(ms, ms.Size);
  finally
    ms.Free;
  end;
end;

procedure TTarWriter.AddEntry(AEntry: TTarEntry; AContent: TStream);
begin
  AddEntry(AEntry.filename, AEntry.mode, AEntry.Uid, AEntry.Gid, AEntry.MTime,
    AEntry.UName, AEntry.GName, AContent);
end;

procedure TTarWriter.Close;
begin
  if not FClosed then
  begin
    FClosed := True;
    WriteString(FTarStream, '', 1024);
  end;
end;

constructor TTarWriter.Create(ATarStream: TStream);
begin
  inherited Create;
  FTarStream := ATarStream;
  FClosed := False;
end;

destructor TTarWriter.Destroy;
begin
  Close;
  inherited;
end;

{ TTarReader }

procedure TTarReader.AddHeader(header: TTarEntry);
begin
  SetLength(FHeaders, Length(FHeaders) + 1);
  FHeaders[Length(FHeaders) - 1] := header;
end;

procedure TTarReader.CopyFileTo(FileIndex: Integer; AStream: TStream);
var
  I, P: Integer;
begin
  P := BLOCK_SIZE;
  for I := 0 to FileIndex - 1 do
    P := P + BLOCK_SIZE + PadTo(FHeaders[I].size, BLOCK_SIZE);
  FTarStream.Position := P;
  AStream.CopyFrom(FTarStream, FHeaders[FileIndex].size);
end;

constructor TTarReader.Create(ATarStream: TStream);
begin
  inherited Create;
  FTarStream := ATarStream;
  ReadFileHeaders;
end;

function TTarReader.GetCount: Integer;
begin
  Result := Length(FHeaders);
end;

function TTarReader.GetHeader(Index: Integer): TTarEntry;
begin
  Result := FHeaders[Index];
end;

procedure TTarReader.ReadFileHeaders;
var
  entry: TTarEntry;
begin
  FTarStream.Position := 0;
  SetLength(FHeaders, 0);
  while (FTarStream.Position < (FTarStream.Size - BLOCK_SIZE)) do
  begin
    entry.filename := ReadString(FTarStream, 100);
    if entry.filename = '' then
      FTarStream.Position := FTarStream.Position + 924
    else
    begin
      // Read header values
      entry.mode.FromString(ReadString(FTarStream, 8));
      entry.uid := StrToInt(ReadString(FTarStream, 8));
      entry.gid := StrToInt(ReadString(FTarStream, 8));
      entry.size := OctToInt(ReadString(FTarStream, 12));
      entry.mtime := UnixToDateTime(OctToInt(ReadString(FTarStream, 12)), False);
      FTarStream.Position := FTarStream.Position + 117;  // Skip constant values
      entry.uname := ReadString(FTarStream, 32);
      entry.gname := ReadString(FTarStream, 32);
      // Skip to end of file contents
      FTarStream.Position := FTarStream.Position + 183 + PadTo(entry.size, BLOCK_SIZE);
      // Add header to array
      AddHeader(entry);
    end;
  end;
end;

{ TFileMode }

function TFileMode.Be(const AUserMode, AGroupMode,
  AGlobalMode: TUserFileMode): TFileMode;
begin
  UserMode := AUserMode;
  GroupMode := AGroupMode;
  GlobalMode := AGlobalMode;
  Result := Self;
end;

{ TFileModeHelper }

procedure TFileModeHelper.FromString(Value: string);
begin
  Value := Trim(Value);
  if Length(Value) >= 6 then
  begin
    UserMode.FromInt(Ord(Value[4]) - Ord('0'));
    GroupMode.FromInt(Ord(Value[5]) - Ord('0'));
    GlobalMode.FromInt(Ord(Value[6]) - Ord('0'));
  end;
end;

function TFileModeHelper.ToString: string;
begin
  Result := Format('000%d%d%d ', [UserMode.ToInt, GroupMode.ToInt, GlobalMode.ToInt]);
end;

{ TUserFileModeHelper }

procedure TUserFileModeHelper.FromInt(Value: Integer);
begin
  case Value of
    1: Self := mX;
    2: Self := mW;
    3: Self := mWX;
    4: Self := mR;
    5: Self := mRX;
    6: Self := mRW;
    7: Self := mRWX;
  end;
end;

function TUserFileModeHelper.ToInt: Integer;
begin
  case Self of
    mR  : Result := 4;
    mW  : Result := 2;
    mX  : Result := 1;
    mRW : Result := 6;
    mRX : Result := 5;
    mWX : Result := 3;
    mRWX: Result := 7;
  end;
end;

end.

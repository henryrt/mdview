uses CRT, DOS;

const
  MaxLines = 10000;

type
  TStyle = (
    stNormal,
    stBold,
    stCode,
    stHeading1,
    stHeading2
  );

  TRun = record
    Style : TStyle;
    Text  : string;
  end;

  TLine = record
    RunCount : Integer;
    Runs     : array[1..20] of TRun;
  end;

var
  Lines: array[1..MaxLines] of TLine;
  LineCount: Integer;
  TopLine : Integer;


procedure DrawStatusBar;
begin
  TextColor(Black);
  TextBackground(LightGray);

  GotoXY(1,25);
  ClrEol;

  Write('Line ', TopLine,
        ' of ', LineCount,
        '  Esc=Quit');

  TextColor(LightGray);
  TextBackground(Black);
end;

procedure PaintDisplay();
var 
  Row : Integer;
begin  
  TextColor(White);
  TextBackground(Blue);
  ClrScr;
  for Row := 1 to 24 do
  begin
    GotoXY(1, Row);
    Write(Copy(Lines[TopLine + Row - 1].Runs[1].Text, 1, 80));
  end;
  DrawStatusBar;
end;

procedure HandleInput();
var
  Key: Char;
begin
  Key := ReadKey;

  if Ord(Key) = 27 then
  begin
    TextBackground(Black);
    TextColor(LightGray);
    ClrScr;
    GotoXY(1,1);
    Halt(0);      { ESC quits }
  end;

  if Key = #0 then
  begin
    Key := ReadKey;

//    WriteLn('Special key: ', Ord(Key));

    case Ord(Key) of
      72: Dec(TopLine);      { Up }
      80: Inc(TopLine);      { Down }
      73: Dec(TopLine,23);   { PgUp }
      81: Inc(TopLine,23);   { PgDn }
      71: TopLine := 1;      { Home }
      79: TopLine := LineCount-23; { End }
    end;
    if TopLine < 1 then TopLine := 1;
    if TopLine > LineCount-23 then TopLine := LineCount-23;
  end;
end;

procedure LoadFile(const FileName: string);
var
  F : Text;
  S : string;
begin
  LineCount := 0;

  Assign(F, FileName);
  Reset(F);

  while (not Eof(F)) and (LineCount < MaxLines) do
  begin
    ReadLn(F, S);
    Inc(LineCount);
  
    Lines[LineCount].RunCount := 1;
    Lines[LineCount].Runs[1].Style := stNormal;
    Lines[LineCount].Runs[1].Text := S;  end;

  Close(F);
end;


BEGIN // Main program
  if ParamCount < 1 then
  begin
    WriteLn('Usage: MdView <filename>');
    Halt(1);
  end;

  LoadFile(ParamStr(1));
  TopLine := 1;

  repeat
    PaintDisplay();
    HandleInput();
  until False;
END.
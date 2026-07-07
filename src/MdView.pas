uses CRT, DOS;

const
  MaxLines = 10000;

var
  Lines: array[1..MaxLines] of string;
  LineCount: Integer;

  TopLine : Integer;

procedure PaintDisplay();
var 
  Row : Integer;
begin  
  ClrScr;
  for Row := 1 to 25 do
  begin
    GotoXY(1, Row);
    Write(Copy(Lines[TopLine + Row - 1], 1, 80));
  end;
end;

procedure HandleInput();
var
  Key: Char;
begin
  Key := ReadKey;

  if Ord(Key) = 27 then
      Halt(0);      { ESC quits }

  if Key = #0 then
  begin
    Key := ReadKey;

//    WriteLn('Special key: ', Ord(Key));

    case Ord(Key) of
      72: Dec(TopLine);      { Up }
      80: Inc(TopLine);      { Down }
      73: Dec(TopLine,24);   { PgUp }
      81: Inc(TopLine,24);   { PgDn }
      71: TopLine := 1;      { Home }
      79: TopLine := LineCount-24; { End }
    end;
    if TopLine < 1 then TopLine := 1;
    if TopLine > LineCount-24 then TopLine := LineCount-24;
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
    Lines[LineCount] := S;
  end;

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
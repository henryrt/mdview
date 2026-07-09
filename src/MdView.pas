program MdView;

{$MODE OBJFPC} {$H+}

uses
  crt, sysutils;

const
  // Extended key codes for DOS keyboard scanning
  KEY_ESC   = #27;
  KEY_UP    = #72;
  KEY_DOWN  = #80;
  KEY_PGUP  = #73;
  KEY_PGDN  = #81;
  KEY_HOME  = #71;
  KEY_END   = #79;

  // Classic Turbo Pascal color palette definitions
  TP_BACKGROUND = Blue;

type
  // Available styles mapping to DOS text attribute colors
  TStyle = (
    sNormal,      // Light gray text
    sBold,        // High-intensity white text
    sItalic,      // Cyan text (italic simulation in DOS)
    sCode,        // Light Cyan inline text
    sHeading,     // High-intensity Yellow text
    sCodeBlock,   // Light Green block code text
    sBulletMark   // Bright Cyan color specifically for bullet point indicators
  );

  // A Run is a contiguous segment of text sharing a single style
  TRun = record
    Text: string;
    Style: TStyle;
  end;

  // A Line holds an array of styled Runs
  TLine = record
    Runs: array of TRun;
    IsCodeBlockLine: Boolean;
    IsHeadingLine: Boolean;
  end;

  // The parsed document structure
  TDocument = record
    Lines: array of TLine;
    LineCount: Integer;
  end;

var
  Doc: TDocument;
  CurrentScrollRow: Integer; // Topmost visible line index (0-based)
  TerminalHeight: Integer;   // Detected screen height (typically 25)
  TerminalWidth: Integer;    // Detected screen width (typically 80)
  Running: Boolean;

{ Helper: Appends a styled text run to a line }
procedure AddRun(var Line: TLine; const AText: string; AStyle: TStyle);
var
  Len: Integer;
begin
  if AText = '' then Exit;
  Len := Length(Line.Runs);
  SetLength(Line.Runs, Len + 1);
  Line.Runs[Len].Text := AText;
  Line.Runs[Len].Style := AStyle;
end;

{ Character scanner that parses inline markdown tags (*, **, `) into runs }
procedure ParseInlineStyles(var Line: TLine; const SourceText: string; DefaultStyle: TStyle);
var
  I: Integer;
  CurrentToken: string;
  CurrentStyle: TStyle;
  Len: Integer;
  Ch, NextCh: Char;
begin
  CurrentToken := '';
  CurrentStyle := DefaultStyle;
  I := 1;
  Len := Length(SourceText);

  while I <= Len do
  begin
    Ch := SourceText[I];
    if I < Len then NextCh := SourceText[I + 1] else NextCh := #0;

    // Check for Bold (** or __)
    if ((Ch = '*') and (NextCh = '*')) or ((Ch = '_') and (NextCh = '_')) then
    begin
      // Save what we have accumulated so far
      if CurrentToken <> '' then
      begin
        AddRun(Line, CurrentToken, CurrentStyle);
        CurrentToken := '';
      end;
      
      // Toggle Style
      if CurrentStyle = sBold then
        CurrentStyle := DefaultStyle
      else
        CurrentStyle := sBold;
        
      Inc(I, 2); // Skip both formatting characters
    end
    // Check for Italic (* or _)
    else if (Ch = '*') or (Ch = '_') then
    begin
      if CurrentToken <> '' then
      begin
        AddRun(Line, CurrentToken, CurrentStyle);
        CurrentToken := '';
      end;
      
      if CurrentStyle = sItalic then
        CurrentStyle := DefaultStyle
      else
        CurrentStyle := sItalic;
        
      Inc(I);
    end
    // Check for Inline Code (`)
    else if Ch = '`' then
    begin
      if CurrentToken <> '' then
      begin
        AddRun(Line, CurrentToken, CurrentStyle);
        CurrentToken := '';
      end;
      
      if CurrentStyle = sCode then
        CurrentStyle := DefaultStyle
      else
        CurrentStyle := sCode;
        
      Inc(I);
    end
    else
    begin
      // Append normal character to active buffer
      CurrentToken := CurrentToken + Ch;
      Inc(I);
    end;
  end;

  // Flush any leftover text in the buffer
  if CurrentToken <> '' then
    AddRun(Line, CurrentToken, CurrentStyle);
end;

{ Parses raw markdown string input line into the structured Line/Runs format }
procedure ParseLine(const RawLine: string; var InCodeBlock: Boolean);
var
  Trimmed: string;
  Idx: Integer;
  NewLine: TLine;
begin
  NewLine.Runs := nil;
  NewLine.IsCodeBlockLine := False;
  NewLine.IsHeadingLine := False;
  Trimmed := Trim(RawLine);

  // 1. Handle Code Block Markdown Boundary (```)
  if Copy(Trimmed, 1, 3) = '```' then
  begin
    InCodeBlock := not InCodeBlock;
    NewLine.IsCodeBlockLine := True;
    // Render the boundary line as gray accent
    AddRun(NewLine, '--------------------------------------------------', sCodeBlock);
    
    Idx := Length(Doc.Lines);
    SetLength(Doc.Lines, Idx + 1);
    Doc.Lines[Idx] := NewLine;
    Inc(Doc.LineCount);
    Exit;
  end;

  // 2. Parse inside Code Block state
  if InCodeBlock then
  begin
    NewLine.IsCodeBlockLine := True;
    // Keep absolute spacing untouched inside code blocks
    AddRun(NewLine, RawLine, sCodeBlock);
  end
  // 3. Parse Headings (#, ##, ###)
  else if (Length(Trimmed) > 0) and (Trimmed[1] = '#') then
  begin
    NewLine.IsHeadingLine := True;
    // Determine heading level and strip prefix
    Idx := 1;
    while (Idx <= Length(Trimmed)) and (Trimmed[Idx] = '#') do
      Inc(Idx);
    
    // Skip empty spaces after header symbol
    while (Idx <= Length(Trimmed)) and (Trimmed[Idx] = ' ') do
      Inc(Idx);
      
    // Parse the rest of the heading text
    ParseInlineStyles(NewLine, Copy(Trimmed, Idx, MaxInt), sHeading);
  end
  // 4. Parse Bullet Lists (* , - )
  else if (Copy(Trimmed, 1, 2) = '* ') or (Copy(Trimmed, 1, 2) = '- ') then
  begin
    // Insert a nice IBM DOS Bullet char (Code 249 is a middle dot, Code 16 is a pointer)
    AddRun(NewLine, '  ' + #249 + ' ', sBulletMark);
    ParseInlineStyles(NewLine, Copy(Trimmed, 3, MaxInt), sNormal);
  end
  // 5. Normal Line Parse
  else
  begin
    ParseInlineStyles(NewLine, RawLine, sNormal);
  end;

  // Append constructed line object to document storage
  Idx := Length(Doc.Lines);
  SetLength(Doc.Lines, Idx + 1);
  Doc.Lines[Idx] := NewLine;
  Inc(Doc.LineCount);
end;

{ Loads a given text file path and populates Doc structures }
function LoadMarkdownFile(const FileName: string): Boolean;
var
  F: TextFile;
  RawLine: string;
  InCodeBlock: Boolean;
begin
  if not FileExists(FileName) then
  begin
    LoadMarkdownFile := False;
    Exit;
  end;

  AssignFile(F, FileName);
  Reset(F);

  Doc.Lines := nil;
  Doc.LineCount := 0;
  InCodeBlock := False;

  while not Eof(F) do
  begin
    ReadLn(F, RawLine);
    ParseLine(RawLine, InCodeBlock);
  end;

  CloseFile(F);
  LoadMarkdownFile := True;
end;

{ Applies terminal colors mapped to the structural token styles }
procedure ApplyStyleColor(Style: TStyle);
begin
  // Set the uniform background to classic Turbo Pascal Blue
  TextBackground(TP_BACKGROUND);

  case Style of
    sNormal:
      TextColor(LightGray);
    sBold:
      TextColor(White);
    sItalic:
      TextColor(Cyan);
    sCode:
      TextColor(LightCyan);
    sHeading:
      TextColor(Yellow);
    sCodeBlock:
      TextColor(LightGreen);
    sBulletMark:
      TextColor(LightCyan);
  end;
end;

{ Draws a line containing runs to the terminal window screen }
procedure DrawLine(const Line: TLine);
var
  I: Integer;
begin
  if Length(Line.Runs) = 0 then
  begin
    WriteLn;
    Exit;
  end;

  for I := 0 to High(Line.Runs) do
  begin
    ApplyStyleColor(Line.Runs[I].Style);
    Write(Line.Runs[I].Text);
  end;
  WriteLn;
end;

{ Renders a full frame of text to the viewport with a bottom status bar }
procedure RenderScreen;
var
  I, ScreenLineLimit, LineIdx: Integer;
begin
  // Set classic Blue background and clear screen to apply it globally
  TextBackground(TP_BACKGROUND);
  TextColor(LightGray);
  ClrScr;
  
  // Save space at bottom for the interactive status bar
  ScreenLineLimit := TerminalHeight - 2;
  
  for I := 0 to ScreenLineLimit do
  begin
    LineIdx := CurrentScrollRow + I;
    if LineIdx < Doc.LineCount then
    begin
      GotoXY(1, I + 1);
      DrawLine(Doc.Lines[LineIdx]);
    end;
  end;

  // Draw Bottom Status Bar (Black on Light Gray)
  TextColor(Black);
  TextBackground(LightGray);
  GotoXY(1, TerminalHeight);
  Write(Format(' [ESC/Q] Exit | [Up/Down/PgUp/PgDn] Scroll | Line %d/%d ', 
        [CurrentScrollRow + 1, Doc.LineCount]));
  
  // Fill rest of status line to avoid background bleeding
  for I := WhereX to TerminalWidth do
    Write(' ');

  // Return pointer to standard input space and restore defaults
  GotoXY(1, TerminalHeight);
  NormVideo;
end;

{ Dynamic viewport controller scanning for user keystrokes }
procedure HandleInput;
var
  Ch: Char;
begin
  Ch := ReadKey;
  
  // Handle Q or Escape keys to safely shut down
  if (Ch = 'q') or (Ch = 'Q') or (Ch = KEY_ESC) then
  begin
    Running := False;
    Exit;
  end;

  // Handle DOS extended arrow codes (#0 prefix)
  if Ch = #0 then
  begin
    Ch := ReadKey; // Fetch secondary key byte
    case Ch of
      KEY_UP:
        begin
          if CurrentScrollRow > 0 then
            Dec(CurrentScrollRow);
        end;
      KEY_DOWN:
        begin
          if CurrentScrollRow < (Doc.LineCount - (TerminalHeight - 2)) then
            Inc(CurrentScrollRow);
        end;
      KEY_PGUP:
        begin
          Dec(CurrentScrollRow, TerminalHeight - 2);
          if CurrentScrollRow < 0 then
            CurrentScrollRow := 0;
        end;
      KEY_PGDN:
        begin
          Inc(CurrentScrollRow, TerminalHeight - 2);
          if CurrentScrollRow > (Doc.LineCount - (TerminalHeight - 2)) then
            CurrentScrollRow := Doc.LineCount - (TerminalHeight - 2);
          if CurrentScrollRow < 0 then
            CurrentScrollRow := 0;
        end;
      KEY_HOME:
        begin
          CurrentScrollRow := 0;
        end;
      KEY_END:
        begin
          CurrentScrollRow := Doc.LineCount - (TerminalHeight - 2);
          if CurrentScrollRow < 0 then
            CurrentScrollRow := 0;
        end;
    end;
  end;
end;

{ Entry Point }
var
  InputFile: string;
begin
  if ParamCount < 1 then
  begin
    WriteLn('Markdown Viewer for DOS (go32v2)');
    WriteLn('Usage: mdview.exe <filename.md>');
    Exit;
  end;

  InputFile := ParamStr(1);
  WriteLn('Reading input structure: ', InputFile);
  
  if not LoadMarkdownFile(InputFile) then
  begin
    WriteLn('Fatal: Failed to parse input file path.');
    Exit;
  end;

  // Initialize terminal state dimensions
  TerminalHeight := ScreenHeight;
  TerminalWidth := ScreenWidth;
  CurrentScrollRow := 0;
  Running := True;

  // Set classic background before entering the interactive loop
  TextBackground(TP_BACKGROUND);
  TextColor(LightGray);
  ClrScr;

  // Interactive Viewport Loop
  while Running do
  begin
    RenderScreen;
    HandleInput;
  end;

  // Restore Terminal environment on exit
  NormVideo;
  ClrScr;
  WriteLn('Thank you for using MdView!');
end.
{
   Utility functions and definitions used by the LSP client
   (C) PyScripter 2021
}


unit LspUtils;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Win.ComObj,
  WinApi.WinInet,
  Winapi.ShLwApi,
  WinApi.Windows;


type
{$SCOPEDENUMS ON}
   TLspCompletionItemKind = (
    Text = 1,
    Method = 2,
    _Function = 3,
    _Constructor = 4,
    Field = 5,
    Variable = 6,
    _Class = 7,
    _Interface = 8,
    Module = 9,
    _Property = 10,
    _Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    _File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    _Operator = 24,
    TypeParameter = 25);

  TSymbolKind = (
	  _File = 1,
	  Module = 2,
 	  Namespace = 3,
	  Package = 4,
	  _Class = 5,
 	  Method = 6,
  	_Property = 7,
	  Field = 8,
	  _Constructor = 9,
	  _Enum = 10,
	  _Interface = 11,
	  _Function = 12,
	  _Variable = 13,
	  _Constant = 14,
	  _String = 15,
    Number = 16,
	  _Boolean = 17,
	  _Array = 18,
	  _Object = 19,
	  _Key = 20,
	  _Null = 21,
	  _EnumMember = 22,
	  _Struct = 23,
	  _Event = 24,
	  _Operator = 25,
	  _TypeParameter = 26);
{$SCOPEDENUMS OFF}

  TCompletionItem = record
    (*
     * The label of this completion item. By default
     * also the text that is inserted when selecting
     * this completion.
     *)
    _label: string;
    kind: TLspCompletionItemKind;
    documentation: string {| MarkupContent};
  end;

  TCompletionItems = TArray<TCompletionItem>;

  TDocPosition = record
    FileName: string;
    Line: integer;
    Char: integer;
    constructor Create(const FileName: string; Line, Char: integer);
  end;

function FormatJSON(const json: string): string;
function FilePathToURL(const FilePath: string): string;
function FilePathFromUrl(const Url: string): string;
function LSPInitializeParams(const ClientName, ClientVersion: string;
  ClientCapabilities: TJsonObject;
  InitializationOptions: TJsonObject = nil): TJsonObject;
function LspPosition(Line, Char: Integer): TJsonObject; overload;
function LspDocPosition(const FileName: string; Line, Char: integer): TJsonObject; overload;
function LspLocationToDocPosition(Location: TJsonValue; out DocPosition: TDocPosition): Boolean;
function LspTextDocumentItem(const FileName, LanguageId, Text: string; Version: integer): TJsonObject;
function LspTextDocumentIdentifier(const FileName: string): TJsonObject;
function LspVersionedTextDocumentIdentifier(const FileName: string; Version: Int64): TJsonObject;
function LspCompletionItems(LspResult: TJsonValue): TCompletionItems;

type
  TJsonArrayHelper = class helper for TJsonArray
    procedure Clear;
  end;

implementation

{ TDocPosition }

constructor TDocPosition.Create(const FileName: string; Line, Char: integer);
begin
  Self.FileName := FileName;
  Self.Line := Line;
  Self.Char := Char;
end;

function FormatJSON(const json: string): string;
var
  tmpJson: TJsonValue;
begin
  tmpJson := TJSONObject.ParseJSONValue(json);
  Result := tmpJson.Format;
  FreeAndNil(tmpJson);
end;


function FilePathToURL(const FilePath: string): string;
var
  BufferLen: DWORD;
begin
  if FindDelimiter(':\/', FilePath) > 0 then
  begin
    BufferLen := INTERNET_MAX_URL_LENGTH;
    SetLength(Result, BufferLen);
    OleCheck(UrlCreateFromPath(PChar(FilePath), PChar(Result), @BufferLen, 0));
    SetLength(Result, BufferLen);
  end
  else
    // Not sure how to handle unsaved files
    // and used the following workaround
    Result := 'file:///C:/Untitled/'+ FilePath;
end;

function FilePathFromUrl(const Url: string): string;
var
  BufferLen: DWORD;
begin
  BufferLen := MAX_PATH;
  SetLength(Result, BufferLen);
  OleCheck(PathCreateFromUrl(PChar(Url), PChar(Result), @BufferLen, 0));
  SetLength(Result, BufferLen);

  if Result.StartsWith('C:\Untitled\', True) then
    Result := Copy(Result, 13);
end;

function LSPInitializeParams(const ClientName, ClientVersion: string;
  ClientCapabilities: TJsonObject;
  InitializationOptions: TJsonObject = nil): TJsonObject;
var
  ClientInfo: TJsonObject;
begin
  ClientInfo := TJsonObject.Create;
  ClientInfo.AddPair('name', TJSONString.Create(ClientName));
  ClientInfo.AddPair('version', TJSONString.Create(ClientVersion));
  Result := TJsonObject.Create;
  Result.AddPair('clientInfo', ClientInfo);
  Result.AddPair('rootUri', TJSONNull.Create);
  Result.AddPair('capabilities', ClientCapabilities);
  if Assigned(InitializationOptions) then
    Result.AddPair('initializationOptions', InitializationOptions);
end;

function LspPosition(Line, Char: Integer): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.AddPair('line', TJSONNumber.Create(Line));
  Result.AddPair('character', TJSONNumber.Create(Char));
end;

function LspDocPosition(const FileName: string; Line, Char: integer): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.AddPair('textDocument', LspTextDocumentIdentifier(FileName));
  Result.AddPair('position', LSPPosition(Line, Char));
end;

function LspLocationToDocPosition(Location: TJsonValue; out DocPosition: TDocPosition): Boolean;
begin
  if not (Location is TJsonObject) then Exit(False);

  Result := Location.TryGetValue<string>('uri',  DocPosition.FileName) and
      Location.TryGetValue<integer>('range.start.line',  DocPosition.Line) and
      Location.TryGetValue<integer>('range.start.character', DocPosition.Char);

  if Result then
  begin
    DocPosition.FileName := FilePathFromUrl(DocPosition.FileName);
    Inc(DocPosition.Line);
    Inc(DocPosition.Char);
  end;
end;

function LspTextDocumentItem(const FileName, LanguageId, Text: string; Version: integer): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.AddPair('uri', TJSONString.Create(FilePathToURL(FileName)));
  Result.AddPair('languageId', TJSONString.Create(LanguageId));
  Result.AddPair('version', TJSONNumber.Create(Version));
  Result.AddPair('text', TJSONString.Create(Text));
end;

function LspTextDocumentIdentifier(const FileName: string): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.AddPair('uri', TJSONString.Create(FilePathToURL(FileName)));
end;

function LspVersionedTextDocumentIdentifier(const FileName: string; Version: Int64): TJsonObject;
begin
  Result := LspTextDocumentIdentifier(FileName);
  Result.AddPair('version', TJSONNumber.Create(Version));
end;


function LspCompletionItems(LspResult: TJsonValue): TCompletionItems;
begin
  if LspResult = nil then Exit;

  var Items := LspResult.FindValue('items');
  if Assigned(Items) and (Items is TJSONArray) then
  begin
    SetLength(Result, TJsonArray(Items).Count);
    for var I:= 0 to Length(Result) - 1  do
    begin
      var Item := TJsonArray(Items).Items[I];
      Item.TryGetValue<string>('label', Result[I]._label);
      var TempI: integer;
      if Item.TryGetValue<integer>('kind', TempI) then
        Result[I].kind := TLspCompletionItemKind(TempI);
    end;
  end;
end;

{ TJsonArrayHelper }

procedure TJsonArrayHelper.Clear;
begin
  while Self.Count > 0 do
    Self.Remove(Self.Count - 1).Free;
end;

end.
{-----------------------------------------------------------------------------
 Unit Name: dlgUnitTestWizard
 Author:    Kiriakos Vlahos
 Date:      09-Feb-2006
 Purpose:   Unit Test Wizard
 History:
-----------------------------------------------------------------------------}
unit dlgUnitTestWizard;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.UITypes,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.ImageList,
  System.JSON,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ImgList,
  Vcl.VirtualImageList,
  TB2Item,
  SpTBXItem,
  VirtualTrees.Types,
  VirtualTrees.BaseAncestorVCL,
  VirtualTrees.AncestorVCL,
  VirtualTrees.BaseTree,
  VirtualTrees,
  dlgPyIDEBase;

type

  TUnitTestWizard = class(TPyIDEDlgBase)
    Panel1: TPanel;
    ExplorerTree: TVirtualStringTree;
    Bevel1: TBevel;
    PopupUnitTestWizard: TSpTBXPopupMenu;
    mnSelectAll: TSpTBXItem;
    mnDeselectAll: TSpTBXItem;
    Label1: TLabel;
    lbHeader: TLabel;
    lbFileName: TLabel;
    OKButton: TButton;
    BitBtn2: TButton;
    HelpButton: TButton;
    vilCodeImages: TVirtualImageList;
    vilImages: TVirtualImageList;
    procedure HelpButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ExplorerTreeInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure ExplorerTreeInitChildren(Sender: TBaseVirtualTree;
      Node: PVirtualNode; var ChildCount: Cardinal);
    procedure ExplorerTreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure ExplorerTreeGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: TImageIndex);
    procedure ExplorerTreeGetHint(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var LineBreakStyle: TVTTooltipLineBreakStyle;
      var HintText: string);
    procedure mnSelectAllClick(Sender: TObject);
    procedure mnDeselectAllClick(Sender: TObject);
  private
    { Private declarations }
    Symbols : TJsonArray;
    ModuleName: string;
    ModuleFileName: string;
    function SymbolHint(Symbol: TJsonObject): string;
    function SymbolSignature(Symbol: TJsonObject): string;
  public
    { Public declarations }
    class function GenerateTests(const ModuleFName: string) : string;
  end;

implementation

uses
  System.Generics.Collections,
  JvJVCLUtils,
  SpTBXSkins,
  JvGnugettext,
  dmResources,
  uCommonFunctions,
  SynEditTypes,
  LspUtils,
  JediLspClient;

{$R *.dfm}

//function TMethodUTWNode.GetHint: string;
//Var
//  Doc : string;
//begin
//  Result := Format('Method %s defined at line %d'#13#10'Arguments: %s',
//              [fCodeElement.Name, fCodeElement.CodePos.LineNo, ParsedFunction.ArgumentsString]);
//  Doc := ParsedFunction.DocString;
//  if Doc <> '' then
//    Result := Result + #13#10#13#10 + Doc;
//end;

procedure Prune(Symbols: TJsonArray);

  function PruneChild(Value: TJsonValue; IsClass: Boolean): Boolean;
  var
    Kind: integer;
  begin
    Result := False;
    var Children := Value.FindValue('children');
    if Assigned(Children) and (Children is TJsonArray) then
    begin
      var Arr := TJsonArray(Children);
      for var I := Arr.Count -1 downto 0 do
      begin
         var Val := Arr.Items[I];
         if not IsClass or not Val.TryGetValue<integer>('kind', Kind) or not
           (Kind = Ord(TSymbolKind.Method))
         then
           Arr.Remove(I).Free;
      end;
      Result := IsClass and (Arr.Count = 0);
    end;
  end;

var
  Kind: integer;
begin
  for var I := Symbols.Count -1 downto 0 do
  begin
     var Value := Symbols.Items[I];
     if not Value.TryGetValue<integer>('kind', Kind) or not
       (Kind in [Ord(TSymbolKind._Class), Ord(TSymbolKind._Function)])
     then
       Symbols.Remove(I).Free
     else
     begin
       if PruneChild(Value, Kind = Ord(TSymbolKind._Class)) then
         Symbols.Remove(I).Free;
     end;
  end;
end;

class function TUnitTestWizard.GenerateTests(const ModuleFName: string) : string;

Const
  Header = '#This file was originally generated by PyScripter''s unit test wizard' +
    SLineBreak + SLineBreak + 'import unittest'+ sLineBreak + 'import %s'
    + sLineBreak + sLineBreak;

   ClassHeader =
      'class Test%s(unittest.TestCase):'+ sLineBreak + SLineBreak +
      '    def setUp(self): ' + SLineBreak +
      '        pass' + SLineBreak + SLineBreak +
      '    def tearDown(self): ' + SLineBreak +
      '        pass' + SLineBreak + SLineBreak;

    MethodHeader =
        '    def test%s(self):' + SLineBreak +
        '        pass' + SLineBreak + SLineBreak;

     Footer =
      'if __name__ == ''__main__'':' + SLineBreak +
      '    unittest.main()' + SLineBreak;

Var
  LSymbols : TJsonArray;
  Node, MethodNode: PVirtualNode;
  Symbol, MSymbol: TJsonObject;
  SName, MName: string;
  FunctionTests : string;
  WaitCursorInterface: IInterface;
begin
  Result := '';
  FunctionTests := '';

  LSymbols := TJedi.DocumentSymbols(ModuleFName);
  if not Assigned(LSymbols) then Exit;
  Prune(LSymbols);
  if LSymbols.Count = 0 then
  begin
    LSymbols.Free;
    Exit;
  end;

  with TUnitTestWizard.Create(Application) do
  begin
    lbFileName.Caption := ModuleFName;
    Symbols := LSymbols;
    ModuleFileName := ModuleFName;
    ModuleName := FileNameToModuleName(ModuleFName);
    // Turn off Animation to speed things up
    ExplorerTree.TreeOptions.AnimationOptions :=
      ExplorerTree.TreeOptions.AnimationOptions - [toAnimatedToggle];
    ExplorerTree.RootNodeCount := 1;
    ExplorerTree.ReinitNode(ExplorerTree.RootNode, True);
    ExplorerTree.TreeOptions.AnimationOptions :=
      ExplorerTree.TreeOptions.AnimationOptions + [toAnimatedToggle];
    if ShowModal = idOK then begin
      Application.ProcessMessages;
      WaitCursorInterface := WaitCursor;
      // Generate code
      Result := Format(Header, [ModuleName]);
      Node := (ExplorerTree.RootNode)^.FirstChild^.FirstChild;
      while Assigned(Node) do begin
        Symbol := Node.GetData<TJsonObject>;
        Symbol.TryGetValue<string>('name', SName);
        if (Node.CheckState in [csCheckedNormal, csCheckedPressed,
          csMixedNormal, csMixedPressed]) then
        begin
          if Node.ChildCount > 0 then begin
            // Class Symbol
            Result := Result + Format(ClassHeader, [SName]);
            MethodNode := Node.FirstChild;
            while Assigned(MethodNode) do begin
              if (MethodNode.CheckState in [csCheckedNormal, csCheckedPressed]) then begin
                MSymbol := MethodNode.GetData<TJsonObject>;
                MSymbol.TryGetValue<string>('name', MName);
                Result := Result + Format(MethodHeader, [MName]);
              end;
              MethodNode := MethodNode.NextSibling;
            end;
          end
          else
          begin
            if FunctionTests = '' then
              FunctionTests := Format(ClassHeader, ['GlobalFunctions']);
            FunctionTests := FunctionTests + Format(MethodHeader, [SName]);
          end;
        end;
        Node := Node.NextSibling;
      end;
      if FunctionTests <> '' then
        Result := Result + FunctionTests;
      Result := Result + Footer;
    end;
    Release;
    Symbols.Free;
  end;
end;

procedure TUnitTestWizard.ExplorerTreeGetHint(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex;
  var LineBreakStyle: TVTTooltipLineBreakStyle; var HintText: string);
begin
  case ExplorerTree.GetNodeLevel(Node) of
    0:  HintText := Format(_('Python Module "%s"'), [ModuleName]);
    1, 2:
      begin
        var Symbol := Node.GetData<TJsonObject>;
        HintText := SymbolHint(Symbol);
      end
    else
      raise Exception.Create('TUnitTestWizard.ExplorerTreeGetHint');
  end;
end;

procedure TUnitTestWizard.ExplorerTreeGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex);
begin
  if Kind in [ikNormal, ikSelected] then
    case ExplorerTree.GetNodeLevel(Node) of
      0: ImageIndex := Integer(TCodeImages.Python);
      1: if Node.ChildCount = 0 then
           ImageIndex := Integer(TCodeImages.Func)
         else
           ImageIndex := Integer(TCodeImages.Klass);
      2: ImageIndex := Integer(TCodeImages.Method);
      else
        raise Exception.Create('TUnitTestWizard.ExplorerTreeGetImageIndex');
    end;
end;

procedure TUnitTestWizard.ExplorerTreeGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
begin
  if TextType = ttNormal then
    case ExplorerTree.GetNodeLevel(Node) of
      0:  CellText := ModuleName;
      1:  begin
            var Symbol := Node.GetData<TJsonObject>;
            if Node.ChildCount = 0 then
              CellText := SymbolSignature(Symbol)
            else
              Symbol.TryGetValue<string>('name', CellText);
          end;
      2:  begin
            var Symbol := Node.GetData<TJsonObject>;
            CellText := SymbolSignature(Symbol)
          end;
      else
        raise Exception.Create('TUnitTestWizard.ExplorerTreeGetText');
    end;
end;

procedure TUnitTestWizard.ExplorerTreeInitChildren(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var ChildCount: Cardinal);
begin
  case ExplorerTree.GetNodeLevel(Node) of
    0: ChildCount := Symbols.Count;
    1:
       begin
         ChildCount := 0;
         var Value := Node.GetData<TJsonObject>;
         var Children := Value.FindValue('children');
         if Children is TJsonArray then
           ChildCount := TJsonArray(Children).Count;
       end;
    2: ChildCount := 0;
    else
      raise Exception.Create('TUnitTestWizard.ExplorerTreeInitChildren');
  end;
end;

procedure TUnitTestWizard.ExplorerTreeInitNode(Sender: TBaseVirtualTree;
  ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
var
  Name: string;
  Kind: integer;
begin
  Node.CheckState := csCheckedNormal;
  Node.CheckType := ctCheckBox;
  case ExplorerTree.GetNodeLevel(Node) of
    0:
       begin
         InitialStates := [ivsHasChildren, ivsExpanded];
         Node.SetData<TJsonValue>(Symbols);
         Node.CheckType := ctTriStateCheckBox;
       end;
    1:
       begin
         var Child := Symbols.Items[Node.Index];
         Node.SetData<TJsonValue>(Child);
         if Child.TryGetValue<integer>('kind', Kind) and
           (Kind = Ord(TSymbolKind._Class)) then
         begin
           InitialStates := [ivsHasChildren, ivsExpanded];
           Node.CheckType := ctTriStateCheckBox;
         end;
       end;
    2:
      begin
        var Klass := ParentNode.GetData<TJsonObject>;
        var Children := Klass.FindValue('children');
        var Method := TJsonArray(Children).Items[Node.Index];
        Assert(Assigned(Children) and (Children is TJsonArray));
        Node.SetData<TJsonValue>(Method);
        if Method.TryGetValue<string>('name', Name) and (Name = '__init__') then
          Node.CheckState := csUncheckedNormal
      end;
    else
      raise Exception.Create('TUnitTestWizard.ExplorerTreeInitNode');
  end;
end;

procedure TUnitTestWizard.FormCreate(Sender: TObject);
begin
  inherited;
  ExplorerTree.NodeDataSize := SizeOf(Pointer);
end;

procedure TUnitTestWizard.HelpButtonClick(Sender: TObject);
begin
  if HelpContext <> 0 then
    Application.HelpContext(HelpContext);
end;

procedure TUnitTestWizard.mnDeselectAllClick(Sender: TObject);
Var
  Node : PVirtualNode;
begin
   Node := ExplorerTree.RootNode^.FirstChild;
   while Assigned(Node) do begin
     ExplorerTree.CheckState[Node] := csUncheckedNormal;
     Node := Node.NextSibling;
   end;
end;

procedure TUnitTestWizard.mnSelectAllClick(Sender: TObject);
Var
  Node : PVirtualNode;
begin
   Node := ExplorerTree.RootNode^.FirstChild;
   while Assigned(Node) do begin
     ExplorerTree.CheckState[Node] := csCheckedNormal;
     Node := Node.NextSibling;
   end;
end;

function TUnitTestWizard.SymbolHint(Symbol: TJsonObject): string;
var
  BC: TBufferCoord;
begin
  if Symbol.TryGetValue<integer>('selectionRange.start.line', BC.Line) and
    Symbol.TryGetValue<integer>('selectionRange.start.character', BC.Char)
  then
  begin
    Inc(BC.Line);
    Inc(BC.Char);
    Result := TJedi.SimpleHintAtCoordinates(ModuleFileName, BC);
  end;
end;

function TUnitTestWizard.SymbolSignature(Symbol: TJsonObject): string;
Var
  Line: integer;
begin
  Result := '';
  if Symbol.TryGetValue<integer>('selectionRange.start.line', Line) then
  begin
    Result := Trim(GetNthSourceLine(ModuleFileName, Line + 1));
    var Index := Result.LastIndexOf(':');
    if Index >= 0 then
      Delete(Result, Index + 1, MaxInt);
    if Result.StartsWith('def') then
      Delete(Result, 1, 3);
    Result := Result.TrimLeft;
  end;
end;

end.

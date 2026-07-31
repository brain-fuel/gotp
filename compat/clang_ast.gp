package compat

import (
	"encoding/json"
	"fmt"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

type NativeABISymbolKind enum {
	NativeFunction()
	NativeTypedef()
	NativeRecord()
	NativeField()
	NativeEnum()
	NativeEnumConstant()
	NativeVariable()
}

type NativeABISymbol struct {
	Profile string `json:"profile"`
	Surface string `json:"surface"`
	Header string `json:"header"`
	Kind string `json:"kind"`
	Container string `json:"container,omitempty"`
	Name string `json:"name"`
	Signature string `json:"signature,omitempty"`
	Value string `json:"value,omitempty"`
}

type ClangASTUnit struct {
	Surface string
	MainPath string
	OwnedPaths []string
	JSON []byte
}

type clangType struct {
	QualType string `json:"qualType"`
	DesugaredQualType string `json:"desugaredQualType"`
}

type clangReference struct {
	ID string `json:"id"`
	Kind string `json:"kind"`
	Name string `json:"name"`
}

type clangLocation struct {
	Offset int `json:"offset"`
	Line int `json:"line"`
	File string `json:"file"`
	IncludedFrom *clangLocation `json:"includedFrom"`
	SpellingLoc *clangLocation `json:"spellingLoc"`
	ExpansionLoc *clangLocation `json:"expansionLoc"`
}

type clangNode struct {
	ID string `json:"id"`
	Kind string `json:"kind"`
	Name string `json:"name"`
	TagUsed string `json:"tagUsed"`
	Value json.RawMessage `json:"value"`
	IsImplicit bool `json:"isImplicit"`
	CompleteDefinition bool `json:"completeDefinition"`
	Type clangType `json:"type"`
	OwnedTagDecl *clangReference `json:"ownedTagDecl"`
	Loc clangLocation `json:"loc"`
	Inner []clangNode `json:"inner"`
}

func NormalizeClangAST(profile string, unit ClangASTUnit) result.Result[[]NativeABISymbol, NativeABIFailure] {
	var root clangNode
	match result.Of(true, json.Unmarshal(unit.JSON, &root)) {
	case result.Err(cause): return result.Err[[]NativeABISymbol, NativeABIFailure](NativeABIASTRejected(unit.MainPath, cause.Error()))
	case result.Ok(_):
	}
	tagNames := map[string]string{}
	collectClangTagNames(root, tagNames)
	symbols := []NativeABISymbol{}
	ownership := clangOwnershipState{}
	walkClangDeclarations(profile, unit, root, "", "root", tagNames, &ownership, &symbols)
	return result.Ok[[]NativeABISymbol, NativeABIFailure](symbols)
}

func collectClangTagNames(node clangNode, names map[string]string) {
	if node.Kind == "TypedefDecl" && node.Name != "" {
		match ownedClangTag(node) {
		case option.None:
		case option.Some(reference): names[reference.ID] = node.Name
		}
	}
	for _, child := range node.Inner { collectClangTagNames(child, names) }
}

func ownedClangTag(node clangNode) option.Option[clangReference] {
	if node.OwnedTagDecl != nil { return option.Some[clangReference](*node.OwnedTagDecl) }
	for _, child := range node.Inner {
		match ownedClangTag(child) {
		case option.None:
		case option.Some(reference): return option.Some[clangReference](reference)
		}
	}
	return option.None[clangReference]
}

type clangOwnershipState struct { File string; SpellingFile string }

func walkClangDeclarations(profile string, unit ClangASTUnit, node clangNode, container string, path string, tagNames map[string]string, ownership *clangOwnershipState, symbols *[]NativeABISymbol) {
	header := ownedClangHeader(unit, node.Loc, ownership)
	owned := header != ""
	nextContainer := container
	if owned && node.Kind == "RecordDecl" && node.CompleteDefinition {
		name := node.Name
		if name == "" { name = tagNames[node.ID] }
		if name == "" { name = "@anonymous." + path }
		nextContainer = name
		*symbols = append(*symbols, NativeABISymbol{Profile: profile, Surface: unit.Surface, Header: header, Kind: "record", Name: name, Signature: node.TagUsed})
	}
	if owned && node.Kind == "EnumDecl" {
		name := node.Name
		if name == "" { name = tagNames[node.ID] }
		if name == "" { name = "@anonymous." + path }
		nextContainer = name
		*symbols = append(*symbols, NativeABISymbol{Profile: profile, Surface: unit.Surface, Header: header, Kind: "enum", Name: name, Signature: node.Type.QualType})
	}
	if owned {
		match clangDeclarationSymbol(profile, unit.Surface, header, container, path, node) {
		case option.None:
		case option.Some(symbol): *symbols = append(*symbols, symbol)
		}
	}
	for index, child := range node.Inner { walkClangDeclarations(profile, unit, child, nextContainer, fmt.Sprintf("%s.%d", path, index), tagNames, ownership, symbols) }
}

func clangDeclarationSymbol(profile string, surface string, header string, container string, path string, node clangNode) option.Option[NativeABISymbol] {
	symbol := NativeABISymbol{Profile: profile, Surface: surface, Header: header, Container: container, Name: node.Name, Signature: node.Type.QualType, Value: clangNodeValue(node)}
	switch node.Kind {
	case "FunctionDecl": symbol.Kind = "function"
	case "TypedefDecl": symbol.Kind = "typedef"
	case "FieldDecl":
		symbol.Kind = "field"
		if symbol.Name == "" { symbol.Name = "@anonymous." + path }
	case "EnumConstantDecl": symbol.Kind = "enum-constant"
	case "VarDecl": symbol.Kind = "variable"
	default: return option.None[NativeABISymbol]
	}
	if symbol.Name == "" { return option.None[NativeABISymbol] }
	return option.Some[NativeABISymbol](symbol)
}

func clangNodeValue(node clangNode) string {
	if len(node.Value) != 0 {
		var text string
		match result.Of(true, json.Unmarshal(node.Value, &text)) {
		case result.Err(_): return string(node.Value)
		case result.Ok(_): return text
		}
	}
	for _, child := range node.Inner {
		value := clangNodeValue(child)
		if value != "" { return value }
	}
	return ""
}

func ownedClangHeader(unit ClangASTUnit, location clangLocation, ownership *clangOwnershipState) string {
	if location.SpellingLoc != nil {
		if location.SpellingLoc.File != "" { ownership.SpellingFile = location.SpellingLoc.File }
		matched := matchingOwnedPath(unit, ownership.SpellingFile)
		if matched != "" { return matched }
		if location.SpellingLoc.IncludedFrom != nil && pathMatches(location.SpellingLoc.IncludedFrom.File, unit.MainPath) && unit.Surface == "nif" { return "erts/emulator/beam/erl_nif_api_funcs.h" }
	}
	if location.File != "" { ownership.File = location.File }
	if ownership.File != "" {
		matched := matchingOwnedPath(unit, ownership.File)
		if matched != "" { return matched }
		return ""
	}
	if location.Offset > 0 && location.IncludedFrom == nil { return unit.MainPath }
	if location.IncludedFrom != nil && pathMatches(location.IncludedFrom.File, unit.MainPath) && (unit.Surface == "nif" || unit.Surface == "driver") { return "erts/emulator/beam/erl_drv_nif.h" }
	return ""
}

func matchingOwnedPath(unit ClangASTUnit, absolute string) string {
	for _, path := range unit.OwnedPaths {
		if absolute == path || strings.HasSuffix(absolute, "/"+path) { return path }
	}
	return ""
}

func pathMatches(absolute string, path string) bool { return absolute == path || strings.HasSuffix(absolute, "/"+path) }

func nativeABISymbolKind(kind string) option.Option[NativeABISymbolKind] {
	switch kind {
	case "function": return option.Some[NativeABISymbolKind](NativeFunction())
	case "typedef": return option.Some[NativeABISymbolKind](NativeTypedef())
	case "record": return option.Some[NativeABISymbolKind](NativeRecord())
	case "field": return option.Some[NativeABISymbolKind](NativeField())
	case "enum": return option.Some[NativeABISymbolKind](NativeEnum())
	case "enum-constant": return option.Some[NativeABISymbolKind](NativeEnumConstant())
	case "variable": return option.Some[NativeABISymbolKind](NativeVariable())
	default: return option.None[NativeABISymbolKind]
	}
}

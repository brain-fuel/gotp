package compat

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	DeclarationSchema = "gotp.otp-declarations/v1"
	PinnedDeclarationCount = 40563
	PinnedDeclarationSourceDigest = "5c475e83c610c09e12deb03b92611fc56367f3c458e4589668bb01c1bf16b2ca"
)

type DeclarationKind enum {
	ExportedFunction()
	ExportedType()
	RequiredCallback()
	OptionalCallback()
}

type OTPModuleSource struct {
	Application string
	Module string
	SourcePath string
	Content string
}

type OTPPublicDeclaration struct {
	Kind string `json:"kind"`
	Application string `json:"application"`
	Module string `json:"module"`
	Name string `json:"name"`
	Arity int `json:"arity"`
}

type OTPDeclarationInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	SourceDigest string `json:"source_digest"`
	Declarations []OTPPublicDeclaration `json:"declarations"`
}

type DeclarationFailure enum {
	DeclarationJSONRejected(Cause string)
	DeclarationProvenanceRejected(Detail string)
	DeclarationSyntaxRejected(Path string, Detail string)
	DeclarationOrderingRejected(Detail string)
	DeclarationIdentityRejected(Detail string)
	DeclarationCountRejected(Found int, Expected int)
}

func (failure DeclarationFailure) Error() string {
	match failure {
	case DeclarationJSONRejected(cause): return "gotp/compat: declaration JSON rejected: " + cause
	case DeclarationProvenanceRejected(detail): return "gotp/compat: declaration provenance rejected: " + detail
	case DeclarationSyntaxRejected(path, detail): return "gotp/compat: declaration syntax rejected in " + path + ": " + detail
	case DeclarationOrderingRejected(detail): return "gotp/compat: declaration ordering rejected: " + detail
	case DeclarationIdentityRejected(detail): return "gotp/compat: declaration identity rejected: " + detail
	case DeclarationCountRejected(found, expected): return fmt.Sprintf("gotp/compat: declaration count %d; want %d", found, expected)
	}
}

// assayxport:unit gotp.compat.otp-public-declarations
func BuildOTPDeclarationInventory(sources []OTPModuleSource) result.Result[OTPDeclarationInventory, DeclarationFailure] {
	ordered := append([]OTPModuleSource{}, sources...)
	sort.Slice(ordered, func(left, right int) bool { return ordered[left].SourcePath < ordered[right].SourcePath })
	declarations := map[string]OTPPublicDeclaration{}
	var canonical strings.Builder
	priorPath := ""
	for index, source := range ordered {
		if source.Application == "" || source.Module == "" || source.SourcePath == "" || (index > 0 && source.SourcePath <= priorPath) {
			return result.Err[OTPDeclarationInventory, DeclarationFailure](DeclarationIdentityRejected("empty or duplicate module source"))
		}
		canonical.WriteString(source.SourcePath)
		canonical.WriteByte(0)
		canonical.WriteString(source.Content)
		canonical.WriteByte(0)
		priorPath = source.SourcePath
		match declarationsFromSource(source) {
		case result.Err(failure): return result.Err[OTPDeclarationInventory, DeclarationFailure](failure)
		case result.Ok(found):
			for _, declaration := range found {
				id := InventoryDeclarationID(declaration)
				if prior, present := declarations[id]; present && prior != declaration {
					return result.Err[OTPDeclarationInventory, DeclarationFailure](DeclarationIdentityRejected("normalized collision " + id))
				}
				declarations[id] = declaration
			}
		}
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	inventory := OTPDeclarationInventory{Schema: DeclarationSchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, SourceDigest: hex.EncodeToString(digest[:])}
	for _, declaration := range declarations { inventory.Declarations = append(inventory.Declarations, declaration) }
	sort.Slice(inventory.Declarations, func(left, right int) bool {
		return InventoryDeclarationID(inventory.Declarations[left]) < InventoryDeclarationID(inventory.Declarations[right])
	})
	match ValidateOTPDeclarationInventory(inventory) {
	case result.Err(failure): return result.Err[OTPDeclarationInventory, DeclarationFailure](failure)
	case result.Ok(_): return result.Ok[OTPDeclarationInventory, DeclarationFailure](inventory)
	}
}

func ParseOTPDeclarationInventory(data []byte) result.Result[OTPDeclarationInventory, DeclarationFailure] {
	var inventory OTPDeclarationInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPDeclarationInventory, DeclarationFailure](DeclarationJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPDeclarationInventory(inventory) {
	case result.Err(failure): return result.Err[OTPDeclarationInventory, DeclarationFailure](failure)
	case result.Ok(_):
		inventory.Declarations = append([]OTPPublicDeclaration{}, inventory.Declarations...)
		return result.Ok[OTPDeclarationInventory, DeclarationFailure](inventory)
	}
}

func ValidateOTPDeclarationInventory(inventory OTPDeclarationInventory) result.Result[bool, DeclarationFailure] {
	if inventory.Schema != DeclarationSchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit || inventory.SourceDigest != PinnedDeclarationSourceDigest {
		return result.Err[bool, DeclarationFailure](DeclarationProvenanceRejected("schema, upstream pin, or source digest differs: " + inventory.SourceDigest))
	}
	if len(inventory.Declarations) != PinnedDeclarationCount {
		return result.Err[bool, DeclarationFailure](DeclarationCountRejected(len(inventory.Declarations), PinnedDeclarationCount))
	}
	prior := ""
	for index, declaration := range inventory.Declarations {
		if declaration.Application == "" || declaration.Module == "" || declaration.Name == "" || declaration.Arity < 0 {
			return result.Err[bool, DeclarationFailure](DeclarationIdentityRejected("empty or negative declaration identity"))
		}
		match declarationKind(declaration.Kind) {
		case option.None: return result.Err[bool, DeclarationFailure](DeclarationIdentityRejected("unknown declaration kind " + declaration.Kind))
		case option.Some(_):
		}
		id := InventoryDeclarationID(declaration)
		if index > 0 && id <= prior { return result.Err[bool, DeclarationFailure](DeclarationOrderingRejected("declarations are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, DeclarationFailure](true)
}

func InventoryDeclarationID(declaration OTPPublicDeclaration) string {
	name := hex.EncodeToString([]byte(declaration.Name))
	return "otp.declaration." + declaration.Kind + "." + strings.ToLower(declaration.Application) + "." + strings.ToLower(declaration.Module) + "." + name + "." + strconv.Itoa(declaration.Arity)
}

func MissingDeclarationCoverage(inventory OTPDeclarationInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, declaration := range inventory.Declarations {
		id := InventoryDeclarationID(declaration)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func declarationsFromSource(source OTPModuleSource) result.Result[[]OTPPublicDeclaration, DeclarationFailure] {
	clean := stripErlangComments(source.Content)
	declarations := []OTPPublicDeclaration{}
	for _, attribute := range []struct{ Marker string; Kind string }{
		{Marker: "-export(", Kind: "function"},
		{Marker: "-export_type(", Kind: "type"},
		{Marker: "-optional_callbacks(", Kind: "optional-callback"},
	} {
		match wrappedAttributeBodies(clean, attribute.Marker, source.SourcePath) {
		case result.Err(failure): return result.Err[[]OTPPublicDeclaration, DeclarationFailure](failure)
		case result.Ok(bodies):
			for _, body := range bodies {
				match parseNameArityList(body, source, attribute.Kind) {
				case result.Err(failure): return result.Err[[]OTPPublicDeclaration, DeclarationFailure](failure)
				case result.Ok(found): declarations = append(declarations, found...)
				}
			}
		}
	}
	match callbackDeclarations(clean, source) {
	case result.Err(failure): return result.Err[[]OTPPublicDeclaration, DeclarationFailure](failure)
	case result.Ok(found): declarations = append(declarations, found...)
	}
	return result.Ok[[]OTPPublicDeclaration, DeclarationFailure](declarations)
}

func wrappedAttributeBodies(source string, marker string, path string) result.Result[[]string, DeclarationFailure] {
	bodies := []string{}
	offset := 0
	for {
		relative := strings.Index(source[offset:], marker)
		if relative < 0 { return result.Ok[[]string, DeclarationFailure](bodies) }
		markerStart := offset + relative
		if !attributeLineStart(source, markerStart) { offset = markerStart + len(marker); continue }
		start := markerStart + len(marker)
		match matchingDelimiter(source, start-1, '(', ')') {
		case option.None: return result.Err[[]string, DeclarationFailure](DeclarationSyntaxRejected(path, "unterminated " + marker))
		case option.Some(end):
			bodies = append(bodies, source[start:end])
			offset = end + 1
		}
	}
}

func parseNameArityList(body string, source OTPModuleSource, kind string) result.Result[[]OTPPublicDeclaration, DeclarationFailure] {
	trimmed := strings.TrimSpace(body)
	if !strings.HasPrefix(trimmed, "[") || !strings.HasSuffix(trimmed, "]") {
		return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, kind + " declaration is not a literal list"))
	}
	entries := splitTopLevel(strings.TrimSpace(trimmed[1:len(trimmed)-1]), ',')
	declarations := []OTPPublicDeclaration{}
	for _, entry := range entries {
		entry = strings.TrimSpace(entry)
		if entry == "" { continue }
		if strings.HasPrefix(entry, "{") && strings.HasSuffix(entry, "}") {
			parts := splitTopLevel(entry[1:len(entry)-1], ',')
			if len(parts) == 2 { entry = strings.TrimSpace(parts[0]) + "/" + strings.TrimSpace(parts[1]) }
		}
		slash := lastTopLevel(entry, '/')
		if slash < 1 { return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "invalid " + kind + " entry " + entry)) }
		name := unquoteAtom(strings.TrimSpace(entry[:slash]))
		arityText := strings.TrimSpace(entry[slash+1:])
		arity, cause := strconv.Atoi(arityText)
		match result.Of(arity, cause) {
		case result.Err(_): return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "invalid arity " + arityText))
		case result.Ok(arity):
			if name == "" || arity < 0 { return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "invalid name/arity " + entry)) }
			declarations = append(declarations, OTPPublicDeclaration{Kind: kind, Application: source.Application, Module: source.Module, Name: name, Arity: arity})
		}
	}
	return result.Ok[[]OTPPublicDeclaration, DeclarationFailure](declarations)
}

func callbackDeclarations(content string, source OTPModuleSource) result.Result[[]OTPPublicDeclaration, DeclarationFailure] {
	const marker = "-callback"
	declarations := []OTPPublicDeclaration{}
	offset := 0
	for {
		relative := strings.Index(content[offset:], marker)
		if relative < 0 { return result.Ok[[]OTPPublicDeclaration, DeclarationFailure](declarations) }
		markerStart := offset + relative
		if !attributeLineStart(content, markerStart) { offset = markerStart + len(marker); continue }
		start := markerStart + len(marker)
		for start < len(content) && unicode.IsSpace(rune(content[start])) { start++ }
		open := topLevelIndex(content[start:], '(')
		if open < 1 { return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "callback has no argument list")) }
		open += start
		match matchingDelimiter(content, open, '(', ')') {
		case option.None: return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "unterminated callback arguments"))
		case option.Some(end):
			name := unquoteAtom(strings.TrimSpace(content[start:open]))
			arguments := strings.TrimSpace(content[open+1:end])
			arity := 0
			if arguments != "" { arity = len(splitTopLevel(arguments, ',')) }
			if name == "" { return result.Err[[]OTPPublicDeclaration, DeclarationFailure](DeclarationSyntaxRejected(source.SourcePath, "empty callback name")) }
			declarations = append(declarations, OTPPublicDeclaration{Kind: "callback", Application: source.Application, Module: source.Module, Name: name, Arity: arity})
			offset = end + 1
		}
	}
}

func attributeLineStart(source string, index int) bool {
	for index > 0 {
		index--
		if source[index] == '\n' { return true }
		if !unicode.IsSpace(rune(source[index])) { return false }
	}
	return true
}

func declarationKind(kind string) option.Option[DeclarationKind] {
	switch kind {
	case "function": return option.Some[DeclarationKind](ExportedFunction())
	case "type": return option.Some[DeclarationKind](ExportedType())
	case "callback": return option.Some[DeclarationKind](RequiredCallback())
	case "optional-callback": return option.Some[DeclarationKind](OptionalCallback())
	default: return option.None[DeclarationKind]
	}
}

func stripErlangComments(source string) string {
	var output strings.Builder
	quoted := byte(0)
	tripleQuoted := false
	escaped := false
	comment := false
	for index := 0; index < len(source); index++ {
		character := source[index]
		if tripleQuoted {
			if strings.HasPrefix(source[index:], "\"\"\"") { output.WriteString("   "); index += 2; tripleQuoted = false; continue }
			if character == '\n' { output.WriteByte(character) } else { output.WriteByte(' ') }
			continue
		}
		if comment {
			if character == '\n' { comment = false; output.WriteByte(character) }
			continue
		}
		if quoted != 0 {
			if quoted == '"' {
				if character == '\n' { output.WriteByte(character) } else { output.WriteByte(' ') }
			} else { output.WriteByte(character) }
			if escaped { escaped = false; continue }
			if character == '\\' { escaped = true; continue }
			if character == quoted { quoted = 0 }
			continue
		}
		if character == '%' { comment = true; continue }
		if strings.HasPrefix(source[index:], "\"\"\"") { output.WriteString("   "); index += 2; tripleQuoted = true; continue }
		if character == '\'' || character == '"' { quoted = character }
		if character == '"' { output.WriteByte(' ') } else { output.WriteByte(character) }
	}
	return output.String()
}

func matchingDelimiter(source string, openIndex int, open byte, close byte) option.Option[int] {
	depth := 0
	quoted := byte(0)
	escaped := false
	for index := openIndex; index < len(source); index++ {
		character := source[index]
		if quoted != 0 {
			if escaped { escaped = false; continue }
			if character == '\\' { escaped = true; continue }
			if character == quoted { quoted = 0 }
			continue
		}
		if character == '\'' || character == '"' { quoted = character; continue }
		if character == open { depth++ }
		if character == close {
			depth--
			if depth == 0 { return option.Some[int](index) }
		}
	}
	return option.None[int]
}

func splitTopLevel(source string, delimiter byte) []string {
	parts := []string{}
	start := 0
	depth := 0
	quoted := byte(0)
	escaped := false
	for index := 0; index < len(source); index++ {
		character := source[index]
		if quoted != 0 {
			if escaped { escaped = false; continue }
			if character == '\\' { escaped = true; continue }
			if character == quoted { quoted = 0 }
			continue
		}
		if character == '\'' || character == '"' { quoted = character; continue }
		switch character {
		case '(', '[', '{', '<': depth++
		case ')', ']', '}', '>': depth--
		default:
		}
		if character == delimiter && depth == 0 { parts = append(parts, source[start:index]); start = index + 1 }
	}
	return append(parts, source[start:])
}

func lastTopLevel(source string, target byte) int {
	indices := splitTopLevelIndices(source, target)
	if len(indices) == 0 { return -1 }
	return indices[len(indices)-1]
}

func topLevelIndex(source string, target byte) int {
	indices := splitTopLevelIndices(source, target)
	if len(indices) == 0 { return -1 }
	return indices[0]
}

func splitTopLevelIndices(source string, target byte) []int {
	indices := []int{}
	depth := 0
	quoted := byte(0)
	escaped := false
	for index := 0; index < len(source); index++ {
		character := source[index]
		if quoted != 0 {
			if escaped { escaped = false; continue }
			if character == '\\' { escaped = true; continue }
			if character == quoted { quoted = 0 }
			continue
		}
		if character == '\'' || character == '"' { quoted = character; continue }
		if character == target && depth == 0 { indices = append(indices, index) }
		switch character {
		case '(', '[', '{', '<': depth++
		case ')', ']', '}', '>': depth--
		default:
		}
	}
	return indices
}

func unquoteAtom(name string) string {
	if len(name) >= 2 && name[0] == '\'' && name[len(name)-1] == '\'' { return name[1:len(name)-1] }
	return name
}

package compat

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	HeaderSchema = "gotp.otp-header-declarations/v1"
	PinnedHeaderDeclarationCount = 11780
	PinnedHeaderSourceDigest = "3d26ede95afa6471caf0689c2ea06bd3ffce1a56bdbc13cdf8032475cc2fb6fa"
)

type HeaderDeclarationKind enum {
	HeaderRecord()
	HeaderObjectMacro()
	HeaderFunctionMacro()
	HeaderType()
	HeaderOpaque()
}

type OTPHeaderSource struct {
	Application string
	SourcePath string
	Content string
}

type OTPHeaderDeclaration struct {
	Kind string `json:"kind"`
	Application string `json:"application"`
	Header string `json:"header"`
	Name string `json:"name"`
	Arity int `json:"arity"`
}

type OTPHeaderInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	SourceDigest string `json:"source_digest"`
	Declarations []OTPHeaderDeclaration `json:"declarations"`
}

type HeaderFailure enum {
	HeaderJSONRejected(Cause string)
	HeaderProvenanceRejected(Detail string)
	HeaderSyntaxRejected(Path string, Detail string)
	HeaderOrderingRejected(Detail string)
	HeaderIdentityRejected(Detail string)
	HeaderCountRejected(Found int, Expected int)
}

func (failure HeaderFailure) Error() string {
	match failure {
	case HeaderJSONRejected(cause): return "gotp/compat: header JSON rejected: " + cause
	case HeaderProvenanceRejected(detail): return "gotp/compat: header provenance rejected: " + detail
	case HeaderSyntaxRejected(path, detail): return "gotp/compat: header syntax rejected in " + path + ": " + detail
	case HeaderOrderingRejected(detail): return "gotp/compat: header ordering rejected: " + detail
	case HeaderIdentityRejected(detail): return "gotp/compat: header identity rejected: " + detail
	case HeaderCountRejected(found, expected): return fmt.Sprintf("gotp/compat: header declaration count %d; want %d", found, expected)
	}
}

// assayxport:unit gotp.compat.otp-public-headers
func BuildOTPHeaderInventory(sources []OTPHeaderSource) result.Result[OTPHeaderInventory, HeaderFailure] {
	ordered := append([]OTPHeaderSource{}, sources...)
	sort.Slice(ordered, func(left, right int) bool { return ordered[left].SourcePath < ordered[right].SourcePath })
	declarations := map[string]OTPHeaderDeclaration{}
	var canonical strings.Builder
	priorPath := ""
	for index, source := range ordered {
		if source.Application == "" || source.SourcePath == "" || (index > 0 && source.SourcePath <= priorPath) {
			return result.Err[OTPHeaderInventory, HeaderFailure](HeaderIdentityRejected("empty or duplicate header source"))
		}
		canonical.WriteString(source.SourcePath)
		canonical.WriteByte(0)
		canonical.WriteString(source.Content)
		canonical.WriteByte(0)
		priorPath = source.SourcePath
		match headerDeclarationsFromSource(source) {
		case result.Err(failure): return result.Err[OTPHeaderInventory, HeaderFailure](failure)
		case result.Ok(found):
			for _, declaration := range found {
				id := InventoryHeaderDeclarationID(declaration)
				if prior, present := declarations[id]; present && prior != declaration {
					return result.Err[OTPHeaderInventory, HeaderFailure](HeaderIdentityRejected("normalized collision " + id))
				}
				declarations[id] = declaration
			}
		}
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	inventory := OTPHeaderInventory{Schema: HeaderSchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, SourceDigest: hex.EncodeToString(digest[:])}
	for _, declaration := range declarations { inventory.Declarations = append(inventory.Declarations, declaration) }
	sort.Slice(inventory.Declarations, func(left, right int) bool { return InventoryHeaderDeclarationID(inventory.Declarations[left]) < InventoryHeaderDeclarationID(inventory.Declarations[right]) })
	match ValidateOTPHeaderInventory(inventory) {
	case result.Err(failure): return result.Err[OTPHeaderInventory, HeaderFailure](failure)
	case result.Ok(_): return result.Ok[OTPHeaderInventory, HeaderFailure](inventory)
	}
}

func ParseOTPHeaderInventory(data []byte) result.Result[OTPHeaderInventory, HeaderFailure] {
	var inventory OTPHeaderInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPHeaderInventory, HeaderFailure](HeaderJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPHeaderInventory(inventory) {
	case result.Err(failure): return result.Err[OTPHeaderInventory, HeaderFailure](failure)
	case result.Ok(_):
		inventory.Declarations = append([]OTPHeaderDeclaration{}, inventory.Declarations...)
		return result.Ok[OTPHeaderInventory, HeaderFailure](inventory)
	}
}

func ValidateOTPHeaderInventory(inventory OTPHeaderInventory) result.Result[bool, HeaderFailure] {
	if inventory.Schema != HeaderSchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit || inventory.SourceDigest != PinnedHeaderSourceDigest {
		return result.Err[bool, HeaderFailure](HeaderProvenanceRejected("schema, upstream pin, or source digest differs: " + inventory.SourceDigest))
	}
	if len(inventory.Declarations) != PinnedHeaderDeclarationCount { return result.Err[bool, HeaderFailure](HeaderCountRejected(len(inventory.Declarations), PinnedHeaderDeclarationCount)) }
	prior := ""
	for index, declaration := range inventory.Declarations {
		if declaration.Application == "" || declaration.Header == "" || declaration.Name == "" || declaration.Arity < -1 {
			return result.Err[bool, HeaderFailure](HeaderIdentityRejected("empty or invalid header declaration"))
		}
		match headerDeclarationKind(declaration.Kind) {
		case option.None: return result.Err[bool, HeaderFailure](HeaderIdentityRejected("unknown header declaration kind " + declaration.Kind))
		case option.Some(_):
		}
		id := InventoryHeaderDeclarationID(declaration)
		if index > 0 && id <= prior { return result.Err[bool, HeaderFailure](HeaderOrderingRejected("declarations are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, HeaderFailure](true)
}

func InventoryHeaderDeclarationID(declaration OTPHeaderDeclaration) string {
	return "otp.header." + declaration.Kind + "." + strings.ToLower(declaration.Application) + "." + hex.EncodeToString([]byte(declaration.Header)) + "." + hex.EncodeToString([]byte(declaration.Name)) + "." + strconv.Itoa(declaration.Arity)
}

func MissingHeaderCoverage(inventory OTPHeaderInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, declaration := range inventory.Declarations {
		id := InventoryHeaderDeclarationID(declaration)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func headerDeclarationsFromSource(source OTPHeaderSource) result.Result[[]OTPHeaderDeclaration, HeaderFailure] {
	clean := stripErlangComments(source.Content)
	found := []OTPHeaderDeclaration{}
	match headerWrappedDeclarations(clean, source, "-record(", "record") {
	case result.Err(failure): return result.Err[[]OTPHeaderDeclaration, HeaderFailure](failure)
	case result.Ok(records): found = append(found, records...)
	}
	match headerMacroDeclarations(clean, source) {
	case result.Err(failure): return result.Err[[]OTPHeaderDeclaration, HeaderFailure](failure)
	case result.Ok(macros): found = append(found, macros...)
	}
	for _, attribute := range []struct{ Marker string; Kind string }{{Marker: "-type", Kind: "type"}, {Marker: "-opaque", Kind: "opaque"}} {
		match headerTypedDeclarations(clean, source, attribute.Marker, attribute.Kind) {
		case result.Err(failure): return result.Err[[]OTPHeaderDeclaration, HeaderFailure](failure)
		case result.Ok(types): found = append(found, types...)
		}
	}
	return result.Ok[[]OTPHeaderDeclaration, HeaderFailure](found)
}

func headerWrappedDeclarations(content string, source OTPHeaderSource, marker string, kind string) result.Result[[]OTPHeaderDeclaration, HeaderFailure] {
	match wrappedAttributeBodies(content, marker, source.SourcePath) {
	case result.Err(failure): return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, failure.Error()))
	case result.Ok(bodies):
		found := []OTPHeaderDeclaration{}
		for _, body := range bodies {
			parts := splitTopLevel(body, ',')
			if len(parts) < 2 { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, kind + " has no body")) }
			name := unquoteAtom(strings.TrimSpace(parts[0]))
			if name == "" { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, "empty " + kind + " name")) }
			found = append(found, OTPHeaderDeclaration{Kind: kind, Application: source.Application, Header: source.SourcePath, Name: name, Arity: -1})
		}
		return result.Ok[[]OTPHeaderDeclaration, HeaderFailure](found)
	}
}

func headerMacroDeclarations(content string, source OTPHeaderSource) result.Result[[]OTPHeaderDeclaration, HeaderFailure] {
	match wrappedAttributeBodies(content, "-define(", source.SourcePath) {
	case result.Err(failure): return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, failure.Error()))
	case result.Ok(bodies):
		found := []OTPHeaderDeclaration{}
		for _, body := range bodies {
			parts := splitTopLevel(body, ',')
			if len(parts) < 2 { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, "macro has no replacement")) }
			head := strings.TrimSpace(parts[0])
			kind := "macro-object"
			arity := -1
			name := unquoteAtom(head)
			open := topLevelIndex(head, '(')
			if open > 0 && strings.HasSuffix(head, ")") {
				kind = "macro-function"
				name = unquoteAtom(strings.TrimSpace(head[:open]))
				arguments := strings.TrimSpace(head[open+1:len(head)-1])
				arity = 0
				if arguments != "" { arity = len(splitTopLevel(arguments, ',')) }
			}
			if name == "" { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, "empty macro name")) }
			found = append(found, OTPHeaderDeclaration{Kind: kind, Application: source.Application, Header: source.SourcePath, Name: name, Arity: arity})
		}
		return result.Ok[[]OTPHeaderDeclaration, HeaderFailure](found)
	}
}

func headerTypedDeclarations(content string, source OTPHeaderSource, marker string, kind string) result.Result[[]OTPHeaderDeclaration, HeaderFailure] {
	found := []OTPHeaderDeclaration{}
	offset := 0
	for {
		relative := strings.Index(content[offset:], marker)
		if relative < 0 { return result.Ok[[]OTPHeaderDeclaration, HeaderFailure](found) }
		markerStart := offset + relative
		if !attributeLineStart(content, markerStart) { offset = markerStart + len(marker); continue }
		start := markerStart + len(marker)
		for start < len(content) && (content[start] == ' ' || content[start] == '\t' || content[start] == '\r' || content[start] == '\n') { start++ }
		open := topLevelIndex(content[start:], '(')
		if open < 1 { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, kind + " has no argument list")) }
		open += start
		match matchingDelimiter(content, open, '(', ')') {
		case option.None: return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, "unterminated " + kind + " arguments"))
		case option.Some(end):
			name := unquoteAtom(strings.TrimSpace(content[start:open]))
			arguments := strings.TrimSpace(content[open+1:end])
			arity := 0
			if arguments != "" { arity = len(splitTopLevel(arguments, ',')) }
			if name == "" { return result.Err[[]OTPHeaderDeclaration, HeaderFailure](HeaderSyntaxRejected(source.SourcePath, "empty " + kind + " name")) }
			found = append(found, OTPHeaderDeclaration{Kind: kind, Application: source.Application, Header: source.SourcePath, Name: name, Arity: arity})
			offset = end + 1
		}
	}
}

func headerDeclarationKind(kind string) option.Option[HeaderDeclarationKind] {
	switch kind {
	case "record": return option.Some[HeaderDeclarationKind](HeaderRecord())
	case "macro-object": return option.Some[HeaderDeclarationKind](HeaderObjectMacro())
	case "macro-function": return option.Some[HeaderDeclarationKind](HeaderFunctionMacro())
	case "type": return option.Some[HeaderDeclarationKind](HeaderType())
	case "opaque": return option.Some[HeaderDeclarationKind](HeaderOpaque())
	default: return option.None[HeaderDeclarationKind]
	}
}

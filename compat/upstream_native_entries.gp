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
	NativeEntrySchema = "gotp.otp-native-entries/v1"
	PinnedNativeEntrySourceCount = 860
	PinnedNativeEntryCount = 296
	PinnedNativeEntrySourceDigest = "2652b1943775661f8be7b8092be85c411e6e9e91f399f37f006618a7a81c376c"
)

type NativeEntryKind enum {
	NativeNIFModule()
	NativeNIFFunction()
	NativeDriverModule()
}

type OTPNativeSource struct {
	Application string
	SourcePath string
	Content string
}

type OTPNativeEntry struct {
	Kind string `json:"kind"`
	Application string `json:"application"`
	SourcePath string `json:"source_path"`
	Module string `json:"module"`
	Name string `json:"name"`
	Arity int `json:"arity"`
	Flags string `json:"flags,omitempty"`
	Load string `json:"load,omitempty"`
	Reload string `json:"reload,omitempty"`
	Upgrade string `json:"upgrade,omitempty"`
	Unload string `json:"unload,omitempty"`
}

type OTPNativeEntryInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	SourceDigest string `json:"source_digest"`
	SourceCount int `json:"source_count"`
	Entries []OTPNativeEntry `json:"entries"`
}

type NativeEntryFailure enum {
	NativeEntryJSONRejected(Cause string)
	NativeEntrySourceRejected(Path string, Detail string)
	NativeEntryInventoryRejected(Detail string)
}

func (failure NativeEntryFailure) Error() string {
	match failure {
	case NativeEntryJSONRejected(cause): return "gotp/compat: native entry JSON rejected: " + cause
	case NativeEntrySourceRejected(path, detail): return "gotp/compat: native entry source rejected " + path + ": " + detail
	case NativeEntryInventoryRejected(detail): return "gotp/compat: native entry inventory rejected: " + detail
	}
}

// assayxport:unit gotp.compat.otp-native-entries
func BuildOTPNativeEntryInventory(sources []OTPNativeSource) result.Result[OTPNativeEntryInventory, NativeEntryFailure] {
	ordered := append([]OTPNativeSource{}, sources...)
	sort.Slice(ordered, func(left, right int) bool { return ordered[left].SourcePath < ordered[right].SourcePath })
	var canonical strings.Builder
	priorPath := ""
	entries := map[string]OTPNativeEntry{}
	for index, source := range ordered {
		if source.Application == "" || source.SourcePath == "" || (index > 0 && source.SourcePath <= priorPath) { return result.Err[OTPNativeEntryInventory, NativeEntryFailure](NativeEntryInventoryRejected("empty or duplicate native source")) }
		canonical.WriteString(source.SourcePath); canonical.WriteByte(0); canonical.WriteString(source.Content); canonical.WriteByte(0); priorPath = source.SourcePath
		if !nativeImplementationPath(source.SourcePath) { continue }
		match nativeEntriesFromSource(source) {
		case result.Err(failure): return result.Err[OTPNativeEntryInventory, NativeEntryFailure](failure)
		case result.Ok(found):
			for _, entry := range found {
				id := InventoryNativeEntryID(entry)
				if prior, present := entries[id]; present && prior != entry { return result.Err[OTPNativeEntryInventory, NativeEntryFailure](NativeEntryInventoryRejected("conflicting native entry " + id)) }
				entries[id] = entry
			}
		}
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	inventory := OTPNativeEntryInventory{Schema: NativeEntrySchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, SourceDigest: hex.EncodeToString(digest[:]), SourceCount: len(ordered)}
	for _, entry := range entries { inventory.Entries = append(inventory.Entries, entry) }
	sort.Slice(inventory.Entries, func(left, right int) bool { return InventoryNativeEntryID(inventory.Entries[left]) < InventoryNativeEntryID(inventory.Entries[right]) })
	match ValidateOTPNativeEntryInventory(inventory) {
	case result.Err(failure): return result.Err[OTPNativeEntryInventory, NativeEntryFailure](failure)
	case result.Ok(_): return result.Ok[OTPNativeEntryInventory, NativeEntryFailure](inventory)
	}
}

func ParseOTPNativeEntryInventory(data []byte) result.Result[OTPNativeEntryInventory, NativeEntryFailure] {
	var inventory OTPNativeEntryInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPNativeEntryInventory, NativeEntryFailure](NativeEntryJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPNativeEntryInventory(inventory) {
	case result.Err(failure): return result.Err[OTPNativeEntryInventory, NativeEntryFailure](failure)
	case result.Ok(_):
		inventory.Entries = append([]OTPNativeEntry{}, inventory.Entries...)
		return result.Ok[OTPNativeEntryInventory, NativeEntryFailure](inventory)
	}
}

func ValidateOTPNativeEntryInventory(inventory OTPNativeEntryInventory) result.Result[bool, NativeEntryFailure] {
	if inventory.Schema != NativeEntrySchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("schema or upstream pin differs")) }
	if inventory.SourceDigest != PinnedNativeEntrySourceDigest { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("source digest differs: " + inventory.SourceDigest)) }
	if inventory.SourceCount != PinnedNativeEntrySourceCount { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected(fmt.Sprintf("source count %d; want %d", inventory.SourceCount, PinnedNativeEntrySourceCount))) }
	if len(inventory.Entries) != PinnedNativeEntryCount { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected(fmt.Sprintf("entry count %d; want %d", len(inventory.Entries), PinnedNativeEntryCount))) }
	prior := ""
	for index, entry := range inventory.Entries {
		if entry.Application == "" || entry.SourcePath == "" || entry.Module == "" || entry.Name == "" || entry.Arity < -1 { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("empty native entry identity")) }
		match nativeEntryKind(entry.Kind) {
		case option.None: return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("unknown native entry kind " + entry.Kind))
		case option.Some(_):
		}
		if entry.Kind == "nif-function" && entry.Arity < 0 { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("negative NIF arity")) }
		id := InventoryNativeEntryID(entry)
		if index > 0 && id <= prior { return result.Err[bool, NativeEntryFailure](NativeEntryInventoryRejected("native entries are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, NativeEntryFailure](true)
}

func InventoryNativeEntryID(entry OTPNativeEntry) string {
	identity := entry.Module + "\x00" + entry.Name + "\x00" + strconv.Itoa(entry.Arity)
	return "otp.native-entry." + entry.Kind + "." + hex.EncodeToString([]byte(identity))
}

func MissingNativeEntryCoverage(inventory OTPNativeEntryInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, entry := range inventory.Entries {
		id := InventoryNativeEntryID(entry)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func nativeEntriesFromSource(source OTPNativeSource) result.Result[[]OTPNativeEntry, NativeEntryFailure] {
	clean := stripCComments(source.Content)
	entries := []OTPNativeEntry{}
	match cMacroBodies(clean, "ERL_NIF_INIT", source.SourcePath) {
	case result.Err(failure): return result.Err[[]OTPNativeEntry, NativeEntryFailure](failure)
	case result.Ok(initializers):
		for _, initializer := range initializers {
			parts := splitTopLevel(initializer, ',')
			if len(parts) != 6 { return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "ERL_NIF_INIT requires six arguments")) }
			module := strings.TrimSpace(parts[0])
			table := strings.TrimSpace(parts[1])
			if module == "" || table == "" { return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "empty NIF module or table")) }
			entries = append(entries, OTPNativeEntry{Kind: "nif-module", Application: source.Application, SourcePath: source.SourcePath, Module: module, Name: module, Arity: -1, Load: strings.TrimSpace(parts[2]), Reload: strings.TrimSpace(parts[3]), Upgrade: strings.TrimSpace(parts[4]), Unload: strings.TrimSpace(parts[5])})
			match cArrayBodies(clean, table, source.SourcePath) {
			case result.Err(failure): return result.Err[[]OTPNativeEntry, NativeEntryFailure](failure)
			case result.Ok(arrays):
				for _, array := range arrays {
					match nifFunctionsFromArray(source, module, array) {
					case result.Err(failure): return result.Err[[]OTPNativeEntry, NativeEntryFailure](failure)
					case result.Ok(functions): entries = append(entries, functions...)
					}
				}
			}
		}
	}
	match cMacroBodies(clean, "DRIVER_INIT", source.SourcePath) {
	case result.Err(failure): return result.Err[[]OTPNativeEntry, NativeEntryFailure](failure)
	case result.Ok(initializers):
		for _, initializer := range initializers {
			name := strings.TrimSpace(initializer)
			if name == "" { return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "empty DRIVER_INIT name")) }
			entries = append(entries, OTPNativeEntry{Kind: "driver-module", Application: source.Application, SourcePath: source.SourcePath, Module: name, Name: name, Arity: -1})
		}
	}
	return result.Ok[[]OTPNativeEntry, NativeEntryFailure](entries)
}

func cMacroBodies(content string, macro string, path string) result.Result[[]string, NativeEntryFailure] {
	bodies := []string{}
	offset := 0
	for {
		relative := strings.Index(content[offset:], macro)
		if relative < 0 { return result.Ok[[]string, NativeEntryFailure](bodies) }
		start := offset + relative
		if (start > 0 && cIdentifierByte(content[start-1])) || (start+len(macro) < len(content) && cIdentifierByte(content[start+len(macro)])) { offset = start + len(macro); continue }
		open := start + len(macro)
		for open < len(content) && (content[open] == ' ' || content[open] == '\t' || content[open] == '\r' || content[open] == '\n') { open++ }
		if open >= len(content) || content[open] != '(' { offset = start + len(macro); continue }
		match matchingDelimiter(content, open, '(', ')') {
		case option.None: return result.Err[[]string, NativeEntryFailure](NativeEntrySourceRejected(path, "unterminated " + macro))
		case option.Some(end): bodies = append(bodies, content[open+1:end]); offset = end + 1
		}
	}
}

func cArrayBodies(content string, name string, path string) result.Result[[]string, NativeEntryFailure] {
	bodies := []string{}
	offset := 0
	for {
		relative := strings.Index(content[offset:], name)
		if relative < 0 { return result.Ok[[]string, NativeEntryFailure](bodies) }
		start := offset + relative
		if (start > 0 && cIdentifierByte(content[start-1])) || (start+len(name) < len(content) && cIdentifierByte(content[start+len(name)])) { offset = start + len(name); continue }
		position := start + len(name)
		for position < len(content) && (content[position] == ' ' || content[position] == '\t' || content[position] == '\r' || content[position] == '\n') { position++ }
		if position >= len(content) || content[position] != '[' { offset = start + len(name); continue }
		match matchingDelimiter(content, position, '[', ']') {
		case option.None: return result.Err[[]string, NativeEntryFailure](NativeEntrySourceRejected(path, "unterminated NIF table dimension"))
		case option.Some(bracketEnd):
			position = bracketEnd + 1
			for position < len(content) && (content[position] == ' ' || content[position] == '\t' || content[position] == '\r' || content[position] == '\n') { position++ }
			if position >= len(content) || content[position] != '=' { offset = bracketEnd + 1; continue }
			position++
			for position < len(content) && (content[position] == ' ' || content[position] == '\t' || content[position] == '\r' || content[position] == '\n') { position++ }
			if position >= len(content) || content[position] != '{' { offset = position; continue }
			match matchingDelimiter(content, position, '{', '}') {
			case option.None: return result.Err[[]string, NativeEntryFailure](NativeEntrySourceRejected(path, "unterminated NIF table initializer"))
			case option.Some(end): bodies = append(bodies, content[position+1:end]); offset = end + 1
			}
		}
	}
}

func nifFunctionsFromArray(source OTPNativeSource, module string, body string) result.Result[[]OTPNativeEntry, NativeEntryFailure] {
	functions := []OTPNativeEntry{}
	offset := 0
	for offset < len(body) {
		open := strings.IndexByte(body[offset:], '{')
		if open < 0 { break }
		open += offset
		match matchingDelimiter(body, open, '{', '}') {
		case option.None: return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "unterminated NIF function entry"))
		case option.Some(end):
			parts := splitTopLevel(body[open+1:end], ',')
			if len(parts) < 3 || len(parts) > 4 { return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "NIF function entry requires three or four fields")) }
			name := strings.TrimSpace(parts[0])
			if len(name) < 2 || name[0] != '"' || name[len(name)-1] != '"' { return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "NIF function name is not a string literal")) }
			name = name[1:len(name)-1]
			arity, cause := strconv.Atoi(strings.TrimSpace(parts[1]))
			match result.Of(arity, cause) {
			case result.Err(_): return result.Err[[]OTPNativeEntry, NativeEntryFailure](NativeEntrySourceRejected(source.SourcePath, "NIF arity is not an integer"))
			case result.Ok(arity):
				flags := "0"
				if len(parts) == 4 { flags = strings.TrimSpace(parts[3]) }
				functions = append(functions, OTPNativeEntry{Kind: "nif-function", Application: source.Application, SourcePath: source.SourcePath, Module: module, Name: name, Arity: arity, Flags: flags})
			}
			offset = end + 1
		}
	}
	return result.Ok[[]OTPNativeEntry, NativeEntryFailure](functions)
}

func stripCComments(source string) string {
	var output strings.Builder
	lineComment := false
	blockComment := false
	quoted := byte(0)
	escaped := false
	for index := 0; index < len(source); index++ {
		character := source[index]
		if lineComment {
			if character == '\n' { lineComment = false; output.WriteByte(character) } else { output.WriteByte(' ') }
			continue
		}
		if blockComment {
			if character == '*' && index+1 < len(source) && source[index+1] == '/' { output.WriteString("  "); index++; blockComment = false; continue }
			if character == '\n' { output.WriteByte(character) } else { output.WriteByte(' ') }
			continue
		}
		if quoted != 0 {
			output.WriteByte(character)
			if escaped { escaped = false; continue }
			if character == '\\' { escaped = true; continue }
			if character == quoted { quoted = 0 }
			continue
		}
		if character == '/' && index+1 < len(source) && source[index+1] == '/' { output.WriteString("  "); index++; lineComment = true; continue }
		if character == '/' && index+1 < len(source) && source[index+1] == '*' { output.WriteString("  "); index++; blockComment = true; continue }
		if character == '"' || character == '\'' { quoted = character }
		output.WriteByte(character)
	}
	return output.String()
}

func nativeImplementationPath(path string) bool {
	for _, suffix := range []string{".c", ".cc", ".cpp"} { if strings.HasSuffix(path, suffix) { return true } }
	return false
}

func cIdentifierByte(value byte) bool { return value == '_' || value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9' }

func nativeEntryKind(kind string) option.Option[NativeEntryKind] {
	switch kind {
	case "nif-module": return option.Some[NativeEntryKind](NativeNIFModule())
	case "nif-function": return option.Some[NativeEntryKind](NativeNIFFunction())
	case "driver-module": return option.Some[NativeEntryKind](NativeDriverModule())
	default: return option.None[NativeEntryKind]
	}
}

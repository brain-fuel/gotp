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

const NativeMacroSchema = "gotp.otp-native-macros/v1"

type nativeMacroProfilePin struct { Count int; Digest string }

var pinnedNativeMacroProfiles = map[string]nativeMacroProfilePin{
	"darwin-arm64-lp64": {Count: 186, Digest: "75d6216a076a0e139263ecf4c99e085aea2f8a075c93a4582b7c9a7d195a90df"},
	"linux-amd64-lp64": {Count: 186, Digest: "339137728a75195bc4a8c74329f03fda89f11cf7f354e8afbb3c2f668ad89f9c"},
	"linux-arm64-lp64": {Count: 186, Digest: "c7ceb7adb36b2b65e3c4faa40dd5aab51ee96a3bea4b17deed254c014c55a281"},
	"windows-amd64-llp64": {Count: 489, Digest: "1f7baba76aa2433b79cbc8c5ea681c5b72484e5a6b354cfb6e48acb2cd50782c"},
}

type NativeMacroForm enum {
	NativeObjectMacro()
	NativeFunctionMacro()
}

type OTPNativeHeader struct {
	Surface string
	SourcePath string
	Content string
}

type OTPNativeMacro struct {
	Profile string `json:"profile"`
	Surface string `json:"surface"`
	SourcePath string `json:"source_path"`
	Name string `json:"name"`
	Form string `json:"form"`
	Arity int `json:"arity,omitempty"`
	Variadic bool `json:"variadic,omitempty"`
	Replacement string `json:"replacement,omitempty"`
}

type OTPNativeMacroInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	Profile string `json:"profile"`
	SourceDigest string `json:"source_digest"`
	SourceCount int `json:"source_count"`
	Macros []OTPNativeMacro `json:"macros"`
}

type NativeMacroFailure enum {
	NativeMacroJSONRejected(Cause string)
	NativeMacroSourceRejected(Path string, Detail string)
	NativeMacroInventoryRejected(Detail string)
}

func (failure NativeMacroFailure) Error() string {
	match failure {
	case NativeMacroJSONRejected(cause): return "gotp/compat: native macro JSON rejected: " + cause
	case NativeMacroSourceRejected(path, detail): return "gotp/compat: native macro source rejected " + path + ": " + detail
	case NativeMacroInventoryRejected(detail): return "gotp/compat: native macro inventory rejected: " + detail
	}
}

type nativeMacroDirective struct {
	Name string
	Form NativeMacroForm
	Arity int
	Variadic bool
	Replacement string
}

// assayxport:unit gotp.compat.otp-native-macros
func BuildOTPNativeMacroInventory(profile string, headers []OTPNativeHeader, activeDump string) result.Result[OTPNativeMacroInventory, NativeMacroFailure] {
	if strings.TrimSpace(profile) == "" { return result.Err[OTPNativeMacroInventory, NativeMacroFailure](NativeMacroInventoryRejected("empty profile")) }
	match parseNativeMacroDirectives("<active-macro-dump>", activeDump) {
	case result.Err(failure): return result.Err[OTPNativeMacroInventory, NativeMacroFailure](failure)
	case result.Ok(activeDirectives):
		active := map[string]nativeMacroDirective{}
		for _, directive := range activeDirectives { active[directive.Name] = directive }
		ordered := append([]OTPNativeHeader{}, headers...)
		sort.Slice(ordered, func(left, right int) bool { return ordered[left].SourcePath < ordered[right].SourcePath })
		var canonical strings.Builder
		canonical.WriteString(profile); canonical.WriteByte(0); canonical.WriteString(activeDump); canonical.WriteByte(0)
		inventory := OTPNativeMacroInventory{Schema: NativeMacroSchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, Profile: profile, SourceCount: len(ordered)}
		priorPath := ""
		seen := map[string]OTPNativeMacro{}
		for index, header := range ordered {
			if header.Surface == "" || header.SourcePath == "" || (index > 0 && header.SourcePath <= priorPath) { return result.Err[OTPNativeMacroInventory, NativeMacroFailure](NativeMacroInventoryRejected("empty or duplicate native header")) }
			canonical.WriteString(header.Surface); canonical.WriteByte(0); canonical.WriteString(header.SourcePath); canonical.WriteByte(0); canonical.WriteString(header.Content); canonical.WriteByte(0)
			priorPath = header.SourcePath
			match parseNativeMacroDirectives(header.SourcePath, header.Content) {
			case result.Err(failure): return result.Err[OTPNativeMacroInventory, NativeMacroFailure](failure)
			case result.Ok(declarations):
				for _, declaration := range declarations {
					enabled, present := active[declaration.Name]
					var enabledOption option.Option[nativeMacroDirective] = option.Of(enabled, present)
					match enabledOption {
					case option.None:
					case option.Some(enabled):
						macro := OTPNativeMacro{Profile: profile, Surface: header.Surface, SourcePath: header.SourcePath, Name: declaration.Name, Form: nativeMacroFormName(enabled.Form), Arity: enabled.Arity, Variadic: enabled.Variadic, Replacement: enabled.Replacement}
						id := InventoryNativeMacroID(macro)
						if prior, present := seen[id]; present && prior != macro { return result.Err[OTPNativeMacroInventory, NativeMacroFailure](NativeMacroInventoryRejected("conflicting active macro " + id)) }
						seen[id] = macro
					}
				}
			}
		}
		digest := sha256.Sum256([]byte(canonical.String()))
		inventory.SourceDigest = hex.EncodeToString(digest[:])
		for _, macro := range seen { inventory.Macros = append(inventory.Macros, macro) }
		sort.Slice(inventory.Macros, func(left, right int) bool { return InventoryNativeMacroID(inventory.Macros[left]) < InventoryNativeMacroID(inventory.Macros[right]) })
		match validateOTPNativeMacroInventory(inventory, false) {
		case result.Err(failure): return result.Err[OTPNativeMacroInventory, NativeMacroFailure](failure)
		case result.Ok(_): return result.Ok[OTPNativeMacroInventory, NativeMacroFailure](inventory)
		}
	}
}

func ParseOTPNativeMacroInventory(data []byte) result.Result[OTPNativeMacroInventory, NativeMacroFailure] {
	var inventory OTPNativeMacroInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPNativeMacroInventory, NativeMacroFailure](NativeMacroJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPNativeMacroInventory(inventory) {
	case result.Err(failure): return result.Err[OTPNativeMacroInventory, NativeMacroFailure](failure)
	case result.Ok(_): return result.Ok[OTPNativeMacroInventory, NativeMacroFailure](inventory)
	}
}

func ValidateOTPNativeMacroInventory(inventory OTPNativeMacroInventory) result.Result[bool, NativeMacroFailure] {
	return validateOTPNativeMacroInventory(inventory, true)
}

func validateOTPNativeMacroInventory(inventory OTPNativeMacroInventory, requirePin bool) result.Result[bool, NativeMacroFailure] {
	if inventory.Schema != NativeMacroSchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("schema or upstream pin differs")) }
	if inventory.Profile == "" || inventory.SourceDigest == "" || inventory.SourceCount < 1 { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("empty profile or provenance")) }
	if requirePin {
		pin, pinned := pinnedNativeMacroProfiles[inventory.Profile]
		match option.Of(pin, pinned) {
		case option.None: return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("unknown profile " + inventory.Profile))
		case option.Some(pin):
			if inventory.SourceDigest != pin.Digest { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("source digest differs: " + inventory.SourceDigest)) }
			if len(inventory.Macros) != pin.Count { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected(fmt.Sprintf("macro count %d; want %d", len(inventory.Macros), pin.Count))) }
		}
	}
	prior := ""
	for index, macro := range inventory.Macros {
		if macro.Profile != inventory.Profile || macro.Surface == "" || macro.SourcePath == "" || macro.Name == "" || macro.Arity < 0 { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("empty native macro identity")) }
		match nativeMacroForm(macro.Form) {
		case option.None: return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("unknown macro form " + macro.Form))
		case option.Some(form):
			match form {
			case NativeObjectMacro: if macro.Arity != 0 || macro.Variadic { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("object macro has parameters")) }
			case NativeFunctionMacro:
			}
		}
		id := InventoryNativeMacroID(macro)
		if index > 0 && id <= prior { return result.Err[bool, NativeMacroFailure](NativeMacroInventoryRejected("native macros are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, NativeMacroFailure](true)
}

func InventoryNativeMacroID(macro OTPNativeMacro) string {
	identity := macro.SourcePath + "\x00" + macro.Name + "\x00" + macro.Form + "\x00" + strconv.Itoa(macro.Arity) + "\x00" + strconv.FormatBool(macro.Variadic)
	return "otp.native-macro." + macro.Profile + "." + macro.Surface + ".x" + hex.EncodeToString([]byte(identity))
}

func MissingNativeMacroCoverage(inventory OTPNativeMacroInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, macro := range inventory.Macros {
		id := InventoryNativeMacroID(macro)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func parseNativeMacroDirectives(path string, content string) result.Result[[]nativeMacroDirective, NativeMacroFailure] {
	logical := strings.ReplaceAll(strings.ReplaceAll(content, "\\\r\n", " "), "\\\n", " ")
	logical = stripCComments(logical)
	directives := []nativeMacroDirective{}
	for _, line := range strings.Split(logical, "\n") {
		body := strings.TrimSpace(line)
		if !strings.HasPrefix(body, "#") { continue }
		body = strings.TrimSpace(strings.TrimPrefix(body, "#"))
		if !strings.HasPrefix(body, "define") || (len(body) > len("define") && !nativeMacroSpace(body[len("define")])) { continue }
		body = strings.TrimSpace(body[len("define"):])
		if body == "" { return result.Err[[]nativeMacroDirective, NativeMacroFailure](NativeMacroSourceRejected(path, "empty define")) }
		end := 0
		for end < len(body) && nativeMacroIdentifier(body[end], end == 0) { end++ }
		if end == 0 { return result.Err[[]nativeMacroDirective, NativeMacroFailure](NativeMacroSourceRejected(path, "invalid macro name")) }
		name := body[:end]
		directive := nativeMacroDirective{Name: name, Form: NativeObjectMacro()}
		if end < len(body) && body[end] == '(' {
			close := strings.IndexByte(body[end:], ')')
			if close < 0 { return result.Err[[]nativeMacroDirective, NativeMacroFailure](NativeMacroSourceRejected(path, "unterminated parameters for " + name)) }
			close += end
			parameters := strings.TrimSpace(body[end+1:close])
			directive.Form = NativeFunctionMacro()
			if parameters != "" {
				for _, parameter := range strings.Split(parameters, ",") {
					parameter = strings.TrimSpace(parameter)
					if parameter == "..." || strings.HasSuffix(parameter, "...") { directive.Variadic = true } else if parameter == "" { return result.Err[[]nativeMacroDirective, NativeMacroFailure](NativeMacroSourceRejected(path, "empty parameter for " + name)) }
					directive.Arity++
				}
			}
			body = body[close+1:]
		} else { body = body[end:] }
		directive.Replacement = strings.Join(strings.Fields(body), " ")
		directives = append(directives, directive)
	}
	return result.Ok[[]nativeMacroDirective, NativeMacroFailure](directives)
}

func nativeMacroIdentifier(value byte, first bool) bool {
	return value == '_' || value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z' || !first && value >= '0' && value <= '9'
}

func nativeMacroSpace(value byte) bool { return value == ' ' || value == '\t' || value == '\r' || value == '\n' }

func nativeMacroFormName(form NativeMacroForm) string {
	match form {
	case NativeObjectMacro: return "object"
	case NativeFunctionMacro: return "function"
	}
}

func nativeMacroForm(form string) option.Option[NativeMacroForm] {
	switch form {
	case "object": return option.Some[NativeMacroForm](NativeObjectMacro())
	case "function": return option.Some[NativeMacroForm](NativeFunctionMacro())
	default: return option.None[NativeMacroForm]()
	}
}

func NativeMacroInventorySummary(inventory OTPNativeMacroInventory) string {
	objects, functions := 0, 0
	for _, macro := range inventory.Macros { if macro.Form == "object" { objects++ } else { functions++ } }
	return fmt.Sprintf("%s: %d macros (%d object, %d function)", inventory.Profile, len(inventory.Macros), objects, functions)
}

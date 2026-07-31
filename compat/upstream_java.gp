package compat

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	JavaInventorySchema = "gotp.otp-java-api/v1"
	PinnedJavaCompiler = "javac 21.0.12"
	PinnedJavaSourceCount = 57
	PinnedJavaClassCount = 65
	PinnedJavaSymbolCount = 730
	PinnedJavaSourceDigest = "3c059636cd68ae676f60b8604b2ec72008a106dcd41ea7f4d8bf49b48fec8898"
	PinnedJavaClassDigest = "2cee8091c1d10749787884aa96e0f70cafe898fbaf42642942ac11b8d87f74c1"
)

type OTPJavaSource struct {
	SourcePath string
	Content []byte
}

type OTPJavaClass struct {
	ClassPath string
	Content []byte
}

type OTPJavaAPIInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	Compiler string `json:"compiler"`
	SourceDigest string `json:"source_digest"`
	ClassDigest string `json:"class_digest"`
	SourceCount int `json:"source_count"`
	ClassCount int `json:"class_count"`
	Symbols []JavaSymbol `json:"symbols"`
}

// assayxport:unit gotp.compat.otp-java-api
func BuildOTPJavaAPIInventory(compiler string, sources []OTPJavaSource, classes []OTPJavaClass) result.Result[OTPJavaAPIInventory, JavaFailure] {
	orderedSources := append([]OTPJavaSource{}, sources...)
	sort.Slice(orderedSources, func(left, right int) bool { return orderedSources[left].SourcePath < orderedSources[right].SourcePath })
	match digestJavaSources(orderedSources) {
	case result.Err(failure): return result.Err[OTPJavaAPIInventory, JavaFailure](failure)
	case result.Ok(sourceDigest):
		orderedClasses := append([]OTPJavaClass{}, classes...)
		sort.Slice(orderedClasses, func(left, right int) bool { return orderedClasses[left].ClassPath < orderedClasses[right].ClassPath })
		match digestJavaClasses(orderedClasses) {
		case result.Err(failure): return result.Err[OTPJavaAPIInventory, JavaFailure](failure)
		case result.Ok(classDigest):
			symbols := map[string]JavaSymbol{}
			for _, class := range orderedClasses {
				match ParseJVMClass(class.ClassPath, class.Content) {
				case result.Err(failure): return result.Err[OTPJavaAPIInventory, JavaFailure](failure)
				case result.Ok(api):
					for _, symbol := range api.Symbols {
						id := InventoryJavaSymbolID(symbol)
						if prior, present := symbols[id]; present && !sameJavaSymbol(prior, symbol) { return result.Err[OTPJavaAPIInventory, JavaFailure](JavaInventoryRejected("symbol collision " + id)) }
						symbols[id] = symbol
					}
				}
			}
			inventory := OTPJavaAPIInventory{Schema: JavaInventorySchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, Compiler: compiler, SourceDigest: sourceDigest, ClassDigest: classDigest, SourceCount: len(orderedSources), ClassCount: len(orderedClasses)}
			for _, symbol := range symbols { inventory.Symbols = append(inventory.Symbols, symbol) }
			sort.Slice(inventory.Symbols, func(left, right int) bool { return InventoryJavaSymbolID(inventory.Symbols[left]) < InventoryJavaSymbolID(inventory.Symbols[right]) })
			match ValidateOTPJavaAPIInventory(inventory) {
			case result.Err(failure): return result.Err[OTPJavaAPIInventory, JavaFailure](failure)
			case result.Ok(_): return result.Ok[OTPJavaAPIInventory, JavaFailure](inventory)
			}
		}
	}
}

func ParseOTPJavaAPIInventory(data []byte) result.Result[OTPJavaAPIInventory, JavaFailure] {
	var inventory OTPJavaAPIInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPJavaAPIInventory, JavaFailure](JavaJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPJavaAPIInventory(inventory) {
	case result.Err(failure): return result.Err[OTPJavaAPIInventory, JavaFailure](failure)
	case result.Ok(_):
		inventory.Symbols = cloneJavaSymbols(inventory.Symbols)
		return result.Ok[OTPJavaAPIInventory, JavaFailure](inventory)
	}
}

func ValidateOTPJavaAPIInventory(inventory OTPJavaAPIInventory) result.Result[bool, JavaFailure] {
	if inventory.Schema != JavaInventorySchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit { return result.Err[bool, JavaFailure](JavaInventoryRejected("schema or upstream pin differs")) }
	if inventory.Compiler != PinnedJavaCompiler { return result.Err[bool, JavaFailure](JavaInventoryRejected("compiler differs: " + inventory.Compiler)) }
	if inventory.SourceDigest != PinnedJavaSourceDigest { return result.Err[bool, JavaFailure](JavaInventoryRejected("source digest differs: " + inventory.SourceDigest)) }
	if inventory.ClassDigest != PinnedJavaClassDigest { return result.Err[bool, JavaFailure](JavaInventoryRejected("class digest differs: " + inventory.ClassDigest)) }
	if inventory.SourceCount != PinnedJavaSourceCount || inventory.ClassCount != PinnedJavaClassCount { return result.Err[bool, JavaFailure](JavaInventoryRejected(fmt.Sprintf("source/class counts %d/%d", inventory.SourceCount, inventory.ClassCount))) }
	if len(inventory.Symbols) != PinnedJavaSymbolCount { return result.Err[bool, JavaFailure](JavaInventoryRejected(fmt.Sprintf("symbol count %d; want %d", len(inventory.Symbols), PinnedJavaSymbolCount))) }
	prior := ""
	for index, symbol := range inventory.Symbols {
		if symbol.Class == "" || symbol.Name == "" || symbol.Descriptor == "" { return result.Err[bool, JavaFailure](JavaInventoryRejected("empty symbol identity")) }
		match javaSymbolKind(symbol.Kind) {
		case option.None: return result.Err[bool, JavaFailure](JavaInventoryRejected("unknown symbol kind " + symbol.Kind))
		case option.Some(_):
		}
		if symbol.Visibility != "public" && symbol.Visibility != "protected" { return result.Err[bool, JavaFailure](JavaInventoryRejected("non-public API visibility")) }
		id := InventoryJavaSymbolID(symbol)
		if index > 0 && id <= prior { return result.Err[bool, JavaFailure](JavaInventoryRejected("symbols are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, JavaFailure](true)
}

func InventoryJavaSymbolID(symbol JavaSymbol) string {
	identity := symbol.Class + "\x00" + symbol.Name + "\x00" + symbol.Descriptor + "\x00" + symbol.GenericSignature
	return "otp.java." + symbol.Kind + "." + hex.EncodeToString([]byte(identity))
}

func MissingJavaCoverage(inventory OTPJavaAPIInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, symbol := range inventory.Symbols {
		id := InventoryJavaSymbolID(symbol)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func digestJavaSources(sources []OTPJavaSource) result.Result[string, JavaFailure] {
	var canonical strings.Builder
	prior := ""
	for index, source := range sources {
		if source.SourcePath == "" || (index > 0 && source.SourcePath <= prior) { return result.Err[string, JavaFailure](JavaInventoryRejected("empty or duplicate Java source path")) }
		canonical.WriteString(source.SourcePath); canonical.WriteByte(0); canonical.Write(source.Content); canonical.WriteByte(0); prior = source.SourcePath
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	return result.Ok[string, JavaFailure](hex.EncodeToString(digest[:]))
}

func digestJavaClasses(classes []OTPJavaClass) result.Result[string, JavaFailure] {
	var canonical strings.Builder
	prior := ""
	for index, class := range classes {
		if class.ClassPath == "" || (index > 0 && class.ClassPath <= prior) { return result.Err[string, JavaFailure](JavaInventoryRejected("empty or duplicate Java class path")) }
		canonical.WriteString(class.ClassPath); canonical.WriteByte(0); canonical.Write(class.Content); canonical.WriteByte(0); prior = class.ClassPath
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	return result.Ok[string, JavaFailure](hex.EncodeToString(digest[:]))
}

func sameJavaSymbol(left JavaSymbol, right JavaSymbol) bool {
	if left.Kind != right.Kind || left.Class != right.Class || left.Name != right.Name || left.Descriptor != right.Descriptor || left.GenericSignature != right.GenericSignature || left.MetadataDigest != right.MetadataDigest || left.Visibility != right.Visibility || left.Static != right.Static || left.Final != right.Final || left.Synthetic != right.Synthetic || left.Bridge != right.Bridge { return false }
	if len(left.Exceptions) != len(right.Exceptions) { return false }
	for index := range left.Exceptions { if left.Exceptions[index] != right.Exceptions[index] { return false } }
	return true
}

func cloneJavaSymbols(symbols []JavaSymbol) []JavaSymbol {
	cloned := append([]JavaSymbol{}, symbols...)
	for index := range cloned { cloned[index].Exceptions = append([]string{}, cloned[index].Exceptions...) }
	return cloned
}

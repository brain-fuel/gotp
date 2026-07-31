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
	NativeABIInventorySchema = "gotp.otp-native-abi/v1"
	PinnedNativeABIProfile = "darwin-arm64-lp64"
	PinnedNativeABICompiler = "Apple clang version 21.0.0 (clang-2100.1.1.101)"
	PinnedLinuxAMD64ABIProfile = "linux-amd64-lp64"
	PinnedLinuxARM64ABIProfile = "linux-arm64-lp64"
	PinnedWindowsAMD64ABIProfile = "windows-amd64-llp64"
	PinnedZigABICompiler = "zig 0.16.0"
	PinnedNativeABISourceCount = 8
	PinnedNativeABISymbolCount = 866
	PinnedLinuxAMD64ABISymbolCount = 855
	PinnedLinuxARM64ABISymbolCount = 855
	PinnedWindowsAMD64ABISymbolCount = 959
	PinnedNativeABISourceDigest = "3084a03e4b4871af3c3ab1db258d6bf7706d53d19d3f8371e50a94c501e43dae"
)

type NativeABIProfile enum {
	DarwinARM64ABI()
	LinuxAMD64ABI()
	LinuxARM64ABI()
	WindowsAMD64ABI()
}

type OTPNativeABISource struct {
	SourcePath string
	Content []byte
}

type OTPNativeABIInventory struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	Profile string `json:"profile"`
	Compiler string `json:"compiler"`
	SourceDigest string `json:"source_digest"`
	SourceCount int `json:"source_count"`
	Symbols []NativeABISymbol `json:"symbols"`
}

type NativeABIFailure enum {
	NativeABIJSONRejected(Cause string)
	NativeABIASTRejected(Header string, Cause string)
	NativeABIInventoryRejected(Detail string)
}

func (failure NativeABIFailure) Error() string {
	match failure {
	case NativeABIJSONRejected(cause): return "gotp/compat: native ABI JSON rejected: " + cause
	case NativeABIASTRejected(header, cause): return "gotp/compat: native ABI AST rejected for " + header + ": " + cause
	case NativeABIInventoryRejected(detail): return "gotp/compat: native ABI inventory rejected: " + detail
	}
}

// assayxport:unit gotp.compat.otp-native-abi
func BuildOTPNativeABIInventory(profile string, compiler string, sources []OTPNativeABISource, units []ClangASTUnit) result.Result[OTPNativeABIInventory, NativeABIFailure] {
	orderedSources := append([]OTPNativeABISource{}, sources...)
	sort.Slice(orderedSources, func(left, right int) bool { return orderedSources[left].SourcePath < orderedSources[right].SourcePath })
	match digestNativeABISources(orderedSources) {
	case result.Err(failure): return result.Err[OTPNativeABIInventory, NativeABIFailure](failure)
	case result.Ok(sourceDigest):
		symbols := map[string]NativeABISymbol{}
		for _, unit := range units {
			match NormalizeClangAST(profile, unit) {
			case result.Err(failure): return result.Err[OTPNativeABIInventory, NativeABIFailure](failure)
			case result.Ok(found):
				for _, symbol := range found {
					id := InventoryNativeABISymbolID(symbol)
					if prior, present := symbols[id]; present {
						if !sameNativeABISymbol(prior, symbol) { return result.Err[OTPNativeABIInventory, NativeABIFailure](NativeABIInventoryRejected("conflicting symbol " + id)) }
						continue
					}
					symbols[id] = symbol
				}
			}
		}
		inventory := OTPNativeABIInventory{Schema: NativeABIInventorySchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit, Profile: profile, Compiler: compiler, SourceDigest: sourceDigest, SourceCount: len(orderedSources)}
		for _, symbol := range symbols { inventory.Symbols = append(inventory.Symbols, symbol) }
		sort.Slice(inventory.Symbols, func(left, right int) bool { return InventoryNativeABISymbolID(inventory.Symbols[left]) < InventoryNativeABISymbolID(inventory.Symbols[right]) })
		match ValidateOTPNativeABIInventory(inventory) {
		case result.Err(failure): return result.Err[OTPNativeABIInventory, NativeABIFailure](failure)
		case result.Ok(_): return result.Ok[OTPNativeABIInventory, NativeABIFailure](inventory)
		}
	}
}

func ParseOTPNativeABIInventory(data []byte) result.Result[OTPNativeABIInventory, NativeABIFailure] {
	var inventory OTPNativeABIInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause): return result.Err[OTPNativeABIInventory, NativeABIFailure](NativeABIJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPNativeABIInventory(inventory) {
	case result.Err(failure): return result.Err[OTPNativeABIInventory, NativeABIFailure](failure)
	case result.Ok(_):
		inventory.Symbols = append([]NativeABISymbol{}, inventory.Symbols...)
		return result.Ok[OTPNativeABIInventory, NativeABIFailure](inventory)
	}
}

func ValidateOTPNativeABIInventory(inventory OTPNativeABIInventory) result.Result[bool, NativeABIFailure] {
	if inventory.Schema != NativeABIInventorySchema || inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("schema or upstream pin differs")) }
	var profile NativeABIProfile
	match nativeABIProfile(inventory.Profile) {
	case option.None: return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("unknown profile: " + inventory.Profile))
	case option.Some(value): profile = value
	}
	if inventory.Compiler != nativeABICompiler(profile) { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("compiler differs: " + inventory.Compiler)) }
	if inventory.SourceDigest != PinnedNativeABISourceDigest { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("source digest differs: " + inventory.SourceDigest)) }
	if inventory.SourceCount != PinnedNativeABISourceCount { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected(fmt.Sprintf("source count %d; want %d", inventory.SourceCount, PinnedNativeABISourceCount))) }
	expectedCount := nativeABISymbolCount(profile)
	if len(inventory.Symbols) != expectedCount { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected(fmt.Sprintf("symbol count %d; want %d", len(inventory.Symbols), expectedCount))) }
	prior := ""
	for index, symbol := range inventory.Symbols {
		if symbol.Profile != inventory.Profile || symbol.Surface == "" || symbol.Header == "" || symbol.Name == "" { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("empty or mismatched symbol identity")) }
		match nativeABISymbolKind(symbol.Kind) {
		case option.None: return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("unknown symbol kind " + symbol.Kind))
		case option.Some(_):
		}
		id := InventoryNativeABISymbolID(symbol)
		if index > 0 && id <= prior { return result.Err[bool, NativeABIFailure](NativeABIInventoryRejected("symbols are not strictly sorted")) }
		prior = id
	}
	return result.Ok[bool, NativeABIFailure](true)
}

func InventoryNativeABISymbolID(symbol NativeABISymbol) string {
	identity := symbol.Container + "\x00" + symbol.Name
	return "otp.native-abi." + symbol.Profile + "." + symbol.Surface + "." + symbol.Kind + "." + hex.EncodeToString([]byte(identity))
}

func MissingNativeABICoverage(inventory OTPNativeABIInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, symbol := range inventory.Symbols {
		id := InventoryNativeABISymbolID(symbol)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func digestNativeABISources(sources []OTPNativeABISource) result.Result[string, NativeABIFailure] {
	var canonical strings.Builder
	prior := ""
	for index, source := range sources {
		if source.SourcePath == "" || (index > 0 && source.SourcePath <= prior) { return result.Err[string, NativeABIFailure](NativeABIInventoryRejected("empty or duplicate ABI source path")) }
		canonical.WriteString(source.SourcePath); canonical.WriteByte(0); canonical.Write(source.Content); canonical.WriteByte(0); prior = source.SourcePath
	}
	digest := sha256.Sum256([]byte(canonical.String()))
	return result.Ok[string, NativeABIFailure](hex.EncodeToString(digest[:]))
}

func sameNativeABISymbol(left NativeABISymbol, right NativeABISymbol) bool {
	return left.Profile == right.Profile && left.Surface == right.Surface && left.Kind == right.Kind && left.Container == right.Container && left.Name == right.Name && left.Signature == right.Signature && left.Value == right.Value
}

func nativeABIProfile(name string) option.Option[NativeABIProfile] {
	switch name {
	case PinnedNativeABIProfile: return option.Some[NativeABIProfile](DarwinARM64ABI())
	case PinnedLinuxAMD64ABIProfile: return option.Some[NativeABIProfile](LinuxAMD64ABI())
	case PinnedLinuxARM64ABIProfile: return option.Some[NativeABIProfile](LinuxARM64ABI())
	case PinnedWindowsAMD64ABIProfile: return option.Some[NativeABIProfile](WindowsAMD64ABI())
	default: return option.None[NativeABIProfile]
	}
}

func nativeABICompiler(profile NativeABIProfile) string {
	match profile {
	case DarwinARM64ABI: return PinnedNativeABICompiler
	case LinuxAMD64ABI: return PinnedZigABICompiler
	case LinuxARM64ABI: return PinnedZigABICompiler
	case WindowsAMD64ABI: return PinnedZigABICompiler
	}
}

func nativeABISymbolCount(profile NativeABIProfile) int {
	match profile {
	case DarwinARM64ABI: return PinnedNativeABISymbolCount
	case LinuxAMD64ABI: return PinnedLinuxAMD64ABISymbolCount
	case LinuxARM64ABI: return PinnedLinuxARM64ABISymbolCount
	case WindowsAMD64ABI: return PinnedWindowsAMD64ABISymbolCount
	}
}

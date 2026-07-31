package compat

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const (
	InventorySchema = "gotp.otp-inventory/v2"
	PinnedApplicationCount = 36
	PinnedModuleCount = 1268
	PinnedSourceUnitCount = 981
)

type OTPApplication struct {
	Name     string `json:"name"`
	Manifest string `json:"manifest"`
}

type OTPModule struct {
	Application string `json:"application"`
	Module      string `json:"module"`
	SourcePath  string `json:"source_path"`
}

type SourceKind enum {
	NativeSource()
	JavaSource()
	GeneratorSource()
	PublicHeaderSource()
}

type OTPSourceUnit struct {
	Kind        string `json:"kind"`
	Application string `json:"application"`
	SourcePath  string `json:"source_path"`
}

type OTPInventory struct {
	Schema         string           `json:"schema"`
	UpstreamTag    string           `json:"upstream_tag"`
	UpstreamCommit string           `json:"upstream_commit"`
	Applications   []OTPApplication `json:"applications"`
	Modules        []OTPModule      `json:"modules"`
	SourceUnits    []OTPSourceUnit  `json:"source_units"`
}

type InventoryFailure enum {
	InventoryJSONRejected(Cause string)
	InventoryProvenanceRejected(Detail string)
	InventoryOrderingRejected(Detail string)
	InventoryMembershipRejected(Detail string)
	InventoryCountRejected(Kind string, Found int, Expected int)
}

func (failure InventoryFailure) Error() string {
	match failure {
	case InventoryJSONRejected(cause): return "gotp/compat: inventory JSON rejected: " + cause
	case InventoryProvenanceRejected(detail): return "gotp/compat: inventory provenance rejected: " + detail
	case InventoryOrderingRejected(detail): return "gotp/compat: inventory ordering rejected: " + detail
	case InventoryMembershipRejected(detail): return "gotp/compat: inventory membership rejected: " + detail
	case InventoryCountRejected(kind, found, expected):
		return fmt.Sprintf("gotp/compat: inventory %s count %d; want %d", kind, found, expected)
	}
}

// assayxport:unit gotp.compat.otp-upstream-inventory
func ParseOTPInventory(data []byte) result.Result[OTPInventory, InventoryFailure] {
	var inventory OTPInventory
	match result.Of(true, json.Unmarshal(data, &inventory)) {
	case result.Err(cause):
		return result.Err[OTPInventory, InventoryFailure](InventoryJSONRejected(cause.Error()))
	case result.Ok(_):
	}
	match ValidateOTPInventory(inventory) {
	case result.Err(failure): return result.Err[OTPInventory, InventoryFailure](failure)
	case result.Ok(_): return result.Ok[OTPInventory, InventoryFailure](cloneInventory(inventory))
	}
}

func ValidateOTPInventory(inventory OTPInventory) result.Result[bool, InventoryFailure] {
	if inventory.Schema != InventorySchema {
		return result.Err[bool, InventoryFailure](InventoryProvenanceRejected("schema " + inventory.Schema))
	}
	if inventory.UpstreamTag != OTPPinnedTag || inventory.UpstreamCommit != OTPPinnedCommit {
		return result.Err[bool, InventoryFailure](InventoryProvenanceRejected("upstream pin differs from compatibility ledger"))
	}
	if len(inventory.Applications) != PinnedApplicationCount {
		return result.Err[bool, InventoryFailure](InventoryCountRejected("application", len(inventory.Applications), PinnedApplicationCount))
	}
	if len(inventory.Modules) != PinnedModuleCount {
		return result.Err[bool, InventoryFailure](InventoryCountRejected("module", len(inventory.Modules), PinnedModuleCount))
	}
	if len(inventory.SourceUnits) != PinnedSourceUnitCount {
		return result.Err[bool, InventoryFailure](InventoryCountRejected("source unit", len(inventory.SourceUnits), PinnedSourceUnitCount))
	}
	applications := make(map[string]struct{}, len(inventory.Applications))
	priorApplication := ""
	for index, application := range inventory.Applications {
		if application.Name == "" || application.Manifest == "" {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("empty application identity"))
		}
		if index > 0 && application.Name <= priorApplication {
			return result.Err[bool, InventoryFailure](InventoryOrderingRejected("applications are not strictly sorted"))
		}
		applications[application.Name] = struct{}{}
		priorApplication = application.Name
	}
	priorModule := ""
	for index, module := range inventory.Modules {
		identity := module.Application + "." + module.Module
		if module.Application == "" || module.Module == "" || module.SourcePath == "" {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("empty module identity"))
		}
		if _, present := applications[module.Application]; !present {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("module references unknown application " + module.Application))
		}
		if index > 0 && identity <= priorModule {
			return result.Err[bool, InventoryFailure](InventoryOrderingRejected("modules are not strictly sorted"))
		}
		priorModule = identity
	}
	priorUnit := ""
	unitIDs := make(map[string]struct{}, len(inventory.SourceUnits))
	for index, unit := range inventory.SourceUnits {
		identity := unit.Kind + ":" + unit.SourcePath
		if unit.Application == "" || unit.SourcePath == "" {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("empty source-unit identity"))
		}
		match sourceKind(unit.Kind) {
		case option.None:
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("unknown source kind " + unit.Kind))
		case option.Some(_):
		}
		if _, present := applications[unit.Application]; !present {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("source unit references unknown application " + unit.Application))
		}
		if index > 0 && identity <= priorUnit {
			return result.Err[bool, InventoryFailure](InventoryOrderingRejected("source units are not strictly sorted"))
		}
		id := InventorySourceID(unit.Kind, unit.SourcePath)
		if _, duplicate := unitIDs[id]; duplicate {
			return result.Err[bool, InventoryFailure](InventoryMembershipRejected("normalized source ID collision " + id))
		}
		unitIDs[id] = struct{}{}
		priorUnit = identity
	}
	return result.Ok[bool, InventoryFailure](true)
}

func MissingInventoryCoverage(inventory OTPInventory, ledger Ledger) []string {
	covered := make(map[string]struct{}, len(ledger.Items))
	for _, item := range ledger.Items { covered[item.ID] = struct{}{} }
	missing := []string{}
	for _, application := range inventory.Applications {
		id := InventoryApplicationID(application.Name)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	for _, module := range inventory.Modules {
		id := InventoryModuleID(module.Application, module.Module)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	for _, unit := range inventory.SourceUnits {
		id := InventorySourceID(unit.Kind, unit.SourcePath)
		if _, present := covered[id]; !present { missing = append(missing, id) }
	}
	return missing
}

func InventoryApplicationID(name string) string {
	return "otp.application." + strings.ToLower(name)
}

func InventoryModuleID(application string, module string) string {
	return "otp.module." + strings.ToLower(application) + "." + strings.ToLower(module)
}

func InventorySourceID(kind string, path string) string {
	return "otp.source." + strings.ToLower(kind) + "." + strings.ToLower(path)
}

func BuildOTPInventory(paths []string) result.Result[OTPInventory, InventoryFailure] {
	ordered := append([]string{}, paths...)
	sort.Strings(ordered)
	applications := make(map[string]string)
	modules := make(map[string]OTPModule)
	units := make(map[string]OTPSourceUnit)
	for _, path := range ordered {
		if path == "erts/preloaded/src/erts.app.src" {
			applications["erts"] = path
		}
		if strings.HasPrefix(path, "lib/") && strings.HasSuffix(path, ".app.src") &&
			!strings.Contains(path, "/test/") && !strings.Contains(path, "/examples/") {
			parts := strings.Split(path, "/")
			if len(parts) >= 3 {
				if _, present := applications[parts[1]]; !present { applications[parts[1]] = path }
			}
		}
		if strings.HasPrefix(path, "lib/") && strings.Contains(path, "/src/") && strings.HasSuffix(path, ".erl") {
			parts := strings.Split(path, "/")
			if len(parts) >= 4 && parts[2] == "src" {
				name := strings.TrimSuffix(parts[len(parts)-1], ".erl")
				identity := parts[1] + "." + name
				if _, present := modules[identity]; !present {
					modules[identity] = OTPModule{Application: parts[1], Module: name, SourcePath: path}
				}
			}
		}
		if strings.HasPrefix(path, "erts/preloaded/src/") && strings.HasSuffix(path, ".erl") {
			parts := strings.Split(path, "/")
			name := strings.TrimSuffix(parts[len(parts)-1], ".erl")
			modules["erts."+name] = OTPModule{Application: "erts", Module: name, SourcePath: path}
		}
		match classifySourceUnit(path) {
		case option.None:
		case option.Some(unit): units[unit.Kind+":"+unit.SourcePath] = unit
		}
	}
	inventory := OTPInventory{
		Schema: InventorySchema, UpstreamTag: OTPPinnedTag, UpstreamCommit: OTPPinnedCommit,
	}
	for name, manifest := range applications {
		inventory.Applications = append(inventory.Applications, OTPApplication{Name: name, Manifest: manifest})
	}
	sort.Slice(inventory.Applications, func(left, right int) bool {
		return inventory.Applications[left].Name < inventory.Applications[right].Name
	})
	for _, module := range modules { inventory.Modules = append(inventory.Modules, module) }
	sort.Slice(inventory.Modules, func(left, right int) bool {
		leftID := inventory.Modules[left].Application + "." + inventory.Modules[left].Module
		rightID := inventory.Modules[right].Application + "." + inventory.Modules[right].Module
		return leftID < rightID
	})
	for _, unit := range units { inventory.SourceUnits = append(inventory.SourceUnits, unit) }
	sort.Slice(inventory.SourceUnits, func(left, right int) bool {
		leftID := inventory.SourceUnits[left].Kind + ":" + inventory.SourceUnits[left].SourcePath
		rightID := inventory.SourceUnits[right].Kind + ":" + inventory.SourceUnits[right].SourcePath
		return leftID < rightID
	})
	match ValidateOTPInventory(inventory) {
	case result.Err(failure): return result.Err[OTPInventory, InventoryFailure](failure)
	case result.Ok(_): return result.Ok[OTPInventory, InventoryFailure](inventory)
	}
}

func cloneInventory(inventory OTPInventory) OTPInventory {
	return OTPInventory{
		Schema: inventory.Schema,
		UpstreamTag: inventory.UpstreamTag,
		UpstreamCommit: inventory.UpstreamCommit,
		Applications: append([]OTPApplication{}, inventory.Applications...),
		Modules: append([]OTPModule{}, inventory.Modules...),
		SourceUnits: append([]OTPSourceUnit{}, inventory.SourceUnits...),
	}
}

func sourceKind(kind string) option.Option[SourceKind] {
	switch kind {
	case "native": return option.Some[SourceKind](NativeSource())
	case "java": return option.Some[SourceKind](JavaSource())
	case "generator": return option.Some[SourceKind](GeneratorSource())
	case "header": return option.Some[SourceKind](PublicHeaderSource())
	default: return option.None[SourceKind]
	}
}

func classifySourceUnit(path string) option.Option[OTPSourceUnit] {
	if strings.Contains(path, "/test/") || strings.Contains(path, "/tests/") || strings.Contains(path, "/example/") || strings.Contains(path, "/examples/") {
		return option.None[OTPSourceUnit]
	}
	if strings.HasPrefix(path, "erts/") && nativePath(path) {
		return option.Some[OTPSourceUnit](OTPSourceUnit{Kind: "native", Application: "erts", SourcePath: path})
	}
	if strings.HasPrefix(path, "lib/") {
		parts := strings.Split(path, "/")
		if len(parts) < 3 { return option.None[OTPSourceUnit] }
		application := parts[1]
		if len(parts) >= 4 && parts[2] == "c_src" && nativePath(path) {
			return option.Some[OTPSourceUnit](OTPSourceUnit{Kind: "native", Application: application, SourcePath: path})
		}
		if application == "jinterface" && parts[2] == "java_src" && strings.HasSuffix(path, ".java") {
			return option.Some[OTPSourceUnit](OTPSourceUnit{Kind: "java", Application: application, SourcePath: path})
		}
		if parts[2] == "src" && generatorPath(path) {
			return option.Some[OTPSourceUnit](OTPSourceUnit{Kind: "generator", Application: application, SourcePath: path})
		}
		if parts[2] == "include" && strings.HasSuffix(path, ".hrl") {
			return option.Some[OTPSourceUnit](OTPSourceUnit{Kind: "header", Application: application, SourcePath: path})
		}
	}
	return option.None[OTPSourceUnit]
}

func nativePath(path string) bool {
	for _, suffix := range []string{".c", ".h", ".cc", ".cpp", ".S", ".s"} {
		if strings.HasSuffix(path, suffix) { return true }
	}
	return false
}

func generatorPath(path string) bool {
	for _, suffix := range []string{".yrl", ".xrl", ".asn1"} {
		if strings.HasSuffix(path, suffix) { return true }
	}
	return false
}

package erts

import (
	"encoding/base64"
	"os"
	"strconv"
	"strings"
	"testing"

	"goforge.dev/gotp/beam"
	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

func pinnedGenServerModule(t *testing.T) *LoadedModule {
	var read beam.ReadFileCapability = beam.OperatingSystemFiles{}
	match LoadModuleFile(read, "../beam/testdata/otp-29.0.4/gen_server.beam", ModuleLoaderConfig{}) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(module): return module
	}
	panic("unreachable")
}

// assayxport:law gotp.erts.otp29-gen_server-differential
func TestPinnedOTPGenServerDifferentialCorpus(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-gen_server-pure.corpus")
	if cause != nil { t.Fatal(cause) }
	module := pinnedGenServerModule(t)
	var modules *ModuleSet
	match NewModuleSet([]*LoadedModule{module, pinnedListsModule(t), pinnedMapsModule(t), pinnedStdlibDependency(t, "sets"), pinnedStdlibDependency(t, "gen"), pinnedStdlibDependency(t, "proc_lib"), pinnedStdlibDependency(t, "sys"), pinnedStdlibDependency(t, "global"), pinnedStdlibDependency(t, "code"), pinnedStdlibDependency(t, "io"), pinnedStdlibDependency(t, "io_lib"), pinnedStdlibDependency(t, "logger"), pinnedStdlibDependency(t, "error_logger")}) { case result.Err(failure): t.Fatal(failure); case result.Ok(found): modules = found }
	registry := otpRegistryForInvocation(t)
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		if strings.HasPrefix(line, "#") { continue }
		fields := strings.Split(line, "|")
		if len(fields) != 5 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
		arity, cause := strconv.Atoi(fields[2])
		if cause != nil { t.Fatal(cause) }
		argumentsTerm := decodeGenServerCorpusTerm(t, fields[3])
		var arguments []term.Term
		match argumentsTerm { case term.ProperListTerm(found): arguments = found; case _: t.Fatalf("%s/%d arguments differ", fields[1], arity) }
		if len(arguments) != arity { t.Fatalf("%s/%d argument count differs", fields[1], arity) }
		expected := decodeGenServerCorpusTerm(t, fields[4])
		process := invokeGenServerCorpusCase(t, modules, registry, fields[1], arguments)
		assertGenServerCorpusOutcome(t, fields[1], arity, process.State(), expected)
	}
}

func invokeGenServerCorpusCase(t *testing.T, modules *ModuleSet, registry *CallRegistry, function string, arguments []term.Term) *VMProcess {
	t.Helper()
	var process *VMProcess
	match modules.Invoke("gen_server", function, arguments, clock.Real{}, registry) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(created): process = created
	}
	runGenServerCorpusProcess(t, process)
	return process
}

func runGenServerCorpusProcess(t *testing.T, process *VMProcess) {
	t.Helper()
	runtime := kernel.New(kernel.KernelConfig{})
	match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	runtime.Run(10_000)
}

func assertGenServerCorpusOutcome(t *testing.T, function string, arity int, actual VMProcessState, expected term.Term) {
	t.Helper()
	match expected {
	case term.TupleTerm(parts):
		if len(parts) < 2 { t.Fatalf("%s/%d expected outcome differs", function, arity) }
		match parts[0] {
		case term.AtomTerm(tag):
			switch tag {
			case "ok":
				match actual {
				case VMProcessCompleted(value, _, _): if !gen_serverCorpusValuesEqual(function, arity, value, parts[1]) { t.Fatalf("%s/%d = %v, want %v", function, arity, value, parts[1]) }
				case _: t.Fatalf("%s/%d state = %T: %v", function, arity, actual, actual)
				}
			case "raised":
				if len(parts) != 3 { t.Fatalf("%s/%d raised outcome differs", function, arity) }
				match actual {
				case VMProcessRaised(class, reason, _, _): if !term.Equal(class, parts[1]) || !term.Equal(reason, parts[2]) { t.Fatalf("%s/%d raised %v:%v, want %v:%v", function, arity, class, reason, parts[1], parts[2]) }
				case _: t.Fatalf("%s/%d state = %T: %v", function, arity, actual, actual)
				}
			default: t.Fatalf("%s/%d outcome tag = %s", function, arity, tag)
			}
		case _: t.Fatalf("%s/%d outcome tag differs", function, arity)
		}
	case _: t.Fatalf("%s/%d expected outcome is not a tuple", function, arity)
	}
}

func gen_serverCorpusValuesEqual(function string, arity int, actual term.Term, expected term.Term) bool {
	if function == "get_keys" { return unorderedGenServerCorpusTermsEqual(actual, expected) }
	if function != "module_info" { return term.Equal(actual, expected) }
	if arity == 1 { return unorderedGenServerCorpusTermsEqual(actual, expected) }
	match actual {
	case term.ProperListTerm(actualFields):
		match expected {
		case term.ProperListTerm(expectedFields):
			if len(actualFields) != len(expectedFields) { return false }
			matched := make([]bool, len(expectedFields))
			for _, actualField := range actualFields {
				found := false
				for index, expectedField := range expectedFields {
					if !matched[index] && gen_serverCorpusModuleInfoFieldEqual(actualField, expectedField) { matched[index] = true; found = true; break }
				}
				if !found { return false }
			}
			return true
		case _: return false
		}
	case _: return false
	}
}

func gen_serverCorpusModuleInfoFieldEqual(actual term.Term, expected term.Term) bool {
	match actual {
	case term.TupleTerm(actualParts):
		match expected {
		case term.TupleTerm(expectedParts):
			if len(actualParts) != 2 || len(expectedParts) != 2 || !term.Equal(actualParts[0], expectedParts[0]) { return false }
			if term.Equal(actualParts[0], term.MustAtom("exports")) { return unorderedGenServerCorpusTermsEqual(actualParts[1], expectedParts[1]) }
			return term.Equal(actualParts[1], expectedParts[1])
		case _: return false
		}
	case _: return false
	}
}

func unorderedGenServerCorpusTermsEqual(actual term.Term, expected term.Term) bool {
	match actual {
	case term.ProperListTerm(actualValues):
		match expected {
		case term.ProperListTerm(expectedValues):
			if len(actualValues) != len(expectedValues) { return false }
			matched := make([]bool, len(expectedValues))
			for _, actualValue := range actualValues {
				found := false
				for index, expectedValue := range expectedValues {
					if !matched[index] && term.Equal(actualValue, expectedValue) { matched[index] = true; found = true; break }
				}
				if !found { return false }
			}
			return true
		case _: return false
		}
	case _: return false
	}
}

func decodeGenServerCorpusTerm(t *testing.T, encoded string) term.Term {
	t.Helper()
	raw, cause := base64.StdEncoding.DecodeString(encoded)
	if cause != nil { t.Fatal(cause) }
	var nodes *etf.StaticNodeTable
	match etf.NewStaticNodeTable(map[uint32]string{1: "nonode@nohost"}) { case result.Err(failure): t.Fatal(failure.Error()); case result.Ok(found): nodes = found }
	codec := etf.CanonicalCodec{Nodes: nodes}
	match codec.Decode(raw) {
	case result.Err(failure): t.Fatal(failure.Error()); return term.InvalidValue()
	case result.Ok(value): return value
	}
}

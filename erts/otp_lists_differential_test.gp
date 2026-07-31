package erts

import (
	"encoding/base64"
	"os"
	"strconv"
	"strings"
	"testing"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.erts.otp29-lists-differential
// assayxport:law gotp.erts.otp29-lists-differential
func TestPinnedOTPListsDifferentialCorpus(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-lists.corpus")
	if cause != nil { t.Fatal(cause) }
	module := pinnedListsModule(t)
	registry := otpRegistryForInvocation(t)
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		if strings.HasPrefix(line, "#") { continue }
		fields := strings.Split(line, "|")
		if len(fields) != 5 || fields[0] != "case" { t.Fatalf("line %d is malformed", lineNumber+1) }
		arity, cause := strconv.Atoi(fields[2])
		if cause != nil { t.Fatal(cause) }
		argumentsTerm := decodeListsCorpusTerm(t, fields[3])
		var arguments []term.Term
		match argumentsTerm { case term.ProperListTerm(found): arguments = found; case _: t.Fatalf("%s/%d arguments differ", fields[1], arity) }
		if len(arguments) != arity { t.Fatalf("%s/%d argument count differs", fields[1], arity) }
		expected := decodeListsCorpusTerm(t, fields[4])
		process := invokeListsCorpusCase(t, module, registry, fields[1], arguments)
		assertListsCorpusOutcome(t, fields[1], arity, process.State(), expected)
	}
}

// assayxport:law gotp.erts.otp29-lists-export-coverage
func TestPinnedOTPListsCorpusCoversEveryExport(t *testing.T) {
	covered := map[string]bool{}
	for _, corpus := range []string{"testdata/otp-29.0.4-lists.corpus", "testdata/otp-29.0.4-lists-callbacks.corpus"} {
		payload, cause := os.ReadFile(corpus)
		if cause != nil { t.Fatal(cause) }
		callback := strings.Contains(corpus, "callbacks")
		for _, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
			if strings.HasPrefix(line, "#") { continue }
			fields := strings.Split(line, "|")
			arityField := 2
			if callback { arityField = 3 }
			covered[fields[1]+"/"+fields[arityField]] = true
		}
	}
	image := pinnedListsModule(t).image()
	for target := range image.Exports {
		identity := target.Function + "/" + strconv.Itoa(int(target.Arity))
		if !covered[identity] { t.Errorf("pinned lists export lacks differential case: %s", identity) }
	}
}

func invokeListsCorpusCase(t *testing.T, module *LoadedModule, registry *CallRegistry, function string, arguments []term.Term) *VMProcess {
	t.Helper()
	var process *VMProcess
	match module.Invoke(function, arguments, clock.Real{}, registry) {
	case result.Err(failure): t.Fatal(failure)
	case result.Ok(created): process = created
	}
	runListsCorpusProcess(t, process)
	return process
}

func runListsCorpusProcess(t *testing.T, process *VMProcess) {
	t.Helper()
	runtime := kernel.New(kernel.KernelConfig{})
	match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) { case result.Err(failure): t.Fatal(failure); case result.Ok(_): }
	runtime.Run(10_000)
}

func assertListsCorpusOutcome(t *testing.T, function string, arity int, actual VMProcessState, expected term.Term) {
	t.Helper()
	match expected {
	case term.TupleTerm(parts):
		if len(parts) < 2 { t.Fatalf("%s/%d expected outcome differs", function, arity) }
		match parts[0] {
		case term.AtomTerm(tag):
			switch tag {
			case "ok":
				match actual {
				case VMProcessCompleted(value, _, _): if !listsCorpusValuesEqual(function, arity, value, parts[1]) { t.Fatalf("%s/%d = %v, want %v", function, arity, value, parts[1]) }
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

func listsCorpusValuesEqual(function string, arity int, actual term.Term, expected term.Term) bool {
	if function != "module_info" { return term.Equal(actual, expected) }
	if arity == 1 { return unorderedListsCorpusTermsEqual(actual, expected) }
	match actual {
	case term.ProperListTerm(actualFields):
		match expected {
		case term.ProperListTerm(expectedFields):
			if len(actualFields) != len(expectedFields) { return false }
			matched := make([]bool, len(expectedFields))
			for _, actualField := range actualFields {
				found := false
				for index, expectedField := range expectedFields {
					if !matched[index] && listsCorpusModuleInfoFieldEqual(actualField, expectedField) { matched[index] = true; found = true; break }
				}
				if !found { return false }
			}
			return true
		case _: return false
		}
	case _: return false
	}
}

func listsCorpusModuleInfoFieldEqual(actual term.Term, expected term.Term) bool {
	match actual {
	case term.TupleTerm(actualParts):
		match expected {
		case term.TupleTerm(expectedParts):
			if len(actualParts) != 2 || len(expectedParts) != 2 || !term.Equal(actualParts[0], expectedParts[0]) { return false }
			if term.Equal(actualParts[0], term.MustAtom("exports")) { return unorderedListsCorpusTermsEqual(actualParts[1], expectedParts[1]) }
			return term.Equal(actualParts[1], expectedParts[1])
		case _: return false
		}
	case _: return false
	}
}

func unorderedListsCorpusTermsEqual(actual term.Term, expected term.Term) bool {
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

func decodeListsCorpusTerm(t *testing.T, encoded string) term.Term {
	t.Helper()
	raw, cause := base64.StdEncoding.DecodeString(encoded)
	if cause != nil { t.Fatal(cause) }
	codec := etf.CanonicalCodec{}
	match codec.Decode(raw) {
	case result.Err(failure): t.Fatal(failure.Error()); return term.InvalidValue()
	case result.Ok(value): return value
	}
}

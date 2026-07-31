package release

import (
	"encoding/base64"
	"os"
	"strings"
	"testing"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
)

// assayxport:law gotp.otp.systools-relup-otp29-differential
func TestSystoolsRelupMatchesPinnedOTP29Corpus(t *testing.T) {
	payload, cause := os.ReadFile("testdata/otp-29.0.4-systools-relup.corpus")
	if cause != nil { t.Fatal(cause) }
	for lineNumber, line := range strings.Split(strings.TrimSpace(string(payload)), "\n") {
		if strings.HasPrefix(line, "#") { continue }
		fields := strings.Split(line, "|")
		if len(fields) < 3 { t.Fatalf("line %d is malformed", lineNumber+1) }
		switch fields[0] {
		case "selector": compareSelectorCorpus(t, fields)
		case "diagnostic": compareDiagnosticCorpus(t, fields)
		default: t.Fatalf("line %d has unknown kind %q", lineNumber+1, fields[0])
		}
	}
}

func compareSelectorCorpus(t *testing.T, fields []string) {
	if len(fields) != 5 { t.Fatalf("selector %q has %d fields", fields[1], len(fields)) }
	base := decodeCorpusTerm(t, fields[2])
	entriesTerm := decodeCorpusTerm(t, fields[3])
	expected := decodeCorpusTerm(t, fields[4])
	var version string
	match appupText(base) { case option.None: t.Fatalf("selector %q has invalid base", fields[1]); case option.Some(found): version = found }
	var entries []term.Term
	match entriesTerm { case term.ProperListTerm(found): entries = found; case _: t.Fatalf("selector %q entries are not a list", fields[1]) }
	actual := SearchAppupVersion(version, entries)
	match expected {
	case term.TupleTerm(parts):
		if len(parts) != 2 { t.Fatalf("selector %q expected tuple differs", fields[1]) }
		match parts[0] {
		case term.AtomTerm(name):
			switch name {
			case "ok":
				match actual {
				case result.Err(failure): t.Fatalf("selector %q: %s", fields[1], failure.Error())
				case result.Ok(script): if !term.Equal(term.List(script...), parts[1]) { t.Fatalf("selector %q script differs", fields[1]) }
				}
			case "error":
				match actual { case result.Err(InvalidVersionPattern): case _: t.Fatalf("selector %q did not reject invalid regex", fields[1]) }
			default: t.Fatalf("selector %q expected tuple tag differs", fields[1])
			}
		case _: t.Fatalf("selector %q expected tuple tag differs", fields[1])
		}
	case term.AtomTerm(name):
		if name != "error" { t.Fatalf("selector %q expected atom differs", fields[1]) }
		match actual { case result.Err(MissingVersionScript): case _: t.Fatalf("selector %q unexpectedly matched", fields[1]) }
	case _: t.Fatalf("selector %q expected result differs", fields[1])
	}
}

func compareDiagnosticCorpus(t *testing.T, fields []string) {
	if len(fields) != 3 { t.Fatalf("diagnostic %q has %d fields", fields[1], len(fields)) }
	want, cause := base64.StdEncoding.DecodeString(fields[2])
	if cause != nil { t.Fatal(cause) }
	found := ""
	switch fields[1] {
	case "error-file-open": found = FormatRelupError(FileProblem("demo.rel", OpenFile()))
	case "error-warnings": found = FormatRelupError(WarningsTreatedAsErrors([]RelupWarning{ERTSVersionChanged(term.MustAtom("old"), term.MustAtom("new")), PreR15EmulatorUpgrade(), RawRelupWarning(term.Tuple(term.MustAtom("other"), term.Integer(3)))}))
	case "error-raw": found = FormatRelupError(RawRelupError(term.Tuple(term.MustAtom("odd"), term.Integer(3))))
	case "warning-erts": found = FormatRelupWarning(ERTSVersionChanged(term.MustAtom("old"), term.MustAtom("new")))
	case "warning-pre-r15": found = FormatRelupWarning(PreR15EmulatorUpgrade())
	case "warning-raw": found = FormatRelupWarning(RawRelupWarning(term.Tuple(term.MustAtom("other"), term.Integer(3))))
	default: t.Fatalf("unknown diagnostic %q", fields[1])
	}
	if found != string(want) { t.Fatalf("diagnostic %q = %q, want %q", fields[1], found, string(want)) }
}

func decodeCorpusTerm(t *testing.T, encoded string) term.Term {
	t.Helper()
	raw, cause := base64.StdEncoding.DecodeString(encoded)
	if cause != nil { t.Fatal(cause) }
	codec := etf.CanonicalCodec{}
	match codec.Decode(raw) {
	case result.Err(failure): t.Fatal(failure.Error()); return term.InvalidValue()
	case result.Ok(value): return value
	}
}

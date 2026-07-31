package release

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"

	"goforge.dev/gotp/term"
)

type FileOperation enum {
	OpenFile()
	ReadFile()
	ParseFile()
	CloseFile()
}

type RelupWarning enum {
	ERTSVersionChanged(From term.Term, To term.Term)
	PreR15EmulatorUpgrade()
	RawRelupWarning(Value term.Term)
}

type RelupError enum {
	FileProblem(File string, Operation FileOperation)
	NoRelup(File string, Application ApplicationSpec, Version string)
	MissingSASL(Release ReleaseSpec)
	WarningsTreatedAsErrors(Warnings []RelupWarning)
	RawRelupError(Value term.Term)
}

// assayxport:unit gotp.otp.systools-relup-diagnostics
func FormatRelupError(failure RelupError) string {
	match failure {
	case FileProblem(file, operation):
		return "Could not " + fileOperationText(operation) + " file " + file + "\n"
	case NoRelup(file, application, version):
		name := erlangAtomText(application.Name)
		return "No release upgrade script entry for " + name + "-" + application.Version +
			" to " + name + "-" + version + " in file " + file + "\n"
	case MissingSASL(release):
		return "No sasl application in release " + release.Name + ", " + release.Version + ". Can not be upgraded."
	case WarningsTreatedAsErrors(warnings):
		var text strings.Builder
		text.WriteString("Warnings being treated as errors:\n")
		for _, warning := range warnings { text.WriteString(formatRelupWarning("", warning)) }
		return text.String()
	case RawRelupError(value):
		return erlangTermText(value) + "\n"
	}
}

func FormatRelupWarning(warning RelupWarning) string {
	return formatRelupWarning("*WARNING* ", warning)
}

func formatRelupWarning(prefix string, warning RelupWarning) string {
	match warning {
	case ERTSVersionChanged(from, to):
		return prefix + "The ERTS version changed between " + erlangTermText(from) + " and " + erlangTermText(to) + "\n"
	case PreR15EmulatorUpgrade:
		return prefix + "Upgrade from an OTP version earlier than R15. New code should be compiled with the old emulator.\n"
	case RawRelupWarning(value):
		return prefix + erlangTermText(value) + "\n"
	}
}

func fileOperationText(operation FileOperation) string {
	match operation {
	case OpenFile: return "open"
	case ReadFile: return "read"
	case ParseFile: return "parse"
	case CloseFile: return "close"
	}
}

func erlangTermText(value term.Term) string {
	match value {
	case term.InvalidTerm: return "undefined"
	case term.IntegerTerm(integer): return integer.String()
	case term.FloatTerm(bits): return fmt.Sprintf("%.17g", math.Float64frombits(bits))
	case term.AtomTerm(name): return erlangAtomText(name)
	case term.BinaryTerm(raw): return "<<" + byteText(raw) + ">>"
	case term.TupleTerm(elements): return "{" + termSequenceText(elements) + "}"
	case term.ProperListTerm(elements): return "[" + termSequenceText(elements) + "]"
	case term.ImproperListTerm(elements, tail): return "[" + termSequenceText(elements) + "|" + erlangTermText(tail) + "]"
	case term.MapTerm(entries):
		parts := make([]string, len(entries))
		for index, entry := range entries { parts[index] = erlangTermText(entry.Key) + "=>" + erlangTermText(entry.Value) }
		return "#{" + strings.Join(parts, ",") + "}"
	case term.PIDTerm(pid): return fmt.Sprintf("<%d.%d.%d>", pid.Node, pid.Number, pid.Creation)
	case term.ReferenceTerm(reference): return fmt.Sprintf("#Ref<%d.%d.%v>", reference.Node, reference.Creation, reference.Words[:int(reference.Length)])
	case term.FunTerm(function): return "#Fun<" + erlangAtomText(function.Module) + "." + strconv.FormatUint(uint64(function.Index), 10) + ">"
	case term.PortTerm(port): return fmt.Sprintf("#Port<%d.%d>", port.Node, port.ID)
	}
}

func erlangAtomText(name string) string {
	valid := name != ""
	for index, character := range name {
		if index == 0 { valid = character >= 'a' && character <= 'z'; continue }
		valid = valid && (unicode.IsLetter(character) || unicode.IsDigit(character) || character == '_' || character == '@')
	}
	if valid { return name }
	return "'" + strings.ReplaceAll(strings.ReplaceAll(name, "\\", "\\\\"), "'", "\\'") + "'"
}

func termSequenceText(values []term.Term) string {
	parts := make([]string, len(values))
	for index, value := range values { parts[index] = erlangTermText(value) }
	return strings.Join(parts, ",")
}

func byteText(values []byte) string {
	parts := make([]string, len(values))
	for index, value := range values { parts[index] = strconv.Itoa(int(value)) }
	return strings.Join(parts, ",")
}

package release

import (
	"regexp"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type AppupDirection enum {
	UpgradeScripts()
	DowngradeScripts()
}

type VersionSelector enum {
	ExactVersion(Version string)
	VersionPattern(Pattern string)
}

type AppupEntry struct {
	Selector VersionSelector
	Instructions []term.Term
	pattern *regexp.Regexp
}

type Appup struct {
	CurrentVersion string
	Up []AppupEntry
	Down []AppupEntry
}

type AppupFailure enum {
	InvalidAppup(Detail string)
	InvalidVersionPattern(Pattern string, Detail string)
	MissingVersionScript(Direction AppupDirection, Version string)
}

func (failure AppupFailure) Error() string {
	match failure {
	case InvalidAppup(detail): return "gotp/release: invalid appup: " + detail
	case InvalidVersionPattern(pattern, detail): return "gotp/release: invalid appup version pattern " + pattern + ": " + detail
	case MissingVersionScript(_, version): return "gotp/release: no appup script for version " + version
	}
}

// assayxport:unit gotp.otp.appup
func ParseAppup(encoded term.Term) result.Result[Appup, AppupFailure] {
	match encoded {
	case term.TupleTerm(fields):
		if len(fields) != 3 { return invalidAppup("root tuple must have three fields") }
		match appupText(fields[0]) {
		case option.None: return invalidAppup("current version is not text")
		case option.Some(current):
			match parseAppupEntries(fields[1]) {
			case result.Err(failure): return result.Err[Appup, AppupFailure](failure)
			case result.Ok(up):
				match parseAppupEntries(fields[2]) {
				case result.Err(failure): return result.Err[Appup, AppupFailure](failure)
				case result.Ok(down): return result.Ok[Appup, AppupFailure](Appup{CurrentVersion: current, Up: up, Down: down})
				}
			}
		}
	case _: return invalidAppup("root is not a tuple")
	}
}

func (appup Appup) Select(direction AppupDirection, baseVersion string) result.Result[[]term.Term, AppupFailure] {
	entries := appup.Up
	match direction { case UpgradeScripts: case DowngradeScripts: entries = appup.Down }
	for _, entry := range entries {
		matched := false
		match entry.Selector {
		case ExactVersion(version): matched = version == baseVersion
		case VersionPattern(_): matched = entry.pattern != nil && entry.pattern.FindString(baseVersion) == baseVersion
		}
		if matched { return result.Ok[[]term.Term, AppupFailure](cloneInstructions(entry.Instructions)) }
	}
	return result.Err[[]term.Term, AppupFailure](MissingVersionScript(direction, baseVersion))
}

func parseAppupEntries(encoded term.Term) result.Result[[]AppupEntry, AppupFailure] {
	var values []term.Term
	match encoded { case term.ProperListTerm(found): values = found; case _: return result.Err[[]AppupEntry, AppupFailure](InvalidAppup("script table is not a proper list")) }
	entries := make([]AppupEntry, len(values))
	for index, value := range values {
		match value {
		case term.TupleTerm(fields):
			if len(fields) != 2 { return result.Err[[]AppupEntry, AppupFailure](InvalidAppup("script entry must have two fields")) }
			var instructions []term.Term
			match fields[1] { case term.ProperListTerm(found): instructions = cloneInstructions(found); case _: return result.Err[[]AppupEntry, AppupFailure](InvalidAppup("script instructions are not a proper list")) }
			match fields[0] {
			case term.BinaryTerm(raw):
				pattern := string(raw)
				match result.Of(regexp.Compile(pattern)) {
				case result.Err(cause): return result.Err[[]AppupEntry, AppupFailure](InvalidVersionPattern(pattern, cause.Error()))
				case result.Ok(compiled): entries[index] = AppupEntry{Selector: VersionPattern(pattern), Instructions: instructions, pattern: compiled}
				}
			case _:
				match appupText(fields[0]) { case option.None: return result.Err[[]AppupEntry, AppupFailure](InvalidAppup("version selector is neither text nor binary pattern")); case option.Some(version): entries[index] = AppupEntry{Selector: ExactVersion(version), Instructions: instructions} }
			}
		case _: return result.Err[[]AppupEntry, AppupFailure](InvalidAppup("script entry is not a tuple"))
		}
	}
	return result.Ok[[]AppupEntry, AppupFailure](entries)
}

func appupText(value term.Term) option.Option[string] {
	match value {
	case term.BinaryTerm(raw): return option.Some(string(raw))
	case term.ProperListTerm(characters):
		bytes := make([]byte, len(characters))
		for index, character := range characters { match term.Int64(character) { case option.Some(code): if code < 0 || code > 255 { return option.None[string]() }; bytes[index] = byte(code); case option.None: return option.None[string]() } }
		return option.Some(string(bytes))
	case _: return option.None[string]()
	}
}

func cloneInstructions(values []term.Term) []term.Term { cloned := make([]term.Term, len(values)); for index, value := range values { cloned[index] = value.Clone() }; return cloned }
func invalidAppup(detail string) result.Result[Appup, AppupFailure] { return result.Err[Appup, AppupFailure](InvalidAppup(detail)) }

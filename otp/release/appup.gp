package release

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/dlclark/regexp2"
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
	pattern *regexp2.Regexp
}

type Appup struct {
	CurrentVersion string
	Up []AppupEntry
	Down []AppupEntry
}

type AppupFailure enum {
	InvalidAppup(Detail string)
	InvalidVersionPattern(Pattern string, Detail string)
	VersionPatternFailure(Pattern string, Detail string)
	MissingVersionScript(Direction AppupDirection, Version string)
}

func (failure AppupFailure) Error() string {
	match failure {
	case InvalidAppup(detail): return "gotp/release: invalid appup: " + detail
	case InvalidVersionPattern(pattern, detail): return "gotp/release: invalid appup version pattern " + pattern + ": " + detail
	case VersionPatternFailure(pattern, detail): return "gotp/release: appup version pattern " + pattern + " failed: " + detail
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
		case VersionPattern(pattern):
			if entry.pattern != nil {
				match versionPatternMatches(entry.pattern, pattern, baseVersion) {
				case result.Err(failure): return result.Err[[]term.Term, AppupFailure](failure)
				case result.Ok(found): matched = found
				}
			}
		}
		if matched { return result.Ok[[]term.Term, AppupFailure](cloneInstructions(entry.Instructions)) }
	}
	return result.Err[[]term.Term, AppupFailure](MissingVersionScript(direction, baseVersion))
}

// assayxport:unit gotp.otp.systools-relup-appup-search
func SearchAppupVersion(
	baseVersion string,
	entries []term.Term,
) result.Result[[]term.Term, AppupFailure] {
	for _, encoded := range entries {
		match encoded {
		case term.TupleTerm(fields):
			if len(fields) != 2 { continue }
			var instructions []term.Term
			match fields[1] { case term.ProperListTerm(found): instructions = found; case _: continue }
			match fields[0] {
			case term.BinaryTerm(raw):
				pattern := string(raw)
				match result.Of(regexp2.Compile(pcreCompatiblePattern(pattern), regexp2.None)) {
				case result.Err(cause): return result.Err[[]term.Term, AppupFailure](InvalidVersionPattern(pattern, cause.Error()))
				case result.Ok(compiled):
					match versionPatternMatches(compiled, pattern, baseVersion) {
					case result.Err(failure): return result.Err[[]term.Term, AppupFailure](failure)
					case result.Ok(found): if found { return result.Ok[[]term.Term, AppupFailure](cloneInstructions(instructions)) }
					}
				}
			case _:
				match appupText(fields[0]) {
				case option.Some(version): if version == baseVersion { return result.Ok[[]term.Term, AppupFailure](cloneInstructions(instructions)) }
				case option.None:
				}
			}
		case _:
		}
	}
	return result.Err[[]term.Term, AppupFailure](MissingVersionScript(UpgradeScripts(), baseVersion))
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
				match result.Of(regexp2.Compile(pcreCompatiblePattern(pattern), regexp2.None)) {
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

func versionPatternMatches(
	compiled *regexp2.Regexp,
	pattern string,
	baseVersion string,
) result.Result[bool, AppupFailure] {
	match result.Of(compiled.FindStringMatch(baseVersion)) {
	case result.Err(cause): return result.Err[bool, AppupFailure](VersionPatternFailure(pattern, cause.Error()))
	case result.Ok(found): return result.Ok[bool, AppupFailure](found != nil && found.String() == baseVersion)
	}
}

func pcreCompatiblePattern(pattern string) string {
	var normalized strings.Builder
	for index := 0; index < len(pattern); {
		quantifierEnd := -1
		if !escapedPatternByte(pattern, index) {
			switch pattern[index] {
			case '*', '+', '?': if index+1 < len(pattern) && pattern[index+1] == '+' { quantifierEnd = index + 1 }
			case '{':
				close := strings.IndexByte(pattern[index+1:], '}')
				if close >= 0 {
					close += index + 1
					if close+1 < len(pattern) && pattern[close+1] == '+' && validRepeatRange(pattern[index+1:close]) { quantifierEnd = close + 1 }
				}
			}
		}
		if quantifierEnd >= 0 {
			current := normalized.String()
			match priorRegexAtomStart(current) {
			case option.None: normalized.WriteString(pattern[index:quantifierEnd+1])
			case option.Some(start):
				normalized.Reset()
				normalized.WriteString(current[:start])
				normalized.WriteString("(?>")
				normalized.WriteString(current[start:])
				normalized.WriteString(pattern[index:quantifierEnd])
				normalized.WriteByte(')')
			}
			index = quantifierEnd + 1
			continue
		}
		normalized.WriteByte(pattern[index])
		index++
	}
	return normalized.String()
}

func priorRegexAtomStart(pattern string) option.Option[int] {
	if pattern == "" { return option.None[int]() }
	last := len(pattern) - 1
	switch pattern[last] {
	case ')': return scanRegexGroupStart(pattern, last, '(', ')')
	case ']': return scanRegexGroupStart(pattern, last, '[', ']')
	case '}':
		open := strings.LastIndexByte(pattern[:last], '{')
		if open > 1 && pattern[open-2] == '\\' && (pattern[open-1] == 'p' || pattern[open-1] == 'P') { return option.Some[int](open-2) }
	}
	_, width := utf8.DecodeLastRuneInString(pattern)
	start := len(pattern) - width
	if start > 0 && pattern[start-1] == '\\' && !escapedPatternByte(pattern, start-1) { start-- }
	return option.Some[int](start)
}

func scanRegexGroupStart(pattern string, end int, open byte, close byte) option.Option[int] {
	depth := 0
	for index := end; index >= 0; index-- {
		if escapedPatternByte(pattern, index) { continue }
		if pattern[index] == close { depth++ }
		if pattern[index] == open {
			depth--
			if depth == 0 { return option.Some[int](index) }
		}
	}
	return option.None[int]()
}

func escapedPatternByte(pattern string, index int) bool {
	slashes := 0
	for index--; index >= 0 && pattern[index] == '\\'; index-- { slashes++ }
	return slashes%2 == 1
}

func validRepeatRange(value string) bool {
	if value == "" { return false }
	commas := 0
	digits := 0
	for _, character := range value {
		if character == ',' { commas++; if commas > 1 { return false }; continue }
		if character < '0' || character > '9' { return false }
		digits++
	}
	return digits > 0
}

func appupText(value term.Term) option.Option[string] {
	match value {
	case term.BinaryTerm(raw): return option.Some(string(raw))
	case term.ProperListTerm(characters):
		var text strings.Builder
		for _, character := range characters {
			match term.Int64(character) {
			case option.Some(code):
				if code < 0 || code > unicode.MaxRune || code >= 0xD800 && code <= 0xDFFF { return option.None[string]() }
				text.WriteRune(rune(code))
			case option.None: return option.None[string]()
			}
		}
		return option.Some(text.String())
	case _: return option.None[string]()
	}
}

func cloneInstructions(values []term.Term) []term.Term { cloned := make([]term.Term, len(values)); for index, value := range values { cloned[index] = value.Clone() }; return cloned }
func invalidAppup(detail string) result.Result[Appup, AppupFailure] { return result.Err[Appup, AppupFailure](InvalidAppup(detail)) }

package ets

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

//goplus:derive off
type ObjectPattern enum {
	AnyPattern()
	VariablePattern(Index int)
	ConstantPattern(Value term.Term)
	TuplePattern(Elements []ObjectPattern)
	ListPattern(Elements []ObjectPattern)
}

type CompiledObjectPattern struct {
	root ObjectPattern
	variables []int
}

type MatchFailure enum {
	InvalidPatternVariable(Name string)
	MatchTableFailure(Cause Failure)
}

func (failure MatchFailure) Error() string {
	match failure {
	case InvalidPatternVariable(name):
		return fmt.Sprintf("gotp/ets: invalid match variable %q", name)
	case MatchTableFailure(cause):
		return cause.Error()
	}
}

// assayxport:unit gotp.otp.ets-object-patterns
func CompileObjectPattern(value term.Term) result.Result[CompiledObjectPattern, MatchFailure] {
	variables := make(map[int]struct{})
	var root ObjectPattern
	match compileObjectPattern(value, variables) {
	case result.Err(failure):
		return result.Err[CompiledObjectPattern, MatchFailure](failure)
	case result.Ok(compiled):
		root = compiled
	}
	indexes := make([]int, 0, len(variables))
	for index := range variables {
		indexes = append(indexes, index)
	}
	sort.Ints(indexes)
	return result.Ok[CompiledObjectPattern, MatchFailure](CompiledObjectPattern{
		root: root, variables: indexes,
	})
}

func compileObjectPattern(
	value term.Term,
	variables map[int]struct{},
) result.Result[ObjectPattern, MatchFailure] {
	match value {
	case term.AtomTerm(name):
		if name == "_" {
			return result.Ok[ObjectPattern, MatchFailure](AnyPattern())
		}
		if strings.HasPrefix(name, "$") && len(name) > 1 {
			digits := name[1:]
			index, parseFailure := strconv.Atoi(digits)
			match result.Of(index, parseFailure) {
			case result.Ok(parsed):
				if parsed < 1 {
					return result.Err[ObjectPattern, MatchFailure](InvalidPatternVariable(name))
				}
				variables[parsed] = struct{}{}
				return result.Ok[ObjectPattern, MatchFailure](VariablePattern(parsed))
			case result.Err(_):
			}
		}
		return result.Ok[ObjectPattern, MatchFailure](ConstantPattern(value.Clone()))
	case term.TupleTerm(elements):
		match compilePatternElements(elements, variables) {
		case result.Err(failure):
			return result.Err[ObjectPattern, MatchFailure](failure)
		case result.Ok(compiled):
			return result.Ok[ObjectPattern, MatchFailure](TuplePattern(compiled))
		}
	case term.ProperListTerm(elements):
		match compilePatternElements(elements, variables) {
		case result.Err(failure):
			return result.Err[ObjectPattern, MatchFailure](failure)
		case result.Ok(compiled):
			return result.Ok[ObjectPattern, MatchFailure](ListPattern(compiled))
		}
	case _:
		return result.Ok[ObjectPattern, MatchFailure](ConstantPattern(value.Clone()))
	}
}

func compilePatternElements(
	elements []term.Term,
	variables map[int]struct{},
) result.Result[[]ObjectPattern, MatchFailure] {
	compiled := make([]ObjectPattern, 0, len(elements))
	for _, element := range elements {
		match compileObjectPattern(element, variables) {
		case result.Err(failure):
			return result.Err[[]ObjectPattern, MatchFailure](failure)
		case result.Ok(pattern):
			compiled = append(compiled, pattern)
		}
	}
	return result.Ok[[]ObjectPattern, MatchFailure](compiled)
}

func (registry *Registry) MatchObject(
	caller term.PID,
	id TableID,
	pattern term.Term,
) result.Result[[]term.Term, MatchFailure] {
	var compiled CompiledObjectPattern
	match CompileObjectPattern(pattern) {
	case result.Err(failure):
		return result.Err[[]term.Term, MatchFailure](failure)
	case result.Ok(value):
		compiled = value
	}
	match registry.table(id) {
	case option.None:
		return result.Err[[]term.Term, MatchFailure](MatchTableFailure(MissingTable(id)))
	case option.Some(found):
		return found.matchObjects(caller, compiled)
	}
}

func (registry *Registry) Match(
	caller term.PID,
	id TableID,
	pattern term.Term,
) result.Result[[][]term.Term, MatchFailure] {
	var compiled CompiledObjectPattern
	match CompileObjectPattern(pattern) {
	case result.Err(failure):
		return result.Err[[][]term.Term, MatchFailure](failure)
	case result.Ok(value):
		compiled = value
	}
	match registry.table(id) {
	case option.None:
		return result.Err[[][]term.Term, MatchFailure](MatchTableFailure(MissingTable(id)))
	case option.Some(found):
		return found.matchBindings(caller, compiled)
	}
}

func (registry *Registry) MatchDelete(
	caller term.PID,
	id TableID,
	pattern term.Term,
) result.Result[int, MatchFailure] {
	var compiled CompiledObjectPattern
	match CompileObjectPattern(pattern) {
	case result.Err(failure):
		return result.Err[int, MatchFailure](failure)
	case result.Ok(value):
		compiled = value
	}
	match registry.table(id) {
	case option.None:
		return result.Err[int, MatchFailure](MatchTableFailure(MissingTable(id)))
	case option.Some(found):
		return found.matchDelete(caller, compiled)
	}
}

func (table *table) matchObjects(
	caller term.PID,
	pattern CompiledObjectPattern,
) result.Result[[]term.Term, MatchFailure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[[]term.Term, MatchFailure](MatchTableFailure(failure))
	case option.None:
	}
	objects := []term.Term{}
	for _, object := range table.rows {
		bindings := make(map[int]term.Term)
		if objectPatternMatches(pattern.root, object, bindings) {
			objects = append(objects, object.Clone())
		}
	}
	return result.Ok[[]term.Term, MatchFailure](objects)
}

func (table *table) matchBindings(
	caller term.PID,
	pattern CompiledObjectPattern,
) result.Result[[][]term.Term, MatchFailure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) {
	case option.Some(failure):
		return result.Err[[][]term.Term, MatchFailure](MatchTableFailure(failure))
	case option.None:
	}
	matches := [][]term.Term{}
	for _, object := range table.rows {
		bindings := make(map[int]term.Term)
		if !objectPatternMatches(pattern.root, object, bindings) {
			continue
		}
		captured := make([]term.Term, 0, len(pattern.variables))
		for _, index := range pattern.variables {
			captured = append(captured, bindings[index].Clone())
		}
		matches = append(matches, captured)
	}
	return result.Ok[[][]term.Term, MatchFailure](matches)
}

func (table *table) matchDelete(
	caller term.PID,
	pattern CompiledObjectPattern,
) result.Result[int, MatchFailure] {
	table.mu.Lock()
	defer table.mu.Unlock()
	match table.writeFailure(caller) {
	case option.Some(failure):
		return result.Err[int, MatchFailure](MatchTableFailure(failure))
	case option.None:
	}
	kept := table.rows[:0]
	removed := 0
	for _, object := range table.rows {
		bindings := make(map[int]term.Term)
		if objectPatternMatches(pattern.root, object, bindings) {
			removed++
		} else {
			kept = append(kept, object)
		}
	}
	table.rows = kept
	return result.Ok[int, MatchFailure](removed)
}

func objectPatternMatches(
	pattern ObjectPattern,
	value term.Term,
	bindings map[int]term.Term,
) bool {
	match pattern {
	case AnyPattern:
		return true
	case ConstantPattern(expected):
		return term.Equal(expected, value)
	case VariablePattern(index):
		bound, present := bindings[index]
		match option.Of(bound, present) {
		case option.None:
			bindings[index] = value.Clone()
			return true
		case option.Some(expected):
			return term.Equal(expected, value)
		}
	case TuplePattern(patterns):
		match value {
		case term.TupleTerm(elements):
			return patternElementsMatch(patterns, elements, bindings)
		case _:
			return false
		}
	case ListPattern(patterns):
		match value {
		case term.ProperListTerm(elements):
			return patternElementsMatch(patterns, elements, bindings)
		case _:
			return false
		}
	}
}

func patternElementsMatch(
	patterns []ObjectPattern,
	values []term.Term,
	bindings map[int]term.Term,
) bool {
	if len(patterns) != len(values) {
		return false
	}
	for index, pattern := range patterns {
		if !objectPatternMatches(pattern, values[index], bindings) {
			return false
		}
	}
	return true
}

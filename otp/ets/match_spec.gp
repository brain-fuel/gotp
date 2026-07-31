package ets

import (
	"fmt"
	"strconv"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type MatchOperator enum {
	ExactEqualOperator()
	LooseEqualOperator()
	LessOperator()
	LessEqualOperator()
	GreaterOperator()
	GreaterEqualOperator()
	AndAlsoOperator()
	OrElseOperator()
	NotOperator()
	IsAtomOperator()
	IsIntegerOperator()
	IsNumberOperator()
	IsTupleOperator()
	IsListOperator()
}

//goplus:derive off
type MatchExpression enum {
	MatchLiteral(Value term.Term)
	MatchVariable(Index int)
	MatchWholeObject()
	MatchAllBindings()
	MatchCall(Operator MatchOperator, Arguments []MatchExpression)
}

type MatchClause struct {
	head CompiledObjectPattern
	guards []MatchExpression
	body []MatchExpression
}

type CompiledMatchSpec struct {
	clauses []MatchClause
}

type SelectContinuation struct {
	values []term.Term
	offset int
	limit int
}

//goplus:derive off
type SelectPage enum {
	SelectComplete(Values []term.Term)
	SelectMore(Values []term.Term, Continuation SelectContinuation)
}

type MatchSpecFailure enum {
	InvalidMatchSpec(Detail string)
	UnknownMatchOperator(Name string)
	InvalidMatchArity(Name string, Expected int, Found int)
	UnboundMatchVariable(Index int)
	MatchSpecTableFailure(Cause Failure)
	MatchSpecPatternFailure(Cause MatchFailure)
	MatchEvaluationFailure(Detail string)
	InvalidSelectLimit(Limit int)
	InvalidSelectContinuation()
}

func (failure MatchSpecFailure) Error() string {
	match failure {
	case InvalidMatchSpec(detail):
		return "gotp/ets: invalid match spec: " + detail
	case UnknownMatchOperator(name):
		return fmt.Sprintf("gotp/ets: unknown match operator %q", name)
	case InvalidMatchArity(name, expected, found):
		return fmt.Sprintf("gotp/ets: operator %s expects %d arguments, got %d", name, expected, found)
	case UnboundMatchVariable(index):
		return fmt.Sprintf("gotp/ets: match variable $%d is not bound by head", index)
	case MatchSpecTableFailure(cause):
		return cause.Error()
	case MatchSpecPatternFailure(cause):
		return cause.Error()
	case MatchEvaluationFailure(detail):
		return "gotp/ets: match evaluation: " + detail
	case InvalidSelectLimit(limit):
		return fmt.Sprintf("gotp/ets: select limit must be positive, got %d", limit)
	case InvalidSelectContinuation:
		return "gotp/ets: invalid select continuation"
	}
}

// assayxport:unit gotp.otp.ets-match-specs
func CompileMatchSpec(value term.Term) result.Result[CompiledMatchSpec, MatchSpecFailure] {
	var clauses []term.Term
	match value {
	case term.ProperListTerm(elements):
		clauses = elements
	case _:
		return result.Err[CompiledMatchSpec, MatchSpecFailure](InvalidMatchSpec("expected clause list"))
	}
	if len(clauses) == 0 {
		return result.Err[CompiledMatchSpec, MatchSpecFailure](InvalidMatchSpec("clause list is empty"))
	}
	compiled := make([]MatchClause, 0, len(clauses))
	for _, clauseTerm := range clauses {
		match compileMatchClause(clauseTerm) {
		case result.Err(failure):
			return result.Err[CompiledMatchSpec, MatchSpecFailure](failure)
		case result.Ok(clause):
			compiled = append(compiled, clause)
		}
	}
	return result.Ok[CompiledMatchSpec, MatchSpecFailure](CompiledMatchSpec{clauses: compiled})
}

func compileMatchClause(value term.Term) result.Result[MatchClause, MatchSpecFailure] {
	var fields []term.Term
	match value {
	case term.TupleTerm(elements):
		fields = elements
	case _:
		return result.Err[MatchClause, MatchSpecFailure](InvalidMatchSpec("clause must be a tuple"))
	}
	if len(fields) != 3 {
		return result.Err[MatchClause, MatchSpecFailure](InvalidMatchSpec("clause tuple must have arity three"))
	}
	var head CompiledObjectPattern
	match CompileObjectPattern(fields[0]) {
	case result.Err(failure):
		return result.Err[MatchClause, MatchSpecFailure](MatchSpecPatternFailure(failure))
	case result.Ok(compiled):
		head = compiled
	}
	allowed := make(map[int]struct{}, len(head.variables))
	for _, index := range head.variables {
		allowed[index] = struct{}{}
	}
	var guards []MatchExpression
	match compileExpressionList(fields[1], allowed, false) {
	case result.Err(failure):
		return result.Err[MatchClause, MatchSpecFailure](failure)
	case result.Ok(compiled):
		guards = compiled
	}
	var body []MatchExpression
	match compileExpressionList(fields[2], allowed, true) {
	case result.Err(failure):
		return result.Err[MatchClause, MatchSpecFailure](failure)
	case result.Ok(compiled):
		body = compiled
	}
	if len(body) == 0 {
		return result.Err[MatchClause, MatchSpecFailure](InvalidMatchSpec("clause body is empty"))
	}
	return result.Ok[MatchClause, MatchSpecFailure](MatchClause{head: head, guards: guards, body: body})
}

func compileExpressionList(
	value term.Term,
	allowed map[int]struct{},
	body bool,
) result.Result[[]MatchExpression, MatchSpecFailure] {
	var values []term.Term
	match value {
	case term.ProperListTerm(elements):
		values = elements
	case _:
		return result.Err[[]MatchExpression, MatchSpecFailure](InvalidMatchSpec("guards and body must be lists"))
	}
	compiled := make([]MatchExpression, 0, len(values))
	for _, expression := range values {
		match compileMatchExpression(expression, allowed, body) {
		case result.Err(failure):
			return result.Err[[]MatchExpression, MatchSpecFailure](failure)
		case result.Ok(found):
			compiled = append(compiled, found)
		}
	}
	return result.Ok[[]MatchExpression, MatchSpecFailure](compiled)
}

func compileMatchExpression(
	value term.Term,
	allowed map[int]struct{},
	body bool,
) result.Result[MatchExpression, MatchSpecFailure] {
	match value {
	case term.AtomTerm(name):
		if name == "$_" {
			return result.Ok[MatchExpression, MatchSpecFailure](MatchWholeObject())
		}
		if name == "$$" {
			return result.Ok[MatchExpression, MatchSpecFailure](MatchAllBindings())
		}
		if strings.HasPrefix(name, "$") && len(name) > 1 {
			parsed, parseFailure := strconv.Atoi(name[1:])
			match result.Of(parsed, parseFailure) {
			case result.Ok(index):
				if _, present := allowed[index]; !present {
					return result.Err[MatchExpression, MatchSpecFailure](UnboundMatchVariable(index))
				}
				return result.Ok[MatchExpression, MatchSpecFailure](MatchVariable(index))
			case result.Err(_):
			}
		}
		return result.Ok[MatchExpression, MatchSpecFailure](MatchLiteral(value.Clone()))
	case term.TupleTerm(elements):
		if len(elements) == 2 {
			match term.AtomName(elements[0]) {
			case option.Some(name):
				if name == "const" {
					return result.Ok[MatchExpression, MatchSpecFailure](MatchLiteral(elements[1].Clone()))
				}
			case option.None:
			}
		}
		if len(elements) == 0 {
			return result.Err[MatchExpression, MatchSpecFailure](InvalidMatchSpec("empty call tuple"))
		}
		var name string
		match term.AtomName(elements[0]) {
		case option.None:
			return result.Err[MatchExpression, MatchSpecFailure](InvalidMatchSpec("operator must be atom"))
		case option.Some(found):
			name = found
		}
		var operator MatchOperator
		match matchOperator(name, len(elements)-1) {
		case result.Err(failure):
			return result.Err[MatchExpression, MatchSpecFailure](failure)
		case result.Ok(found):
			operator = found
		}
		arguments := make([]MatchExpression, 0, len(elements)-1)
		for _, argument := range elements[1:] {
			match compileMatchExpression(argument, allowed, body) {
			case result.Err(failure):
				return result.Err[MatchExpression, MatchSpecFailure](failure)
			case result.Ok(compiled):
				arguments = append(arguments, compiled)
			}
		}
		return result.Ok[MatchExpression, MatchSpecFailure](MatchCall(operator, arguments))
	case _:
		return result.Ok[MatchExpression, MatchSpecFailure](MatchLiteral(value.Clone()))
	}
}

func matchOperator(name string, arity int) result.Result[MatchOperator, MatchSpecFailure] {
	var operator MatchOperator
	expected := 2
	switch name {
	case "=:=": operator = ExactEqualOperator()
	case "==": operator = LooseEqualOperator()
	case "<": operator = LessOperator()
	case "=<": operator = LessEqualOperator()
	case ">": operator = GreaterOperator()
	case ">=": operator = GreaterEqualOperator()
	case "andalso": operator = AndAlsoOperator()
	case "orelse": operator = OrElseOperator()
	case "not": operator = NotOperator(); expected = 1
	case "is_atom": operator = IsAtomOperator(); expected = 1
	case "is_integer": operator = IsIntegerOperator(); expected = 1
	case "is_number": operator = IsNumberOperator(); expected = 1
	case "is_tuple": operator = IsTupleOperator(); expected = 1
	case "is_list": operator = IsListOperator(); expected = 1
	default:
		return result.Err[MatchOperator, MatchSpecFailure](UnknownMatchOperator(name))
	}
	if arity != expected {
		return result.Err[MatchOperator, MatchSpecFailure](InvalidMatchArity(name, expected, arity))
	}
	return result.Ok[MatchOperator, MatchSpecFailure](operator)
}

func (registry *Registry) Select(caller term.PID, id TableID, spec term.Term) result.Result[[]term.Term, MatchSpecFailure] {
	var compiled CompiledMatchSpec
	match CompileMatchSpec(spec) { case result.Err(failure): return result.Err[[]term.Term, MatchSpecFailure](failure); case result.Ok(value): compiled = value }
	match registry.table(id) {
	case option.None: return result.Err[[]term.Term, MatchSpecFailure](MatchSpecTableFailure(MissingTable(id)))
	case option.Some(found): return found.selectObjects(caller, compiled)
	}
}

func (registry *Registry) SelectLimit(
	caller term.PID,
	id TableID,
	spec term.Term,
	limit int,
) result.Result[SelectPage, MatchSpecFailure] {
	if limit <= 0 {
		return result.Err[SelectPage, MatchSpecFailure](InvalidSelectLimit(limit))
	}
	match registry.Select(caller, id, spec) {
	case result.Err(failure):
		return result.Err[SelectPage, MatchSpecFailure](failure)
	case result.Ok(values):
		return result.Ok[SelectPage, MatchSpecFailure](selectionPage(
			SelectContinuation{values: cloneSelection(values), offset: 0, limit: limit},
		))
	}
}

func ContinueSelect(
	continuation SelectContinuation,
) result.Result[SelectPage, MatchSpecFailure] {
	if continuation.limit <= 0 || continuation.offset < 0 || continuation.offset > len(continuation.values) {
		return result.Err[SelectPage, MatchSpecFailure](InvalidSelectContinuation())
	}
	return result.Ok[SelectPage, MatchSpecFailure](selectionPage(continuation))
}

func selectionPage(continuation SelectContinuation) SelectPage {
	end := continuation.offset + continuation.limit
	if end > len(continuation.values) {
		end = len(continuation.values)
	}
	page := cloneSelection(continuation.values[continuation.offset:end])
	if end == len(continuation.values) {
		return SelectComplete(page)
	}
	return SelectMore(page, SelectContinuation{
		values: cloneSelection(continuation.values), offset: end, limit: continuation.limit,
	})
}

func cloneSelection(values []term.Term) []term.Term {
	cloned := make([]term.Term, len(values))
	for index, value := range values {
		cloned[index] = value.Clone()
	}
	return cloned
}

func (registry *Registry) SelectCount(caller term.PID, id TableID, spec term.Term) result.Result[int, MatchSpecFailure] {
	var compiled CompiledMatchSpec
	match CompileMatchSpec(spec) { case result.Err(failure): return result.Err[int, MatchSpecFailure](failure); case result.Ok(value): compiled = value }
	match registry.table(id) {
	case option.None: return result.Err[int, MatchSpecFailure](MatchSpecTableFailure(MissingTable(id)))
	case option.Some(found): return found.selectBoolean(caller, compiled, false)
	}
}

func (registry *Registry) SelectDelete(caller term.PID, id TableID, spec term.Term) result.Result[int, MatchSpecFailure] {
	var compiled CompiledMatchSpec
	match CompileMatchSpec(spec) { case result.Err(failure): return result.Err[int, MatchSpecFailure](failure); case result.Ok(value): compiled = value }
	match registry.table(id) {
	case option.None: return result.Err[int, MatchSpecFailure](MatchSpecTableFailure(MissingTable(id)))
	case option.Some(found): return found.selectBoolean(caller, compiled, true)
	}
}

func (table *table) selectObjects(caller term.PID, spec CompiledMatchSpec) result.Result[[]term.Term, MatchSpecFailure] {
	table.mu.RLock()
	defer table.mu.RUnlock()
	match table.readFailure(caller) { case option.Some(failure): return result.Err[[]term.Term, MatchSpecFailure](MatchSpecTableFailure(failure)); case option.None: }
	selected := []term.Term{}
	for _, object := range table.rows {
		match evaluateMatchSpec(spec, object) {
		case result.Err(failure): return result.Err[[]term.Term, MatchSpecFailure](failure)
		case result.Ok(outcome):
			match outcome {
			case option.None:
			case option.Some(value): selected = append(selected, value.Clone())
			}
		}
	}
	return result.Ok[[]term.Term, MatchSpecFailure](selected)
}

func (table *table) selectBoolean(caller term.PID, spec CompiledMatchSpec, remove bool) result.Result[int, MatchSpecFailure] {
	if remove { table.mu.Lock(); defer table.mu.Unlock() } else { table.mu.RLock(); defer table.mu.RUnlock() }
	var denied option.Option[Failure]
	if remove { denied = table.writeFailure(caller) } else { denied = table.readFailure(caller) }
	match denied { case option.Some(failure): return result.Err[int, MatchSpecFailure](MatchSpecTableFailure(failure)); case option.None: }
	kept := table.rows[:0]
	count := 0
	for _, object := range table.rows {
		matched := false
		match evaluateMatchSpec(spec, object) {
		case result.Err(failure): return result.Err[int, MatchSpecFailure](failure)
		case result.Ok(outcome):
			match outcome {
			case option.None:
			case option.Some(value): matched = matchBoolean(value)
			}
		}
		if matched { count++ } else if remove { kept = append(kept, object) }
	}
	if remove { table.rows = kept }
	return result.Ok[int, MatchSpecFailure](count)
}

func evaluateMatchSpec(spec CompiledMatchSpec, object term.Term) result.Result[option.Option[term.Term], MatchSpecFailure] {
	for _, clause := range spec.clauses {
		bindings := make(map[int]term.Term)
		if !objectPatternMatches(clause.head.root, object, bindings) { continue }
		guardsPass := true
		for _, guard := range clause.guards {
			match evaluateMatchExpression(guard, object, clause.head.variables, bindings) {
			case result.Err(_): guardsPass = false
			case result.Ok(value): if !matchBoolean(value) { guardsPass = false }
			}
			if !guardsPass { break }
		}
		if !guardsPass { continue }
		var value term.Term
		for _, expression := range clause.body {
			match evaluateMatchExpression(expression, object, clause.head.variables, bindings) {
			case result.Err(failure): return result.Err[option.Option[term.Term], MatchSpecFailure](failure)
			case result.Ok(found): value = found
			}
		}
		return result.Ok[option.Option[term.Term], MatchSpecFailure](option.Some[term.Term](value.Clone()))
	}
	return result.Ok[option.Option[term.Term], MatchSpecFailure](option.None[term.Term])
}

func evaluateMatchExpression(expression MatchExpression, object term.Term, indexes []int, bindings map[int]term.Term) result.Result[term.Term, MatchSpecFailure] {
	match expression {
	case MatchLiteral(value): return result.Ok[term.Term, MatchSpecFailure](value.Clone())
	case MatchWholeObject: return result.Ok[term.Term, MatchSpecFailure](object.Clone())
	case MatchAllBindings:
		values := make([]term.Term, 0, len(indexes)); for _, index := range indexes { values = append(values, bindings[index].Clone()) }
		return result.Ok[term.Term, MatchSpecFailure](term.List(values...))
	case MatchVariable(index):
		value, present := bindings[index]
		match option.Of(value, present) { case option.None: return result.Err[term.Term, MatchSpecFailure](UnboundMatchVariable(index)); case option.Some(found): return result.Ok[term.Term, MatchSpecFailure](found.Clone()) }
	case MatchCall(operator, arguments):
		values := make([]term.Term, 0, len(arguments)); for _, argument := range arguments { match evaluateMatchExpression(argument, object, indexes, bindings) { case result.Err(failure): return result.Err[term.Term, MatchSpecFailure](failure); case result.Ok(value): values = append(values, value) } }
		return evaluateMatchCall(operator, values)
	}
}

func evaluateMatchCall(operator MatchOperator, values []term.Term) result.Result[term.Term, MatchSpecFailure] {
	truth := false
	match operator {
	case ExactEqualOperator: truth = term.Equal(values[0], values[1])
	case LooseEqualOperator, LessOperator, LessEqualOperator, GreaterOperator, GreaterEqualOperator:
		match term.Compare(values[0], values[1]) {
		case result.Err(_): return result.Err[term.Term, MatchSpecFailure](MatchEvaluationFailure("terms are not ordered"))
		case result.Ok(order):
			match operator {
			case LooseEqualOperator: match order { case term.TermEqual: truth = true; case term.TermLess, term.TermGreater: }
			case LessOperator: match order { case term.TermLess: truth = true; case term.TermEqual, term.TermGreater: }
			case LessEqualOperator: match order { case term.TermLess, term.TermEqual: truth = true; case term.TermGreater: }
			case GreaterOperator: match order { case term.TermGreater: truth = true; case term.TermLess, term.TermEqual: }
			case GreaterEqualOperator: match order { case term.TermGreater, term.TermEqual: truth = true; case term.TermLess: }
			case ExactEqualOperator, AndAlsoOperator, OrElseOperator, NotOperator, IsAtomOperator, IsIntegerOperator, IsNumberOperator, IsTupleOperator, IsListOperator:
			}
		}
	case AndAlsoOperator: truth = matchBoolean(values[0]) && matchBoolean(values[1])
	case OrElseOperator: truth = matchBoolean(values[0]) || matchBoolean(values[1])
	case NotOperator: truth = !matchBoolean(values[0])
	case IsAtomOperator: match values[0] { case term.AtomTerm(_): truth = true; case _: }
	case IsIntegerOperator: match values[0] { case term.IntegerTerm(_): truth = true; case _: }
	case IsNumberOperator: match values[0] { case term.IntegerTerm(_), term.FloatTerm(_): truth = true; case _: }
	case IsTupleOperator: match values[0] { case term.TupleTerm(_): truth = true; case _: }
	case IsListOperator: match values[0] { case term.ProperListTerm(_), term.ImproperListTerm(_, _): truth = true; case _: }
	}
	if truth { return result.Ok[term.Term, MatchSpecFailure](term.MustAtom("true")) }
	return result.Ok[term.Term, MatchSpecFailure](term.MustAtom("false"))
}

func matchBoolean(value term.Term) bool {
	match term.AtomName(value) { case option.Some(name): return name == "true"; case option.None: return false }
}

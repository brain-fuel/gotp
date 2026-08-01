package erts

import (
	"fmt"
	"math/big"
	"time"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:unit gotp.erts.otp-context-bifs
func (process *VMProcess) contextualCall(
	context *kernel.Context,
	target vm.ExternalFunction,
	arguments []term.Term,
) vm.ExternalCallOutcome {
	if target.Module == "erlang" && target.Function == "self" && target.Arity == 0 { return vm.ExternalCallReturned(term.PIDValue(context.Self())) }
	if target.Module == "erlang" && target.Function == "make_ref" && target.Arity == 0 { return vm.ExternalCallReturned(term.ReferenceValue(context.MakeReference())) }
	if target.Module == "erlang" && target.Function == "garbage_collect" && target.Arity == 0 { return vm.ExternalCallReturned(term.MustAtom("true")) }
	if target.Module == "erlang" && target.Function == "hibernate" && target.Arity == 0 { return vm.ExternalCallReturned(term.MustAtom("true")) }
	if target.Module == "erlang" && target.Function == "monotonic_time" && (target.Arity == 0 || target.Arity == 1) { return process.otpMonotonicTime(arguments) }
	if target.Module == "erlang" && target.Function == "node" && target.Arity == 0 { return vm.ExternalCallReturned(term.MustAtom(context.NodeName())) }
	if target.Module == "erlang" && target.Function == "node" && target.Arity == 1 {
		match term.TermPIDValue(arguments[0]) { case option.Some(pid): match context.NodeNameFor(pid.Node) { case option.None: return otpBadarg(); case option.Some(name): return vm.ExternalCallReturned(term.MustAtom(name)) }; case option.None: }
		match term.TermReferenceValue(arguments[0]) { case option.Some(reference): match context.NodeNameFor(reference.Node) { case option.None: return otpBadarg(); case option.Some(name): return vm.ExternalCallReturned(term.MustAtom(name)) }; case option.None: return otpBadarg() }
	}
	if target.Module == "erlang" && target.Function == "pid_to_list" && target.Arity == 1 {
		match term.TermPIDValue(arguments[0]) {
		case option.None: return otpBadarg()
		case option.Some(pid):
			text := fmt.Sprintf("<0.%d.%d>", pid.Number, pid.Serial)
			characters := make([]term.Term, len(text))
			for index := range text { characters[index] = term.Integer(int64(text[index])) }
			return vm.ExternalCallReturned(term.List(characters...))
		}
	}
	if target.Module == "erlang" && target.Function == "nodes" && target.Arity == 0 { values := []term.Term{}; for _, node := range context.ConnectedNodes() { values = append(values, term.MustAtom(node)) }; return vm.ExternalCallReturned(term.List(values...)) }
	if target.Module == "erlang" && target.Function == "send" && (target.Arity == 2 || target.Arity == 3) { return otpContextSend(context, arguments, target.Arity == 3) }
	if target.Module == "erlang" && target.Function == "spawn_opt" && target.Arity == 4 { return process.otpContextSpawn(context, arguments) }
	if target.Module == "erlang" && target.Function == "spawn_monitor" && target.Arity == 3 { return process.otpContextSpawnMonitor(context, arguments) }
	if target.Module == "erlang" && target.Function == "monitor" && (target.Arity == 2 || target.Arity == 3) { return otpContextMonitor(context, arguments) }
	if target.Module == "erlang" && target.Function == "demonitor" && (target.Arity == 1 || target.Arity == 2) { return otpContextDemonitor(context, arguments) }
	if target.Module == "erlang" && target.Function == "link" && target.Arity == 1 { match term.TermPIDValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(pid): match context.Link(pid) { case result.Err(failure): return vm.ExternalCallRejected(failure.Error()); case result.Ok(_): return vm.ExternalCallReturned(term.MustAtom("true")) } } }
	if target.Module == "erlang" && target.Function == "unlink" && target.Arity == 1 { match term.TermPIDValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(pid): context.Unlink(pid); return vm.ExternalCallReturned(term.MustAtom("true")) } }
	if target.Module == "erlang" && target.Function == "process_flag" && target.Arity == 2 { match term.AtomName(arguments[0]) { case option.Some(flag): if flag != "trap_exit" { return otpBadarg() }; match term.AtomName(arguments[1]) { case option.Some(value): switch value { case "true": context.SetTrapExit(true); return vm.ExternalCallReturned(term.MustAtom("false")); case "false": context.SetTrapExit(false); return vm.ExternalCallReturned(term.MustAtom("false")); default: return otpBadarg() }; case option.None: return otpBadarg() }; case option.None: return otpBadarg() } }
	if target.Module == "erlang" && target.Function == "register" && target.Arity == 2 { return otpContextRegister(context, arguments) }
	if target.Module == "erlang" && target.Function == "unregister" && target.Arity == 1 { match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(name): match context.Unregister(name) { case result.Err(_): return otpBadarg(); case result.Ok(_): return vm.ExternalCallReturned(term.MustAtom("true")) } } }
	if target.Module == "erlang" && target.Function == "whereis" && target.Arity == 1 { match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(name): match context.Whereis(name) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(pid): return vm.ExternalCallReturned(term.PIDValue(pid)) } } }
	if target.Module == "erlang" && target.Function == "process_info" && target.Arity == 2 {
		var pid term.PID; match term.TermPIDValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): pid = value }
		match term.AtomName(arguments[1]) { case option.None: return otpBadarg(); case option.Some(item): match context.ProcessInfo(pid, item) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(value): return vm.ExternalCallReturned(value) } }
	}
	if target.Module == "erlang" && target.Function == "put" && target.Arity == 2 { match context.DictionaryPut(arguments[0], arguments[1]) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(value): return vm.ExternalCallReturned(value) } }
	if target.Module == "erlang" && target.Function == "get" && target.Arity == 1 { match context.DictionaryGet(arguments[0]) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(value): return vm.ExternalCallReturned(value) } }
	if target.Module == "erlang" && target.Function == "get" && target.Arity == 0 { return vm.ExternalCallReturned(term.List(context.DictionaryEntries()...)) }
	if target.Module == "erlang" && target.Function == "erase" && target.Arity == 1 { match context.DictionaryErase(arguments[0]) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(value): return vm.ExternalCallReturned(value) } }
	if target.Module == "persistent_term" && target.Function == "get" && target.Arity == 1 { match context.PersistentGet(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): return vm.ExternalCallReturned(value) } }
	if target.Module == "persistent_term" && target.Function == "get" && target.Arity == 2 { match context.PersistentGet(arguments[0]) { case option.None: return vm.ExternalCallReturned(term.Clone(arguments[1])); case option.Some(value): return vm.ExternalCallReturned(value) } }
	if target.Module == "persistent_term" && target.Function == "put" && target.Arity == 2 { context.PersistentPut(arguments[0], arguments[1]); return vm.ExternalCallReturned(term.MustAtom("ok")) }
	if target.Module == "persistent_term" && target.Function == "erase" && target.Arity == 1 { erased := context.PersistentErase(arguments[0]); if erased { return vm.ExternalCallReturned(term.MustAtom("true")) }; return vm.ExternalCallReturned(term.MustAtom("false")) }
	if target.Module == "application" && target.Function == "get_env" && target.Arity == 2 { return vm.ExternalCallReturned(term.MustAtom("undefined")) }
	if target.Module == "application" && target.Function == "get_env" && target.Arity == 3 { return vm.ExternalCallReturned(term.Clone(arguments[2])) }
	if target.Module == "os" && target.Function == "getenv" && target.Arity == 1 { return vm.ExternalCallReturned(term.MustAtom("false")) }
	if target.Module == "init" && target.Function == "get_arguments" && target.Arity == 0 { return vm.ExternalCallReturned(term.List()) }
	if target.Module == "init" && target.Function == "get_argument" && target.Arity == 1 { return vm.ExternalCallReturned(term.MustAtom("error")) }
	if target.Module == "global" && target.Function == "register_name" && target.Arity == 2 { match term.TermPIDValue(arguments[1]) { case option.None: return otpBadarg(); case option.Some(pid): if context.RegisterGlobal(arguments[0], pid) { return vm.ExternalCallReturned(term.MustAtom("yes")) }; return vm.ExternalCallReturned(term.MustAtom("no")) } }
	if target.Module == "global" && target.Function == "unregister_name" && target.Arity == 1 { context.UnregisterGlobal(arguments[0]); return vm.ExternalCallReturned(term.MustAtom("ok")) }
	if target.Module == "global" && target.Function == "whereis_name" && target.Arity == 1 { match context.WhereisGlobal(arguments[0]) { case option.None: return vm.ExternalCallReturned(term.MustAtom("undefined")); case option.Some(pid): return vm.ExternalCallReturned(term.PIDValue(pid)) } }
	if target.Module == "global" && target.Function == "send" && target.Arity == 2 { match context.WhereisGlobal(arguments[0]) { case option.None: return vm.ExternalCallRaised(term.MustAtom("exit"), term.Tuple(term.MustAtom("badarg"), term.Tuple(arguments[0].Clone(), arguments[1].Clone()))); case option.Some(pid): context.Send(pid, arguments[1]); return vm.ExternalCallReturned(term.PIDValue(pid)) } }
	if target.Module == "erlang" && target.Function == "alias" && target.Arity == 0 {
		match context.Alias() {
		case result.Err(failure):
			return vm.ExternalCallRejected(failure.Error())
		case result.Ok(reference):
			return vm.ExternalCallReturned(term.ReferenceValue(reference))
		}
	}
	if target.Module == "erlang" && target.Function == "unalias" && target.Arity == 1 {
		match term.TermReferenceValue(arguments[0]) {
		case option.None:
			return vm.ExternalCallRaised(term.MustAtom("error"), term.MustAtom("badarg"))
		case option.Some(reference):
			context.Unalias(reference)
			return vm.ExternalCallReturned(term.MustAtom("true"))
		}
	}
	if target.Module == "erlang" && target.Function == "start_timer" && target.Arity == 3 { return process.otpContextStartTimer(context, arguments) }
	if target.Module == "erlang" && target.Function == "cancel_timer" && target.Arity == 1 { match term.TermReferenceValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(reference): if context.CancelMessageTimer(reference) { return vm.ExternalCallReturned(term.Integer(1)) }; return vm.ExternalCallReturned(term.MustAtom("false")) } }
	return process.callRegistry.Call(target, arguments)
}

func (process *VMProcess) otpMonotonicTime(arguments []term.Term) vm.ExternalCallOutcome {
	unit := "native"
	if len(arguments) == 1 { match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(found): unit = found } }
	nanoseconds := process.clock.Now().UnixNano()
	switch unit {
	case "native", "nanosecond": return vm.ExternalCallReturned(term.Integer(nanoseconds))
	case "microsecond": return vm.ExternalCallReturned(term.Integer(nanoseconds / int64(time.Microsecond)))
	case "millisecond": return vm.ExternalCallReturned(term.Integer(nanoseconds / int64(time.Millisecond)))
	case "second": return vm.ExternalCallReturned(term.Integer(nanoseconds / int64(time.Second)))
	default: return otpBadarg()
	}
}

func otpContextSend(context *kernel.Context, arguments []term.Term, options bool) vm.ExternalCallOutcome {
	delivered := kernel.Delivery(kernel.NoProcess())
	match term.TermPIDValue(arguments[0]) { case option.Some(pid): delivered = context.Send(pid, arguments[1]); case option.None: match term.TermReferenceValue(arguments[0]) { case option.Some(reference): delivered = context.SendAlias(reference, arguments[1]); case option.None: match term.AtomName(arguments[0]) { case option.Some(name): delivered = context.SendRegistered(name, arguments[1]); case option.None: match arguments[0] { case term.TupleTerm(parts): if len(parts) != 2 { return otpBadarg() }; var name, node string; match term.AtomName(parts[0]) { case option.None: return otpBadarg(); case option.Some(value): name = value }; match term.AtomName(parts[1]) { case option.None: return otpBadarg(); case option.Some(value): node = value }; delivered = context.SendRemoteRegistered(node, name, arguments[1]); case _: return otpBadarg() } } } }
	match delivered { case kernel.Delivered, kernel.NoProcess: if options { return vm.ExternalCallReturned(term.MustAtom("ok")) }; return vm.ExternalCallReturned(term.Clone(arguments[1])) }
}

func (process *VMProcess) otpContextStartTimer(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	var milliseconds int64
	match term.IntegerValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): if !value.IsInt64() { return otpBadarg() }; milliseconds = value.Int64(); if milliseconds < 0 { return otpBadarg() } }
	match context.StartMessageTimer(process.clock, arguments[1], arguments[2], time.Duration(milliseconds)*time.Millisecond) {
	case result.Err(_): return otpBadarg()
	case result.Ok(reference): return vm.ExternalCallReturned(term.ReferenceValue(reference))
	}
}

func (process *VMProcess) otpContextSpawn(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	if process.spawnMFA == nil { return vm.ExternalCallRejected("MFA spawning is unavailable") }
	var module, function string
	match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): module = value }
	match term.AtomName(arguments[1]) { case option.None: return otpBadarg(); case option.Some(value): function = value }
	var callArguments, options []term.Term
	match arguments[2] { case term.ProperListTerm(values): callArguments = values; case _: return otpBadarg() }
	match arguments[3] { case term.ProperListTerm(values): options = values; case _: return otpBadarg() }
	link, monitor := false, false
	for _, value := range options { match term.AtomName(value) { case option.Some(name): switch name { case "link": link = true; case "monitor": monitor = true }; case option.None: } }
	return process.spawnMFA(context, module, function, callArguments, link, monitor)
}

func (process *VMProcess) otpContextSpawnMonitor(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	if process.spawnMFA == nil { return vm.ExternalCallRejected("MFA spawning is unavailable") }
	var module, function string
	match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): module = value }
	match term.AtomName(arguments[1]) { case option.None: return otpBadarg(); case option.Some(value): function = value }
	var callArguments []term.Term
	match arguments[2] { case term.ProperListTerm(values): callArguments = values; case _: return otpBadarg() }
	return process.spawnMFA(context, module, function, callArguments, false, true)
}

func otpContextMonitor(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	match term.AtomName(arguments[0]) { case option.Some(kind): if kind != "process" { return otpBadarg() }; case option.None: return otpBadarg() }
	aliasOnDemonitor := false
	tag := term.Term(term.MustAtom("DOWN"))
	if len(arguments) == 3 {
		var options []term.Term
		match arguments[2] { case term.ProperListTerm(values): options = values; case _: return otpBadarg() }
		for _, value := range options {
			match value {
			case term.TupleTerm(elements):
				if len(elements) != 2 { return otpBadarg() }
				var name string
				match term.AtomName(elements[0]) { case option.None: return otpBadarg(); case option.Some(found): name = found }
				switch name {
				case "alias": match term.AtomName(elements[1]) { case option.Some(mode): if mode != "demonitor" { return otpBadarg() }; aliasOnDemonitor = true; case option.None: return otpBadarg() }
				case "tag": tag = elements[1].Clone()
				default: return otpBadarg()
				}
			case _: return otpBadarg()
			}
		}
	}
	match term.TermPIDValue(arguments[1]) { case option.Some(pid): if aliasOnDemonitor { monitored := context.MonitorAliasResult(pid); if !monitored.Accepted { return vm.ExternalCallRejected(monitored.Detail) }; return vm.ExternalCallReturned(term.ReferenceValue(monitored.Reference)) }; match context.MonitorTagged(pid, tag) { case result.Err(failure): return vm.ExternalCallRejected(failure.Error()); case result.Ok(reference): return vm.ExternalCallReturned(term.ReferenceValue(reference)) }; case option.None: }
	match arguments[1] { case term.TupleTerm(parts): if len(parts) != 2 || aliasOnDemonitor { return otpBadarg() }; var name, node string; match term.AtomName(parts[0]) { case option.None: return otpBadarg(); case option.Some(value): name = value }; match term.AtomName(parts[1]) { case option.None: return otpBadarg(); case option.Some(value): node = value }; match context.MonitorTaggedName(node, name, tag) { case result.Err(failure): return vm.ExternalCallRejected(failure.Error()); case result.Ok(reference): return vm.ExternalCallReturned(term.ReferenceValue(reference)) }; case _: return otpBadarg() }
}

func otpContextDemonitor(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	match term.TermReferenceValue(arguments[0]) { case option.None: return otpBadarg(); case option.Some(reference): context.Demonitor(reference, true); return vm.ExternalCallReturned(term.MustAtom("true")) }
}

func otpContextRegister(context *kernel.Context, arguments []term.Term) vm.ExternalCallOutcome {
	var name string
	match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(value): name = value }
	match term.TermPIDValue(arguments[1]) { case option.None: return otpBadarg(); case option.Some(pid): match context.Register(name, pid) { case result.Err(_): return otpBadarg(); case result.Ok(_): return vm.ExternalCallReturned(term.MustAtom("true")) } }
}

package erts

import (
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func decodeModuleMetadata(module *beam.Module) map[string]term.Term {
	metadata := map[string]term.Term{}
	metadata["module"] = term.MustAtom(module.Name)
	exports := make([]term.Term, len(module.Exports))
	for index, exported := range module.Exports {
		exports[index] = term.Tuple(term.MustAtom(exported.Function), term.Integer(int64(exported.Arity)))
	}
	metadata["exports"] = term.List(exports...)
	codec := etf.CanonicalCodec{}
	for chunk, key := range map[string]string{"Attr": "attributes", "CInf": "compile"} {
		match module.Chunk(chunk) {
		case option.None:
		case option.Some(encoded):
			match codec.Decode(encoded) { case result.Err(_): case result.Ok(value): metadata[key] = value }
		}
	}
	match defaultModuleMD5(metadata["attributes"]) {
	case option.None:
	case option.Some(value): metadata["md5"] = term.Binary(value)
	}
	return metadata
}

func defaultModuleMD5(attributes term.Term) option.Option[[]byte] {
	match attributes {
	case term.ProperListTerm(values):
		for _, value := range values {
			match value {
			case term.TupleTerm(fields):
				if len(fields) != 2 { continue }
				match fields[0] {
				case term.AtomTerm(name):
					if name != "vsn" { continue }
					match fields[1] {
					case term.ProperListTerm(versions):
						if len(versions) != 1 { return option.None[[]byte]() }
						match term.IntegerValue(versions[0]) {
						case option.None: return option.None[[]byte]()
						case option.Some(integer):
							if integer.Sign() < 0 || integer.BitLen() > 128 { return option.None[[]byte]() }
							digest := make([]byte, 16)
							integer.FillBytes(digest)
							return option.Some(digest)
						}
					case _: return option.None[[]byte]()
					}
				case _:
				}
			case _:
			}
		}
	case _:
	}
	return option.None[[]byte]()
}

func registryWithModuleInfo(registry *CallRegistry, modules map[string]*LoadedModule) *CallRegistry {
	implementations := map[vm.ExternalFunction]ExternalImplementation{}
	if registry != nil { for target, implementation := range registry.implementations { implementations[target] = implementation } }
	implementations[vm.ExternalFunction{Module: "erlang", Function: "get_module_info", Arity: 1}] = func(arguments []term.Term) vm.ExternalCallOutcome { return otpGetModuleInfo(modules, arguments, option.None[string]()) }
	implementations[vm.ExternalFunction{Module: "erlang", Function: "get_module_info", Arity: 2}] = func(arguments []term.Term) vm.ExternalCallOutcome {
		match term.AtomName(arguments[1]) { case option.None: return otpBadarg(); case option.Some(key): return otpGetModuleInfo(modules, arguments, option.Some(key)) }
	}
	return &CallRegistry{implementations: implementations}
}

func otpGetModuleInfo(modules map[string]*LoadedModule, arguments []term.Term, requested option.Option[string]) vm.ExternalCallOutcome {
	var name string
	match term.AtomName(arguments[0]) { case option.None: return otpBadarg(); case option.Some(found): name = found }
	module, present := modules[name]
	match option.Of(module, present) {
	case option.None: return otpBadarg()
	case option.Some(found):
		match requested {
		case option.Some(key):
			value, exists := found.metadata[key]
			match option.Of(value, exists) { case option.None: return otpBadarg(); case option.Some(info): return vm.ExternalCallReturned(info) }
		case option.None:
			keys := []string{"module", "exports", "attributes", "compile", "md5"}
			values := make([]term.Term, 0, len(keys))
			for _, key := range keys {
				value, exists := found.metadata[key]
				if exists { values = append(values, term.Tuple(term.MustAtom(key), value)) }
			}
			return vm.ExternalCallReturned(term.List(values...))
		}
	}
}

package vm

import (
	"fmt"

	"goforge.dev/goplus/std/memory"
)

type Failure enum {
	InvalidConfiguration(Detail string)
	ImmediateOutOfRange(Value int64)
	HeapIndexOutOfRange(Index int, Words int)
	MemoryFailure(Cause memory.Failure)
	InvalidProgram(Detail string)
	RegisterOutOfRange(Register string, Index int)
	UninitializedRegister(Register string, Index int)
	MissingConstant(Kind string, Index uint64)
	MissingLabel(Label uint64)
	StepLimitExceeded(Limit int)
	UnsupportedOpcode(Name string, Arity int, Offset int)
}

func (failure Failure) Error() string {
	match failure {
	case InvalidConfiguration(detail):
		return "gotp/vm: invalid configuration: " + detail
	case ImmediateOutOfRange(value):
		return fmt.Sprintf("gotp/vm: integer %d does not fit an immediate word", value)
	case HeapIndexOutOfRange(index, words):
		return fmt.Sprintf("gotp/vm: heap word index %d is outside %d words", index, words)
	case MemoryFailure(cause):
		return "gotp/vm: arena: " + cause.Error()
	case InvalidProgram(detail):
		return "gotp/vm: invalid program: " + detail
	case RegisterOutOfRange(register, index):
		return fmt.Sprintf("gotp/vm: %s register %d is out of range", register, index)
	case UninitializedRegister(register, index):
		return fmt.Sprintf("gotp/vm: %s register %d is uninitialized", register, index)
	case MissingConstant(kind, index):
		return fmt.Sprintf("gotp/vm: %s constant %d is unavailable", kind, index)
	case MissingLabel(label):
		return fmt.Sprintf("gotp/vm: label %d does not exist", label)
	case StepLimitExceeded(limit):
		return fmt.Sprintf("gotp/vm: step limit %d exceeded", limit)
	case UnsupportedOpcode(name, arity, offset):
		return fmt.Sprintf(
			"gotp/vm: opcode %s/%d at byte %d is not implemented by the reference interpreter",
			name,
			arity,
			offset,
		)
	}
}

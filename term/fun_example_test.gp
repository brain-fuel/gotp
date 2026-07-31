package term

import (
	"testing"

	"goforge.dev/goplus/std/option"
)

// assayxport:law gotp.term.fun-laws
func TestFunEnvironmentIsImmutable(t *testing.T) {
	environment := []Term{List(Integer(1))}
	value := Function(Fun{Form: LocalClosure(), Module: "demo", Function: "captured", Arity: 1, Label: 2, Index: 3, Unique: 4, Environment: environment})
	environment[0] = MustAtom("mutated")
	match value.FunValue() {
	case option.None:
		t.Fatal("function projection failed")
	case option.Some(function):
		if !Equal(function.Environment[0], List(Integer(1))) {
			t.Fatalf("captured environment = %v", function.Environment)
		}
		function.Environment[0] = MustAtom("projected")
		if !Equal(value, value.Clone()) {
			t.Fatal("function clone differs from source")
		}
	}
}

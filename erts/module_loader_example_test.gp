package erts

import (
	"encoding/binary"
	"fmt"
	"math/big"
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/clock"
	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

func loaderChunk(id string, data []byte) []byte {
	out := make([]byte, 8+((len(data)+3)&^3))
	copy(out[:4], id)
	binary.BigEndian.PutUint32(out[4:8], uint32(len(data)))
	copy(out[8:], data)
	return out
}

func loaderTableAtoms(values ...string) []byte {
	out := make([]byte, 4)
	binary.BigEndian.PutUint32(out, uint32(len(values)))
	for _, value := range values {
		out = append(out, byte(len(value)))
		out = append(out, value...)
	}
	return out
}

func loaderTableWords(rows ...[]uint32) []byte {
	out := make([]byte, 4)
	binary.BigEndian.PutUint32(out, uint32(len(rows)))
	for _, row := range rows {
		for _, value := range row {
			var raw [4]byte
			binary.BigEndian.PutUint32(raw[:], value)
			out = append(out, raw[:]...)
		}
	}
	return out
}

func loaderModuleBytes(chunks ...[]byte) []byte {
	size := 4
	for _, chunk := range chunks {
		size += len(chunk)
	}
	out := make([]byte, 8, 8+size)
	copy(out[:4], "FOR1")
	binary.BigEndian.PutUint32(out[4:8], uint32(size))
	out = append(out, []byte("BEAM")...)
	for _, chunk := range chunks {
		out = append(out, chunk...)
	}
	return out
}

func executableModuleBytes() []byte {
	code := []byte{
		1, 0x15,
		2, 0x12, 0x22, 0x00,
		64, 0x71, 0x03,
		19,
		3,
	}
	chunk := make([]byte, 20+len(code))
	binary.BigEndian.PutUint32(chunk[0:4], 16)
	binary.BigEndian.PutUint32(chunk[4:8], 0)
	binary.BigEndian.PutUint32(chunk[8:12], 191)
	binary.BigEndian.PutUint32(chunk[12:16], 1)
	binary.BigEndian.PutUint32(chunk[16:20], 1)
	copy(chunk[20:], code)
	return loaderModuleBytes(
		loaderChunk("AtU8", loaderTableAtoms("demo", "main")),
		loaderChunk("Code", chunk),
		loaderChunk("ImpT", loaderTableWords()),
		loaderChunk("ExpT", loaderTableWords([]uint32{2, 0, 1})),
	)
}

func literalExecutableModuleBytes() []byte {
	code := []byte{
		1, 0x15,
		2, 0x12, 0x22, 0x00,
		64, 0x47, 0x00, 0x03,
		19,
		3,
	}
	codeChunk := make([]byte, 20+len(code))
	binary.BigEndian.PutUint32(codeChunk[0:4], 16)
	binary.BigEndian.PutUint32(codeChunk[4:8], 0)
	binary.BigEndian.PutUint32(codeChunk[8:12], 191)
	binary.BigEndian.PutUint32(codeChunk[12:16], 1)
	binary.BigEndian.PutUint32(codeChunk[16:20], 1)
	copy(codeChunk[20:], code)
	value := term.Tuple(term.MustAtom("literal"), term.Integer(99))
	var encoded []byte
	codec := etf.CanonicalCodec{}
	match codec.Encode(value) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(data):
		encoded = data
	}
	literals := make([]byte, 12, 12+len(encoded))
	binary.BigEndian.PutUint32(literals[4:8], 1)
	binary.BigEndian.PutUint32(literals[8:12], uint32(len(encoded)))
	literals = append(literals, encoded...)
	return loaderModuleBytes(
		loaderChunk("AtU8", loaderTableAtoms("literal_demo", "main")),
		loaderChunk("Code", codeChunk),
		loaderChunk("ImpT", loaderTableWords()),
		loaderChunk("ExpT", loaderTableWords([]uint32{2, 0, 1})),
		loaderChunk("LitT", literals),
	)
}

// ExampleLoadedModule_NewProcess is the executable module-loading example.
func ExampleLoadedModule_NewProcess() {
	match DecodeModule(executableModuleBytes(), ModuleLoaderConfig{}) {
	case result.Err(failure):
		panic(failure.Error())
	case result.Ok(module):
		fmt.Println(module.Name())
		match module.NewProcess("main", 0, clock.Real{}) {
		case result.Err(failure):
			panic(failure.Error())
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				panic(failure.Error())
			case result.Ok(_):
			}
			runtime.Run(10)
			var state VMProcessState = process.State()
			match state {
			case VMProcessCompleted(value, _, _):
				match term.IntegerValue(value) {
				case option.None:
					panic("expected integer")
				case option.Some(integer):
					fmt.Println(integer)
				}
			case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
				panic("process did not complete")
			}
		}
	}
	// Output:
	// demo
	// 7
}

// assayxport:law gotp.erts.module-loader-laws
func TestModuleDecoderNeverPanics(t *testing.T) {
	law := func(data []byte) bool {
		_ = DecodeModule(data, ModuleLoaderConfig{
			CodeLimits: beam.CodeDecodeLimits{
				MaxInstructions: 64,
				MaxOperandDepth: 16,
				MaxListItems: 64,
				MaxIntegerBytes: 32,
			},
		})
		return true
	}
	match result.Of(true, quick.Check(law, &quick.Config{MaxCount: 1_000})) {
	case result.Err(cause):
		t.Fatal(cause)
	case result.Ok(_):
	}
}

func TestLoadedModuleCreatesIsolatedMachines(t *testing.T) {
	match DecodeModule(executableModuleBytes(), ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		var left *vm.Machine
		var right *vm.Machine
		match module.NewMachine() {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(machine):
			left = machine
		}
		match module.NewMachine() {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(machine):
			right = machine
		}
		if left == right {
			t.Fatal("loaded module reused mutable machine state")
		}
	}
}

func TestPinnedOTPModuleLoadsAndResolvesExport(t *testing.T) {
	match LoadModuleFile(
		beam.OperatingSystemFiles(),
		"../beam/testdata/otp-29.0.4/lists.beam",
		ModuleLoaderConfig{},
	) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		if module.Name() != "lists" {
			t.Fatalf("module name = %q", module.Name())
		}
		if module.LiteralCount() == 0 {
			t.Fatal("pinned OTP lists module has no decoded literals")
		}
		match module.Entry("reverse", 1) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(label):
			if label == 0 {
				t.Fatal("reverse/1 resolved to label zero")
			}
		}
		match module.NewMachine() {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(_):
		}
	}
}

func TestLoadedLiteralExecutesAsRuntimeTerm(t *testing.T) {
	match DecodeModule(literalExecutableModuleBytes(), ModuleLoaderConfig{}) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(module):
		if module.LiteralCount() != 1 {
			t.Fatalf("literal count = %d", module.LiteralCount())
		}
		match module.NewProcess("main", 0, clock.Real{}) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(process):
			runtime := kernel.New(kernel.KernelConfig{})
			match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
			case result.Err(failure):
				t.Fatal(failure)
			case result.Ok(_):
			}
			runtime.Run(10)
			var state VMProcessState = process.State()
			match state {
			case VMProcessCompleted(value, _, _):
				want := term.Tuple(term.MustAtom("literal"), term.Integer(99))
				if !term.Equal(value, want) {
					t.Fatalf("literal value = %v", value)
				}
			case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
				t.Fatalf("literal process state = %T", state)
			}
		}
	}
}

// assayxport:law gotp.erts.pinned-lists-execution-laws
func TestPinnedOTPListsReverseFastPath(t *testing.T) {
	var module *LoadedModule
	match LoadModuleFile(
		beam.OperatingSystemFiles(),
		"../beam/testdata/otp-29.0.4/lists.beam",
		ModuleLoaderConfig{},
	) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(loaded):
		module = loaded
	}
	var machine *vm.Machine
	match module.NewMachine() {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		machine = created
	}
	match machine.SetX(0, term.List(term.Integer(1), term.Integer(2))) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(_):
	}
	var entry uint64
	match module.Entry("reverse", 1) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(label):
		entry = label
	}
	var registry *CallRegistry
	match NewCallRegistry(nil) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(created):
		registry = created
	}
	match NewVMProcessWithRegistry(machine, entry, clock.Real{}, registry) {
	case result.Err(failure):
		t.Fatal(failure)
	case result.Ok(process):
		runtime := kernel.New(kernel.KernelConfig{})
		match runtime.Spawn(process.Behavior(), kernel.Unlinked(false)) {
		case result.Err(failure):
			t.Fatal(failure)
		case result.Ok(_):
		}
		runtime.Run(100)
		var state VMProcessState = process.State()
		match state {
		case VMProcessCompleted(value, reductions, instructions):
			want := term.List(term.Integer(2), term.Integer(1))
			if !term.Equal(value, want) || reductions != 1 || instructions != 9 {
				t.Fatalf("reverse = %v, reductions = %d, instructions = %d", value, reductions, instructions)
			}
		case VMProcessRunning, VMProcessSuspended(_, _), VMProcessWaiting(_, _), VMProcessRaised(_, _, _, _), VMProcessFailed(_, _, _):
			t.Fatalf("reverse state = %T", state)
		}
	}
}

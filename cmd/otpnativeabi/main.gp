package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"goforge.dev/goplus/std/process"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

var sourcePaths = []string{
	"erts/emulator/beam/erl_driver.h",
	"erts/emulator/beam/erl_drv_nif.h",
	"erts/emulator/beam/erl_nif.h",
	"erts/emulator/beam/erl_nif_api_funcs.h",
	"erts/include/erl_int_sizes_config.h.in",
	"erts/emulator/sys/win32/erl_win_dyn_driver.h",
	"lib/erl_interface/include/ei.h",
	"lib/erl_interface/include/ei_connect.h",
}

func main() {
	if len(os.Args) != 5 { fmt.Fprintln(os.Stderr, "usage: otpnativeabi COMPILER OTP_SOURCE_ROOT WORK_PARENT PROFILE"); os.Exit(2) }
	match result.Of(true, os.MkdirAll(os.Args[3], 0o755)) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(_):
	}
	temporary, temporaryError := os.MkdirTemp(os.Args[3], "otpnativeabi-")
	match result.Of(temporary, temporaryError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(temporary): build(temporary)
	}
}

type commandProfile enum {
	DarwinARM64()
	LinuxAMD64()
	LinuxARM64()
	WindowsAMD64()
}

func build(temporary string) {
	defer os.RemoveAll(temporary)
	var selected commandProfile
	match parseProfile(os.Args[4]) {
	case result.Err(detail): fail(detail)
	case result.Ok(profile): selected = profile
	}
	longSize := 8
	match selected { case DarwinARM64: case LinuxAMD64: case LinuxARM64: case WindowsAMD64: longSize = 4 }
	configuration := fmt.Sprintf("#define SIZEOF_CHAR 1\n#define SIZEOF_SHORT 2\n#define SIZEOF_INT 4\n#define SIZEOF_LONG %d\n#define SIZEOF_LONG_LONG 8\n#define SIZEOF_VOID_P 8\n", longSize)
	match result.Of(true, os.WriteFile(filepath.Join(temporary, "erl_int_sizes_config.h"), []byte(configuration), 0o644)) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(_):
	}
	versionOutput, versionError := process.Run(context.Background(), process.Spec{Path: os.Args[1], Args: versionArguments(selected)})
	match result.Of(versionOutput, versionError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(output):
		compiler := compilerIdentity(selected, strings.Split(strings.TrimSpace(string(append(output.Stdout, output.Stderr...))), "\n")[0])
		sources := readSources()
		units := []compat.ClangASTUnit{
			clangAST(selected, temporary, "nif", "erts/emulator/beam/erl_nif.h", []string{"erts/emulator/beam/erl_nif.h", "erts/emulator/beam/erl_nif_api_funcs.h", "erts/emulator/beam/erl_drv_nif.h"}),
			clangAST(selected, temporary, "driver", "erts/emulator/beam/erl_driver.h", []string{"erts/emulator/beam/erl_driver.h", "erts/emulator/beam/erl_drv_nif.h", "erts/emulator/sys/win32/erl_win_dyn_driver.h"}),
			clangAST(selected, temporary, "ei", "lib/erl_interface/include/ei.h", []string{"lib/erl_interface/include/ei.h"}),
		}
		match compat.BuildOTPNativeABIInventory(os.Args[4], compiler, sources, units) {
		case result.Err(failure): fail(failure.Error())
		case result.Ok(inventory): emit(inventory)
		}
	}
}

func readSources() []compat.OTPNativeABISource {
	sources := []compat.OTPNativeABISource{}
	for _, sourcePath := range sourcePaths {
		content, readError := os.ReadFile(filepath.Join(os.Args[2], filepath.FromSlash(sourcePath)))
		match result.Of(content, readError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(content): sources = append(sources, compat.OTPNativeABISource{SourcePath: sourcePath, Content: content})
		}
	}
	return sources
}

func clangAST(profile commandProfile, configuration string, surface string, mainPath string, ownedPaths []string) compat.ClangASTUnit {
	arguments := compilerPrefix(profile)
	match profile {
	case DarwinARM64: arguments = append(arguments, "-Xclang", "-ast-dump=json", "-fsyntax-only")
	case LinuxAMD64: arguments = append(arguments, "-ast-dump=json")
	case LinuxARM64: arguments = append(arguments, "-ast-dump=json")
	case WindowsAMD64: arguments = append(arguments, "-ast-dump=json")
	}
	arguments = append(arguments, "-x", "c",
		"-I" + configuration,
		"-I" + filepath.Join(os.Args[2], "erts/emulator/beam"),
		"-I" + filepath.Join(os.Args[2], "erts/include"),
		"-I" + filepath.Join(os.Args[2], "erts/include/internal"),
		"-I" + filepath.Join(os.Args[2], "erts/emulator/sys/win32"),
		"-I" + filepath.Join(os.Args[2], "lib/erl_interface/include"),
		filepath.Join(os.Args[2], filepath.FromSlash(mainPath)),
	)
	output, runError := process.Run(context.Background(), process.Spec{Path: os.Args[1], Args: arguments})
	match result.Of(output, runError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(output): return compat.ClangASTUnit{Surface: surface, MainPath: mainPath, OwnedPaths: ownedPaths, JSON: output.Stdout}
	}
	panic("unreachable")
}

func emit(inventory compat.OTPNativeABIInventory) {
	encoded, encodeError := json.MarshalIndent(inventory, "", "  ")
	match result.Of(encoded, encodeError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(output):
		output = append(output, '\n')
		written, writeError := os.Stdout.Write(output)
		match result.Of(written, writeError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(_):
		}
	}
}

func fail(detail string) { fmt.Fprintln(os.Stderr, detail); os.Exit(1) }

func parseProfile(name string) result.Result[commandProfile, string] {
	switch name {
	case "darwin-arm64-lp64": return result.Ok[commandProfile, string](DarwinARM64())
	case "linux-amd64-lp64": return result.Ok[commandProfile, string](LinuxAMD64())
	case "linux-arm64-lp64": return result.Ok[commandProfile, string](LinuxARM64())
	case "windows-amd64-llp64": return result.Ok[commandProfile, string](WindowsAMD64())
	default: return result.Err[commandProfile, string]("unknown native ABI profile " + name)
	}
}

func compilerPrefix(profile commandProfile) []string {
	zigLibrary := filepath.Join(filepath.Dir(os.Args[1]), "lib")
	match profile {
	case DarwinARM64: return []string{}
	case LinuxAMD64: return []string{"-cc1", "-triple", "x86_64-unknown-linux5.10.0-gnu2.31.0", "-nostdsysteminc", "-nobuiltininc", "-resource-dir", filepath.Join(zigLibrary, "clang/21"), "-isystem", filepath.Join(zigLibrary, "include"), "-isystem", filepath.Join(zigLibrary, "libc/include/x86-linux-gnu"), "-isystem", filepath.Join(zigLibrary, "libc/include/generic-glibc"), "-isystem", filepath.Join(zigLibrary, "libc/include/x86-linux-any"), "-isystem", filepath.Join(zigLibrary, "libc/include/any-linux-any"), "-D__GLIBC_MINOR__=31"}
	case LinuxARM64: return []string{"-cc1", "-triple", "aarch64-unknown-linux5.10.0-gnu2.31.0", "-nostdsysteminc", "-nobuiltininc", "-resource-dir", filepath.Join(zigLibrary, "clang/21"), "-isystem", filepath.Join(zigLibrary, "include"), "-isystem", filepath.Join(zigLibrary, "libc/include/aarch64-linux-gnu"), "-isystem", filepath.Join(zigLibrary, "libc/include/generic-glibc"), "-isystem", filepath.Join(zigLibrary, "libc/include/aarch64-linux-any"), "-isystem", filepath.Join(zigLibrary, "libc/include/any-linux-any"), "-D__GLIBC_MINOR__=31"}
	case WindowsAMD64: return []string{"-cc1", "-triple", "x86_64-unknown-windows-gnu", "-fms-extensions", "-fms-compatibility", "-fgnuc-version=4.2.1", "-nostdsysteminc", "-nobuiltininc", "-resource-dir", filepath.Join(zigLibrary, "clang/21"), "-isystem", filepath.Join(zigLibrary, "include"), "-isystem", filepath.Join(zigLibrary, "libc/include/x86_64-windows-gnu"), "-isystem", filepath.Join(zigLibrary, "libc/include/generic-mingw"), "-isystem", filepath.Join(zigLibrary, "libc/include/x86_64-windows-any"), "-isystem", filepath.Join(zigLibrary, "libc/include/any-windows-any"), "-D__MSVCRT_VERSION__=0xE00", "-D_WIN32_WINNT=0x0a00", "-Wno-pragma-pack"}
	}
}

func versionArguments(profile commandProfile) []string {
	match profile {
	case DarwinARM64: return []string{"--version"}
	case LinuxAMD64: return []string{"version"}
	case LinuxARM64: return []string{"version"}
	case WindowsAMD64: return []string{"version"}
	}
}

func compilerIdentity(profile commandProfile, version string) string {
	match profile {
	case DarwinARM64: return version
	case LinuxAMD64: return "zig " + version
	case LinuxARM64: return "zig " + version
	case WindowsAMD64: return "zig " + version
	}
}

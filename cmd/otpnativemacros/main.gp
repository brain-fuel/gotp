package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

type headerSpec struct { Surface string; Path string }

var publicHeaders = []headerSpec{
	{Surface: "driver", Path: "erts/emulator/beam/erl_driver.h"},
	{Surface: "shared", Path: "erts/emulator/beam/erl_drv_nif.h"},
	{Surface: "nif", Path: "erts/emulator/beam/erl_nif.h"},
	{Surface: "nif", Path: "erts/emulator/beam/erl_nif_api_funcs.h"},
	{Surface: "config", Path: "erts/include/erl_int_sizes_config.h.in"},
	{Surface: "driver-windows", Path: "erts/emulator/sys/win32/erl_win_dyn_driver.h"},
	{Surface: "ei", Path: "lib/erl_interface/include/ei.h"},
	{Surface: "ei", Path: "lib/erl_interface/include/ei_connect.h"},
}

func main() {
	if len(os.Args) != 4 { fmt.Fprintln(os.Stderr, "usage: otpnativemacros PROFILE OTP_SOURCE_ROOT ACTIVE_MACRO_DUMP"); os.Exit(2) }
	dump, readError := os.ReadFile(os.Args[3])
	match result.Of(dump, readError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(dump): build(string(dump))
	}
}

func build(dump string) {
	headers := []compat.OTPNativeHeader{}
	for _, spec := range publicHeaders {
		content, readError := os.ReadFile(filepath.Join(os.Args[2], filepath.FromSlash(spec.Path)))
		match result.Of(content, readError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(content): headers = append(headers, compat.OTPNativeHeader{Surface: spec.Surface, SourcePath: spec.Path, Content: string(content)})
		}
	}
	match compat.BuildOTPNativeMacroInventory(os.Args[1], headers, dump) {
	case result.Err(failure): fail(failure.Error())
	case result.Ok(inventory):
		encoded, encodeError := json.MarshalIndent(inventory, "", "  ")
		match result.Of(encoded, encodeError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(output):
			written, writeError := os.Stdout.Write(append(output, '\n'))
			match result.Of(written, writeError) {
			case result.Err(cause): fail(cause.Error())
			case result.Ok(_):
			}
		}
	}
}

func fail(detail string) { fmt.Fprintln(os.Stderr, detail); os.Exit(1) }

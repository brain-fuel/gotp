package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

func main() {
	if len(os.Args) != 3 { fmt.Fprintln(os.Stderr, "usage: otpnativeentries OTP_SOURCE_ROOT OTP_INVENTORY.json"); os.Exit(2) }
	data, readError := os.ReadFile(os.Args[2])
	match result.Of(data, readError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(data):
		match compat.ParseOTPInventory(data) {
		case result.Err(failure): fail(failure.Error())
		case result.Ok(inventory): build(inventory)
		}
	}
}

func build(inventory compat.OTPInventory) {
	sources := []compat.OTPNativeSource{}
	for _, unit := range inventory.SourceUnits {
		if unit.Kind != "native" { continue }
		content, readError := os.ReadFile(filepath.Join(os.Args[1], filepath.FromSlash(unit.SourcePath)))
		match result.Of(content, readError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(content): sources = append(sources, compat.OTPNativeSource{Application: unit.Application, SourcePath: unit.SourcePath, Content: string(content)})
		}
	}
	match compat.BuildOTPNativeEntryInventory(sources) {
	case result.Err(failure): fail(failure.Error())
	case result.Ok(inventory):
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
}

func fail(detail string) { fmt.Fprintln(os.Stderr, detail); os.Exit(1) }

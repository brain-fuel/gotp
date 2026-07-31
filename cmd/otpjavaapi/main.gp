package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"goforge.dev/goplus/std/process"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

func main() {
	if len(os.Args) != 5 { fmt.Fprintln(os.Stderr, "usage: otpjavaapi JAVAC OTP_SOURCE_ROOT OTP_INVENTORY.json CLASS_OUTPUT_DIR"); os.Exit(2) }
	data, readError := os.ReadFile(os.Args[3])
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
	match result.Of(true, os.MkdirAll(os.Args[4], 0o755)) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(_):
	}
	outputDirectory, temporaryError := os.MkdirTemp(os.Args[4], "otpjavaapi-")
	match result.Of(outputDirectory, temporaryError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(outputDirectory): compile(inventory, outputDirectory)
	}
}

func compile(inventory compat.OTPInventory, outputDirectory string) {
	defer os.RemoveAll(outputDirectory)
	sources := []compat.OTPJavaSource{}
	arguments := []string{"-g:none", "-d", outputDirectory}
	for _, unit := range inventory.SourceUnits {
		if unit.Kind != "java" { continue }
		path := filepath.Join(os.Args[2], filepath.FromSlash(unit.SourcePath))
		content, readError := os.ReadFile(path)
		match result.Of(content, readError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(content):
			sources = append(sources, compat.OTPJavaSource{SourcePath: unit.SourcePath, Content: content})
			arguments = append(arguments, path)
		}
	}
	versionOutput, versionError := process.Run(context.Background(), process.Spec{Path: os.Args[1], Args: []string{"-version"}, Clean: false})
	match result.Of(versionOutput, versionError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(output):
		compiler := strings.TrimSpace(string(append(output.Stdout, output.Stderr...)))
		compileOutput, compileError := process.Run(context.Background(), process.Spec{Path: os.Args[1], Args: arguments, Clean: false})
		match result.Of(compileOutput, compileError) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(_): emit(compiler, sources, outputDirectory)
		}
	}
}

func emit(compiler string, sources []compat.OTPJavaSource, outputDirectory string) {
	classes := []compat.OTPJavaClass{}
	walkError := filepath.WalkDir(outputDirectory, func(path string, entry fs.DirEntry, cause error) error {
		match result.Of(true, cause) {
		case result.Err(cause): return cause
		case result.Ok(_):
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".class") { return nil }
		content, readError := os.ReadFile(path)
		match result.Of(content, readError) {
		case result.Err(cause): return cause
		case result.Ok(content):
			relative, relativeError := filepath.Rel(outputDirectory, path)
			match result.Of(relative, relativeError) {
			case result.Err(cause): return cause
			case result.Ok(relative): classes = append(classes, compat.OTPJavaClass{ClassPath: filepath.ToSlash(relative), Content: content})
			}
		}
		return nil
	})
	match result.Of(true, walkError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(_):
		match compat.BuildOTPJavaAPIInventory(compiler, sources, classes) {
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
}

func fail(detail string) { fmt.Fprintln(os.Stderr, detail); os.Exit(1) }

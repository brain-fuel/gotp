package main

import (
	"encoding/json"
	"fmt"
	"os"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/compat"
)

type treePayload struct { Tree []treeEntry `json:"tree"` }
type treeEntry struct { Path string `json:"path"` }

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: otpinventory GITHUB_TREE.json")
		os.Exit(2)
	}
	data, readError := os.ReadFile(os.Args[1])
	match result.Of(data, readError) {
	case result.Err(cause): fail(cause.Error())
	case result.Ok(source):
		var payload treePayload
		match result.Of(true, json.Unmarshal(source, &payload)) {
		case result.Err(cause): fail(cause.Error())
		case result.Ok(_):
			paths := make([]string, len(payload.Tree))
			for index, entry := range payload.Tree { paths[index] = entry.Path }
			match compat.BuildOTPInventory(paths) {
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
}

func fail(detail string) {
	fmt.Fprintln(os.Stderr, detail)
	os.Exit(1)
}

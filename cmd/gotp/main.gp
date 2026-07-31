package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp"
	"goforge.dev/gotp/beam"
	"goforge.dev/gotp/etf"
	"goforge.dev/gotp/proof"
)

type CommandResult enum {
	CommandCompleted()
}

type Failure enum {
	UsageFailure(Detail string)
	FlagFailure(Cause error)
	IOFailure(Operation string, Cause error)
	BeamFailure(Cause beam.Failure)
	ETFFailure(Cause etf.Failure)
	ProofFailure(Cause proof.Failure)
	VerificationFailure(Detail string)
}

func (failure Failure) Error() string {
	match failure {
	case UsageFailure(detail):
		return detail
	case FlagFailure(cause):
		return cause.Error()
	case IOFailure(operation, cause):
		return fmt.Sprintf("%s: %v", operation, cause)
	case BeamFailure(cause):
		return cause.Error()
	case ETFFailure(cause):
		return cause.Error()
	case ProofFailure(cause):
		return cause.Error()
	case VerificationFailure(detail):
		return detail
	}
}

func main() {
	match run(os.Args[1:]) {
	case result.Ok(CommandCompleted):
	case result.Err(failure):
		fmt.Fprintln(os.Stderr, "gotp:", failure.Error())
		os.Exit(1)
	}
}

func run(arguments []string) result.Result[CommandResult, Failure] {
	if len(arguments) == 0 {
		usage()
		return result.Err[CommandResult, Failure](UsageFailure("a command is required"))
	}
	switch arguments[0] {
	case "inspect":
		return inspect(arguments[1:])
	case "verify":
		return verify(arguments[1:])
	case "etf":
		return inspectETF(arguments[1:])
	case "parity":
		return inspectParity(arguments[1:])
	case "version":
		fmt.Printf("gotp %s (%s)\n", gotp.Version, gotp.OTPBaseline)
		return result.Ok[CommandResult, Failure](CommandCompleted())
	default:
		usage()
		return result.Err[CommandResult, Failure](UsageFailure(
			fmt.Sprintf("unknown command %q", arguments[0]),
		))
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: gotp <inspect|verify|etf|parity|version> [options] FILE")
}

func inspect(arguments []string) result.Result[CommandResult, Failure] {
	flags := flag.NewFlagSet("inspect", flag.ContinueOnError)
	match parseFlags(flags, arguments) {
	case result.Err(failure):
		return result.Err[CommandResult, Failure](failure)
	case result.Ok(_):
	}
	if flags.NArg() != 1 {
		return result.Err[CommandResult, Failure](UsageFailure("inspect requires one BEAM file"))
	}
	match beam.Load(beam.OperatingSystemFiles(), flags.Arg(0)) {
	case result.Err(cause):
		return result.Err[CommandResult, Failure](BeamFailure(cause))
	case result.Ok(module):
		return writeJSON(module)
	}
}

type verification struct {
	Module       string             `json:"module"`
	Digest       string             `json:"digest"`
	Structural   bool               `json:"structural"`
	ProofPresent bool               `json:"proof_present"`
	Assurance    proof.Level        `json:"assurance"`
	Dangerous    []proof.Assumption `json:"dangerous,omitempty"`
}

func verify(arguments []string) result.Result[CommandResult, Failure] {
	flags := flag.NewFlagSet("verify", flag.ContinueOnError)
	minimum := flags.String("min", string(proof.Foreign), "minimum assurance level")
	match parseFlags(flags, arguments) {
	case result.Err(failure):
		return result.Err[CommandResult, Failure](failure)
	case result.Ok(_):
	}
	if flags.NArg() != 1 {
		return result.Err[CommandResult, Failure](UsageFailure("verify requires one BEAM file"))
	}
	required := proof.Level(*minimum)
	if !proof.ValidLevel(required) {
		return result.Err[CommandResult, Failure](VerificationFailure(fmt.Sprintf(
			"invalid minimum assurance %q",
			required,
		)))
	}
	match beam.Load(beam.OperatingSystemFiles(), flags.Arg(0)) {
	case result.Err(cause):
		return result.Err[CommandResult, Failure](BeamFailure(cause))
	case result.Ok(module):
		report := verification{
			Module: module.Name, Digest: module.Digest,
			Structural: true, Assurance: proof.Foreign,
		}
		match module.Chunk("GpPr") {
		case option.None:
		case option.Some(raw):
			match proof.Parse(raw) {
			case result.Err(cause):
				return result.Err[CommandResult, Failure](ProofFailure(cause))
			case result.Ok(manifest):
				if manifest.Module != module.Name {
					return result.Err[CommandResult, Failure](VerificationFailure(
						"proof manifest module does not match BEAM module",
					))
				}
				if manifest.ArtifactDigest != module.Digest {
					return result.Err[CommandResult, Failure](VerificationFailure(
						"proof manifest artifact digest does not match BEAM content",
					))
				}
				match manifest.Aggregate() {
				case result.Err(cause):
					return result.Err[CommandResult, Failure](ProofFailure(cause))
				case result.Ok(assurance):
					report.ProofPresent = true
					report.Assurance = assurance
					report.Dangerous = manifest.Dangerous()
				}
			}
		}
		match proof.AtLeast(report.Assurance, required) {
		case result.Err(cause):
			return result.Err[CommandResult, Failure](ProofFailure(cause))
		case result.Ok(accepted):
			if !accepted {
				return result.Err[CommandResult, Failure](VerificationFailure(fmt.Sprintf(
					"module assurance %s is below required %s",
					report.Assurance,
					required,
				)))
			}
		}
		for _, assumption := range report.Dangerous {
			fmt.Fprintf(
				os.Stderr,
				"gotp: DANGEROUS %s %s: %s\n",
				assumption.Kind,
				assumption.Subject,
				assumption.Reason,
			)
		}
		return writeJSON(report)
	}
}

func inspectETF(arguments []string) result.Result[CommandResult, Failure] {
	flags := flag.NewFlagSet("etf", flag.ContinueOnError)
	maxBytes := flags.Int("max-bytes", 256<<20, "maximum decoded bytes")
	match parseFlags(flags, arguments) {
	case result.Err(failure):
		return result.Err[CommandResult, Failure](failure)
	case result.Ok(_):
	}
	if flags.NArg() != 1 {
		return result.Err[CommandResult, Failure](UsageFailure("etf requires one file"))
	}
	raw, readError := os.ReadFile(flags.Arg(0))
	match result.Of(raw, readError) {
	case result.Err(cause):
		return result.Err[CommandResult, Failure](IOFailure("read ETF file", cause))
	case result.Ok(encoded):
		limits := etf.DefaultLimits()
		limits.MaxBytes = *maxBytes
		match etf.Decode(encoded, limits) {
		case result.Err(cause):
			return result.Err[CommandResult, Failure](ETFFailure(cause))
		case result.Ok(value):
			return writeJSON(value)
		}
	}
}

func parseFlags(
	flags *flag.FlagSet,
	arguments []string,
) result.Result[CommandResult, Failure] {
	match result.Of(true, flags.Parse(arguments)) {
	case result.Ok(_):
		return result.Ok[CommandResult, Failure](CommandCompleted())
	case result.Err(cause):
		return result.Err[CommandResult, Failure](FlagFailure(cause))
	}
}

func writeJSON(value any) result.Result[CommandResult, Failure] {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	match result.Of(true, encoder.Encode(value)) {
	case result.Ok(_):
		return result.Ok[CommandResult, Failure](CommandCompleted())
	case result.Err(cause):
		return result.Err[CommandResult, Failure](IOFailure("encode JSON", cause))
	}
}

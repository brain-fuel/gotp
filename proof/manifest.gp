// Package proof defines the machine-readable assurance metadata carried in a
// GoTP BEAM GpPr chunk.
package proof

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
)

const Schema = "gotp.proof/v1"

// Level is the stable wire spelling used by GpPr JSON.
type Level string

const (
	Foreign         Level = "Foreign"
	BoundaryChecked Level = "BoundaryChecked"
	ResourceSafe    Level = "ResourceSafe"
	Total           Level = "Total"
	ClosedVerified  Level = "ClosedVerified"
)

// Assurance is the closed semantic representation used for exhaustive logic.
type Assurance enum {
	ForeignAssurance()
	BoundaryCheckedAssurance()
	ResourceSafeAssurance()
	TotalAssurance()
	ClosedVerifiedAssurance()
}

type Failure enum {
	InvalidJSON(Cause error)
	UnsupportedSchema(Found string)
	MissingField(Field string)
	InvalidDigest(Field string, Detail string)
	InvalidLevel(Dimension string, Found Level)
	IncompleteAssumption(Index int)
}

func (failure Failure) Error() string {
	match failure {
	case InvalidJSON(cause):
		return fmt.Sprintf("proof: invalid JSON: %v", cause)
	case UnsupportedSchema(found):
		return fmt.Sprintf("proof: unsupported schema %q", found)
	case MissingField(field):
		return fmt.Sprintf("proof: required field %s is empty", field)
	case InvalidDigest(field, detail):
		return fmt.Sprintf("proof: %s digest: %s", field, detail)
	case InvalidLevel(dimension, found):
		return fmt.Sprintf("proof: invalid %s level %q", dimension, found)
	case IncompleteAssumption(index):
		return fmt.Sprintf("proof: assumption %d is incomplete", index)
	}
}

type Dimensions struct {
	Types       Level `json:"types"`
	Totality    Level `json:"totality"`
	Resources   Level `json:"resources"`
	Effects     Level `json:"effects"`
	Translation Level `json:"translation"`
	Runtime     Level `json:"runtime"`
}

type Assumption struct {
	Kind      string `json:"kind"`
	Subject   string `json:"subject"`
	Reason    string `json:"reason"`
	Dangerous bool   `json:"dangerous,omitempty"`
}

type Manifest struct {
	Schema         string       `json:"schema"`
	Module         string       `json:"module"`
	SourceDigest   string       `json:"source_digest"`
	ArtifactDigest string       `json:"artifact_digest"`
	Compiler       string       `json:"compiler"`
	OTPBaseline    string       `json:"otp_baseline"`
	Target         string       `json:"target"`
	Dimensions     Dimensions   `json:"dimensions"`
	Assumptions    []Assumption `json:"assumptions,omitempty"`
}

type Validation enum {
	Valid()
}

type dimensionValue struct {
	name  string
	level Level
}

func Parse(data []byte) result.Result[Manifest, Failure] {
	var manifest Manifest
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	decodeError := decoder.Decode(&manifest)
	match result.Of(manifest, decodeError) {
	case result.Err(cause):
		return result.Err[Manifest, Failure](InvalidJSON(cause))
	case result.Ok(decoded):
		match decoded.Validate() {
		case result.Err(failure):
			return result.Err[Manifest, Failure](failure)
		case result.Ok(_):
			return result.Ok[Manifest, Failure](decoded)
		}
	}
}

func (manifest Manifest) Validate() result.Result[Validation, Failure] {
	if manifest.Schema != Schema {
		return result.Err[Validation, Failure](UnsupportedSchema(manifest.Schema))
	}
	required := []struct {
		name  string
		value string
	}{
		{name: "module", value: manifest.Module},
		{name: "compiler", value: manifest.Compiler},
		{name: "otp_baseline", value: manifest.OTPBaseline},
		{name: "target", value: manifest.Target},
	}
	for _, field := range required {
		if field.value == "" {
			return result.Err[Validation, Failure](MissingField(field.name))
		}
	}
	match digest("source", manifest.SourceDigest) {
	case result.Err(failure):
		return result.Err[Validation, Failure](failure)
	case result.Ok(_):
	}
	match digest("artifact", manifest.ArtifactDigest) {
	case result.Err(failure):
		return result.Err[Validation, Failure](failure)
	case result.Ok(_):
	}
	dimensions := []dimensionValue{
		{name: "types", level: manifest.Dimensions.Types},
		{name: "totality", level: manifest.Dimensions.Totality},
		{name: "resources", level: manifest.Dimensions.Resources},
		{name: "effects", level: manifest.Dimensions.Effects},
		{name: "translation", level: manifest.Dimensions.Translation},
		{name: "runtime", level: manifest.Dimensions.Runtime},
	}
	for _, dimension := range dimensions {
		match ParseLevel(dimension.level) {
		case option.Some(_):
		case option.None:
			return result.Err[Validation, Failure](InvalidLevel(dimension.name, dimension.level))
		}
	}
	for index, assumption := range manifest.Assumptions {
		if assumption.Kind == "" || assumption.Subject == "" || assumption.Reason == "" {
			return result.Err[Validation, Failure](IncompleteAssumption(index))
		}
	}
	return result.Ok[Validation, Failure](Valid())
}

func (manifest Manifest) Aggregate() result.Result[Level, Failure] {
	dimensions := []dimensionValue{
		{name: "types", level: manifest.Dimensions.Types},
		{name: "totality", level: manifest.Dimensions.Totality},
		{name: "resources", level: manifest.Dimensions.Resources},
		{name: "effects", level: manifest.Dimensions.Effects},
		{name: "translation", level: manifest.Dimensions.Translation},
		{name: "runtime", level: manifest.Dimensions.Runtime},
	}
	var current Assurance = ClosedVerifiedAssurance()
	for _, dimension := range dimensions {
		match ParseLevel(dimension.level) {
		case option.None:
			return result.Err[Level, Failure](InvalidLevel(dimension.name, dimension.level))
		case option.Some(found):
			if assuranceRank(found) < assuranceRank(current) {
				current = found
			}
		}
	}
	if len(manifest.Assumptions) > 0 &&
		assuranceRank(current) > assuranceRank(BoundaryCheckedAssurance()) {
		current = BoundaryCheckedAssurance()
	}
	return result.Ok[Level, Failure](WireLevel(current))
}

func (manifest Manifest) Dangerous() []Assumption {
	out := []Assumption{}
	for _, assumption := range manifest.Assumptions {
		if assumption.Dangerous {
			out = append(out, assumption)
		}
	}
	return out
}

func ParseLevel(level Level) option.Option[Assurance] {
	switch level {
	case Foreign:
		return option.Some[Assurance](ForeignAssurance())
	case BoundaryChecked:
		return option.Some[Assurance](BoundaryCheckedAssurance())
	case ResourceSafe:
		return option.Some[Assurance](ResourceSafeAssurance())
	case Total:
		return option.Some[Assurance](TotalAssurance())
	case ClosedVerified:
		return option.Some[Assurance](ClosedVerifiedAssurance())
	default:
		return option.None[Assurance]
	}
}

func WireLevel(assurance Assurance) Level {
	match assurance {
	case ForeignAssurance:
		return Foreign
	case BoundaryCheckedAssurance:
		return BoundaryChecked
	case ResourceSafeAssurance:
		return ResourceSafe
	case TotalAssurance:
		return Total
	case ClosedVerifiedAssurance:
		return ClosedVerified
	}
}

func ValidLevel(level Level) bool {
	match ParseLevel(level) {
	case option.Some(_):
		return true
	case option.None:
		return false
	}
}

func AtLeast(actual Level, minimum Level) result.Result[bool, Failure] {
	match ParseLevel(actual) {
	case option.None:
		return result.Err[bool, Failure](InvalidLevel("actual", actual))
	case option.Some(actualAssurance):
		match ParseLevel(minimum) {
		case option.None:
			return result.Err[bool, Failure](InvalidLevel("minimum", minimum))
		case option.Some(minimumAssurance):
			return result.Ok[bool, Failure](
				assuranceRank(actualAssurance) >= assuranceRank(minimumAssurance),
			)
		}
	}
}

func assuranceRank(assurance Assurance) int {
	match assurance {
	case ForeignAssurance:
		return 0
	case BoundaryCheckedAssurance:
		return 1
	case ResourceSafeAssurance:
		return 2
	case TotalAssurance:
		return 3
	case ClosedVerifiedAssurance:
		return 4
	}
}

func digest(field string, value string) result.Result[Validation, Failure] {
	raw, decodeError := hex.DecodeString(value)
	match result.Of(raw, decodeError) {
	case result.Err(cause):
		return result.Err[Validation, Failure](InvalidDigest(field, cause.Error()))
	case result.Ok(decoded):
		if len(decoded) != 32 {
			return result.Err[Validation, Failure](InvalidDigest(field, "expected SHA-256 digest"))
		}
		return result.Ok[Validation, Failure](Valid())
	}
}

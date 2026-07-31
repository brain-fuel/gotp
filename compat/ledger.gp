package compat

import (
	"encoding/json"
	"sort"
	"strings"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/proof"
)

const (
	SchemaVersion = "gotp.compatibility/v2"
	OTPPinnedTag = "OTP-29.0.4"
	OTPPinnedCommit = "1259612946cb36a8bf9614b289090bb32fbcbeb2"
)

type WireStatus string

const (
	WireMissing WireStatus = "missing"
	WirePartial WireStatus = "partial"
	WireConformant WireStatus = "conformant"
	WireUnavailable WireStatus = "unavailable"
)

type Status enum {
	Missing()
	Partial()
	Conformant()
	Unavailable()
}

type Evidence struct {
	Kind string `json:"kind"`
	Reference string `json:"reference"`
	Digest string `json:"digest,omitempty"`
}

type Item struct {
	ID string
	Area string
	Capability string
	Status Status
	Assurance proof.Level
	Reason string
	Evidence []Evidence
}

type Ledger struct {
	Schema string
	UpstreamTag string
	UpstreamCommit string
	InventoryComplete bool
	Items []Item
}

type Summary struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	InventoryComplete bool `json:"inventory_complete"`
	Total int `json:"total"`
	Missing int `json:"missing"`
	Partial int `json:"partial"`
	Conformant int `json:"conformant"`
	Unavailable int `json:"unavailable"`
	Complete bool `json:"complete"`
}

type Failure enum {
	InvalidJSON(Detail string)
	InvalidSchema(Schema string)
	InvalidUpstream(Upstream string)
	InvalidID(ID string)
	DuplicateID(ID string)
	InvalidStatus(ID string, Status string)
	InvalidAssurance(ID string, Assurance string)
	MissingEvidence(ID string)
	MissingReason(ID string)
	EncodingFailure(Detail string)
}

type wireItem struct {
	ID string `json:"id"`
	Area string `json:"area"`
	Capability string `json:"capability"`
	Status WireStatus `json:"status"`
	Assurance proof.Level `json:"assurance"`
	Reason string `json:"reason,omitempty"`
	Evidence []Evidence `json:"evidence,omitempty"`
}

type wireLedger struct {
	Schema string `json:"schema"`
	UpstreamTag string `json:"upstream_tag"`
	UpstreamCommit string `json:"upstream_commit"`
	InventoryComplete bool `json:"inventory_complete"`
	Items []wireItem `json:"items"`
}

// assayxport:unit gotp.compat.ledger
func Parse(data []byte) result.Result[Ledger, Failure] {
	wire := wireLedger{}
	if err := json.Unmarshal(data, &wire); err != nil {
		return result.Err[Ledger, Failure](InvalidJSON(err.Error()))
	}
	if wire.Schema != SchemaVersion {
		return result.Err[Ledger, Failure](InvalidSchema(wire.Schema))
	}
	if wire.UpstreamTag != OTPPinnedTag || wire.UpstreamCommit != OTPPinnedCommit {
		return result.Err[Ledger, Failure](InvalidUpstream(wire.UpstreamTag + "@" + wire.UpstreamCommit))
	}

	seen := map[string]struct{}{}
	items := make([]Item, 0, len(wire.Items))
	for _, candidate := range wire.Items {
		if !validID(candidate.ID) {
			return result.Err[Ledger, Failure](InvalidID(candidate.ID))
		}
		if _, exists := seen[candidate.ID]; exists {
			return result.Err[Ledger, Failure](DuplicateID(candidate.ID))
		}
		seen[candidate.ID] = struct{}{}

		status, valid := statusFromWire(candidate.Status)
		if !valid {
			return result.Err[Ledger, Failure](InvalidStatus(candidate.ID, string(candidate.Status)))
		}
		if !proof.ValidLevel(candidate.Assurance) {
			return result.Err[Ledger, Failure](InvalidAssurance(candidate.ID, string(candidate.Assurance)))
		}
		if candidate.Status == WireConformant && len(candidate.Evidence) == 0 {
			return result.Err[Ledger, Failure](MissingEvidence(candidate.ID))
		}
		if candidate.Status == WireUnavailable && strings.TrimSpace(candidate.Reason) == "" {
			return result.Err[Ledger, Failure](MissingReason(candidate.ID))
		}

		evidence := append([]Evidence(nil), candidate.Evidence...)
		sort.Slice(evidence, func(i, j int) bool {
			if evidence[i].Kind == evidence[j].Kind {
				return evidence[i].Reference < evidence[j].Reference
			}
			return evidence[i].Kind < evidence[j].Kind
		})
		items = append(items, Item{
			ID: candidate.ID,
			Area: candidate.Area,
			Capability: candidate.Capability,
			Status: status,
			Assurance: candidate.Assurance,
			Reason: candidate.Reason,
			Evidence: evidence,
		})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].ID < items[j].ID })

	return result.Ok[Ledger, Failure](Ledger{
		Schema: wire.Schema,
		UpstreamTag: wire.UpstreamTag,
		UpstreamCommit: wire.UpstreamCommit,
		InventoryComplete: wire.InventoryComplete,
		Items: items,
	})
}

func Summarize(ledger Ledger) Summary {
	summary := Summary{
		Schema: ledger.Schema,
		UpstreamTag: ledger.UpstreamTag,
		UpstreamCommit: ledger.UpstreamCommit,
		InventoryComplete: ledger.InventoryComplete,
		Total: len(ledger.Items),
	}
	for _, item := range ledger.Items {
		match item.Status {
		case Missing:
			summary.Missing++
		case Partial:
			summary.Partial++
		case Conformant:
			summary.Conformant++
		case Unavailable:
			summary.Unavailable++
		}
	}
	summary.Complete = summary.InventoryComplete && summary.Total > 0 && summary.Missing == 0 && summary.Partial == 0
	return summary
}

func CanonicalJSON(ledger Ledger) result.Result[[]byte, Failure] {
	items := append([]Item(nil), ledger.Items...)
	sort.Slice(items, func(i, j int) bool { return items[i].ID < items[j].ID })
	wireItems := make([]wireItem, 0, len(items))
	for _, item := range items {
		evidence := append([]Evidence(nil), item.Evidence...)
		sort.Slice(evidence, func(i, j int) bool {
			if evidence[i].Kind == evidence[j].Kind {
				return evidence[i].Reference < evidence[j].Reference
			}
			return evidence[i].Kind < evidence[j].Kind
		})
		wireItems = append(wireItems, wireItem{
			ID: item.ID,
			Area: item.Area,
			Capability: item.Capability,
			Status: statusToWire(item.Status),
			Assurance: item.Assurance,
			Reason: item.Reason,
			Evidence: evidence,
		})
	}
	payload, err := json.MarshalIndent(wireLedger{
		Schema: ledger.Schema,
		UpstreamTag: ledger.UpstreamTag,
		UpstreamCommit: ledger.UpstreamCommit,
		InventoryComplete: ledger.InventoryComplete,
		Items: wireItems,
	}, "", "  ")
	if err != nil {
		return result.Err[[]byte, Failure](EncodingFailure(err.Error()))
	}
	return result.Ok[[]byte, Failure](append(payload, '\n'))
}

func FailureMessage(failure Failure) string {
	match failure {
	case InvalidJSON(detail):
		return "invalid compatibility JSON: " + detail
	case InvalidSchema(schema):
		return "unsupported compatibility schema: " + schema
	case InvalidUpstream(upstream):
		return "ledger is not pinned to " + OTPPinnedTag + "@" + OTPPinnedCommit + ": " + upstream
	case InvalidID(id):
		return "invalid stable compatibility ID: " + id
	case DuplicateID(id):
		return "duplicate compatibility ID: " + id
	case InvalidStatus(id, status):
		return "invalid status for " + id + ": " + status
	case InvalidAssurance(id, assurance):
		return "invalid assurance for " + id + ": " + assurance
	case MissingEvidence(id):
		return "conformant item has no evidence: " + id
	case MissingReason(id):
		return "unavailable item has no reason: " + id
	case EncodingFailure(detail):
		return "cannot encode compatibility ledger: " + detail
	}
}

func StatusName(status Status) string {
	return string(statusToWire(status))
}

func statusFromWire(status WireStatus) (Status, bool) {
	switch status {
	case WireMissing:
		return Missing(), true
	case WirePartial:
		return Partial(), true
	case WireConformant:
		return Conformant(), true
	case WireUnavailable:
		return Unavailable(), true
	default:
		return Missing(), false
	}
}

func statusToWire(status Status) WireStatus {
	match status {
	case Missing:
		return WireMissing
	case Partial:
		return WirePartial
	case Conformant:
		return WireConformant
	case Unavailable:
		return WireUnavailable
	}
}

func validID(id string) bool {
	if id == "" || strings.TrimSpace(id) != id || strings.Contains(id, "..") {
		return false
	}
	for _, r := range id {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || strings.ContainsRune("._:-/", r) {
			continue
		}
		return false
	}
	return true
}

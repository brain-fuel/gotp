package erts

import (
    "encoding/json"
    "os"
    "strings"
    "testing"
)

type genStatemAuditEvidence struct { Reference string `json:"reference"` }
type genStatemAuditItem struct {
    ID string `json:"id"`
    Capability string `json:"capability"`
    Status string `json:"status"`
    Evidence []genStatemAuditEvidence `json:"evidence"`
}
type genStatemAuditWire struct { Items []genStatemAuditItem `json:"items"` }

// assayxport:law gotp.erts.gen-statem-complete-inventory-audit
func TestGenStatemCompleteInventoryAudit(t *testing.T) {
    payload, cause := os.ReadFile("../compat/otp-29.0.4.json")
    if cause != nil { t.Fatal(cause) }
    wire := genStatemAuditWire{}
    if cause := json.Unmarshal(payload, &wire); cause != nil { t.Fatal(cause) }
    counts := map[string]int{}
    for _, item := range wire.Items {
        if !strings.Contains(item.ID, ".stdlib.gen_statem.") || !strings.HasPrefix(item.ID, "otp.declaration.") { continue }
        parts := strings.Split(item.ID, ".")
        if len(parts) < 4 { t.Fatalf("malformed declaration identity %s", item.ID) }
        kind := parts[2]
        counts[kind]++
        if kind == "type" {
            if item.Status != "missing" { t.Fatalf("static type was promoted without type evidence: %s", item.Capability) }
            continue
        }
        if item.Status != "partial" { t.Fatalf("executable declaration %s = %s", item.Capability, item.Status) }
        if len(item.Evidence) == 0 { t.Fatalf("partial declaration lacks evidence: %s", item.Capability) }
    }
    expected := map[string]int{"function": 39, "callback": 8, "optional-callback": 6, "type": 25}
    for kind, wanted := range expected {
        if counts[kind] != wanted { t.Fatalf("gen_statem %s declarations = %d, want %d", kind, counts[kind], wanted) }
    }
}

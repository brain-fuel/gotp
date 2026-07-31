package erts

import (
	"testing"
	"testing/quick"

	"goforge.dev/goplus/std/memory"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
	"goforge.dev/gotp/vm"
)

// assayxport:law gotp.erts.receive-marker-cursor
func TestReceiveMarkerRestoresBoundMailboxCursor(t *testing.T) {
	property := func(raw uint8) bool {
		prefix := int(raw % 32)
		process := &VMProcess{receiveMessages: memory.NewBuffer[kernel.MessageEnvelope](prefix + 1)}
		for index := 0; index < prefix; index++ { process.receiveMessages.Append(kernel.MessageEnvelope{Message: term.Integer(int64(index))}) }
		var marker term.Term
		match process.reserveReceiveMarker() { case vm.ReceiveMarkerReserveRejected(_): return false; case vm.ReceiveMarkerReserved(found): marker = found }
		reference := term.Reference{Node: 1, Creation: 1, Words: [5]uint32{1}, Length: 1}
		match process.bindReceiveMarker(marker, term.ReferenceValue(reference)) { case vm.ReceiveMarkerRejected(_): return false; case vm.ReceiveMarkerChanged: }
		process.receiveCursor = 0
		match process.useReceiveMarker(term.ReferenceValue(reference)) { case vm.ReceiveMarkerRejected(_): return false; case vm.ReceiveMarkerChanged: }
		if process.receiveCursor != prefix { return false }
		match process.clearReceiveMarker(term.ReferenceValue(reference)) { case vm.ReceiveMarkerRejected(_): return false; case vm.ReceiveMarkerChanged: }
		process.receiveCursor = prefix
		match process.useReceiveMarker(term.ReferenceValue(reference)) { case vm.ReceiveMarkerRejected(_): return false; case vm.ReceiveMarkerChanged: }
		return process.receiveCursor == 0
	}
	if cause := quick.Check(property, nil); cause != nil { t.Fatal(cause) }
}

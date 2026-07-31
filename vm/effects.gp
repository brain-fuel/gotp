package vm

import (
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type SendOutcome enum {
	MessageSent(Value term.Term)
	SendRejected(Detail string)
}

type SendEffect func(To term.Term, Message term.Term) SendOutcome

type SendCapability enum {
	SendUnavailable()
	SendAllowed()
}

type ReceiveOutcome enum {
	ReceiveMessage(Value term.Term)
	ReceiveEmpty()
	ReceiveRejected(Detail string)
}

type AdvanceOutcome enum {
	ReceiveCursorAdvanced()
	AdvanceRejected(Detail string)
}

type RemoveOutcome enum {
	ReceiveMessageRemoved()
	RemoveRejected(Detail string)
}

type ReceivePeekEffect func() ReceiveOutcome
type ReceiveAdvanceEffect func() AdvanceOutcome
type ReceiveRemoveEffect func() RemoveOutcome

type ReceiveCapability enum {
	ReceiveUnavailable()
	ReceiveAllowed()
}

type ReceiveEffects struct {
	Peek    ReceivePeekEffect
	Advance ReceiveAdvanceEffect
	Remove  ReceiveRemoveEffect
}

type MessagingEffects struct {
	Send SendEffect
	Receive ReceiveEffects
}

type HostCapabilities struct {
	Send    SendCapability
	Receive ReceiveCapability
	send    SendEffect
	peek    ReceivePeekEffect
	advance ReceiveAdvanceEffect
	remove  ReceiveRemoveEffect
}

func NoHostCapabilities() HostCapabilities {
	var unavailable SendCapability = SendUnavailable()
	var receiveUnavailable ReceiveCapability = ReceiveUnavailable()
	return HostCapabilities{Send: unavailable, Receive: receiveUnavailable}
}

// assayxport:unit gotp.vm.host-effects
func HostWithSend(effect SendEffect) result.Result[HostCapabilities, Failure] {
	if effect == nil {
		return result.Err[HostCapabilities, Failure](InvalidConfiguration("send effect is nil"))
	}
	var allowed SendCapability = SendAllowed()
	var receiveUnavailable ReceiveCapability = ReceiveUnavailable()
	return result.Ok[HostCapabilities, Failure](HostCapabilities{
		Send: allowed,
		Receive: receiveUnavailable,
		send: effect,
	})
}

func HostWithReceive(effects ReceiveEffects) result.Result[HostCapabilities, Failure] {
	match validateReceiveEffects(effects) {
	case result.Err(failure):
		return result.Err[HostCapabilities, Failure](failure)
	case result.Ok(_):
		var sendUnavailable SendCapability = SendUnavailable()
		var receiveAllowed ReceiveCapability = ReceiveAllowed()
		return result.Ok[HostCapabilities, Failure](HostCapabilities{
			Send: sendUnavailable,
			Receive: receiveAllowed,
			peek: effects.Peek,
			advance: effects.Advance,
			remove: effects.Remove,
		})
	}
}

func HostWithMessaging(effects MessagingEffects) result.Result[HostCapabilities, Failure] {
	if effects.Send == nil {
		return result.Err[HostCapabilities, Failure](InvalidConfiguration("send effect is nil"))
	}
	match validateReceiveEffects(effects.Receive) {
	case result.Err(failure):
		return result.Err[HostCapabilities, Failure](failure)
	case result.Ok(_):
		var sendAllowed SendCapability = SendAllowed()
		var receiveAllowed ReceiveCapability = ReceiveAllowed()
		return result.Ok[HostCapabilities, Failure](HostCapabilities{
			Send: sendAllowed,
			Receive: receiveAllowed,
			send: effects.Send,
			peek: effects.Receive.Peek,
			advance: effects.Receive.Advance,
			remove: effects.Receive.Remove,
		})
	}
}

func validateReceiveEffects(effects ReceiveEffects) result.Result[bool, Failure] {
	if effects.Peek == nil || effects.Advance == nil || effects.Remove == nil {
		return result.Err[bool, Failure](InvalidConfiguration("receive effects must be complete"))
	}
	return result.Ok[bool, Failure](true)
}

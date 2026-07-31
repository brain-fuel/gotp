package vm

import (
	"time"

	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/term"
)

type TimerWaitOutcome enum {
	TimerPending()
	TimerExpired()
	TimerRejected(Detail string)
}

type TimerMutation enum {
	TimerChanged()
	TimerUnchanged()
	TimerMutationRejected(Detail string)
}

type TimerWaitEffect func(Delay time.Duration) TimerWaitOutcome
type TimerMutationEffect func() TimerMutation

type TimerCapability enum {
	TimerUnavailable()
	TimerAllowed()
}

type TimerEffects struct {
	Wait   TimerWaitEffect
	Cancel TimerMutationEffect
	Finish TimerMutationEffect
}

type ExternalFunction struct {
	Module   string
	Function string
	Arity    uint32
}

// assayxport:unit gotp.vm.exception-propagation
type ExternalCallOutcome enum {
	ExternalCallUnbound()
	ExternalCallReturned(Value term.Term)
	ExternalCallRaised(Class term.Term, Reason term.Term)
	ExternalCallRejected(Detail string)
}

type ExternalCallEffect func(Target ExternalFunction, Arguments []term.Term) ExternalCallOutcome

type ExternalCallCapability enum {
	ExternalCallsUnavailable()
	ExternalCallsAllowed()
}

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

type TimedMessagingEffects struct {
	Messaging MessagingEffects
	Timer     TimerEffects
}

type HostCapabilities struct {
	Send    SendCapability
	Receive ReceiveCapability
	Timer   TimerCapability
	ExternalCalls ExternalCallCapability
	send    SendEffect
	peek    ReceivePeekEffect
	advance ReceiveAdvanceEffect
	remove  ReceiveRemoveEffect
	timerWait   TimerWaitEffect
	timerCancel TimerMutationEffect
	timerFinish TimerMutationEffect
	externalCall ExternalCallEffect
}

func NoHostCapabilities() HostCapabilities {
	var unavailable SendCapability = SendUnavailable()
	var receiveUnavailable ReceiveCapability = ReceiveUnavailable()
	var timerUnavailable TimerCapability = TimerUnavailable()
	var callsUnavailable ExternalCallCapability = ExternalCallsUnavailable()
	return HostCapabilities{
		Send: unavailable,
		Receive: receiveUnavailable,
		Timer: timerUnavailable,
		ExternalCalls: callsUnavailable,
	}
}

// assayxport:unit gotp.vm.host-effects
func HostWithSend(effect SendEffect) result.Result[HostCapabilities, Failure] {
	if effect == nil {
		return result.Err[HostCapabilities, Failure](InvalidConfiguration("send effect is nil"))
	}
	var allowed SendCapability = SendAllowed()
	var receiveUnavailable ReceiveCapability = ReceiveUnavailable()
	var timerUnavailable TimerCapability = TimerUnavailable()
	var callsUnavailable ExternalCallCapability = ExternalCallsUnavailable()
	return result.Ok[HostCapabilities, Failure](HostCapabilities{
		Send: allowed,
		Receive: receiveUnavailable,
		Timer: timerUnavailable,
		ExternalCalls: callsUnavailable,
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
		var timerUnavailable TimerCapability = TimerUnavailable()
		var callsUnavailable ExternalCallCapability = ExternalCallsUnavailable()
		return result.Ok[HostCapabilities, Failure](HostCapabilities{
			Send: sendUnavailable,
			Receive: receiveAllowed,
			Timer: timerUnavailable,
			ExternalCalls: callsUnavailable,
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
		var timerUnavailable TimerCapability = TimerUnavailable()
		var callsUnavailable ExternalCallCapability = ExternalCallsUnavailable()
		return result.Ok[HostCapabilities, Failure](HostCapabilities{
			Send: sendAllowed,
			Receive: receiveAllowed,
			Timer: timerUnavailable,
			ExternalCalls: callsUnavailable,
			send: effects.Send,
			peek: effects.Receive.Peek,
			advance: effects.Receive.Advance,
			remove: effects.Receive.Remove,
		})
	}
}

// assayxport:unit gotp.vm.external-call-capability
func HostGrantExternalCalls(
	host HostCapabilities,
	effect ExternalCallEffect,
) result.Result[HostCapabilities, Failure] {
	if effect == nil {
		return result.Err[HostCapabilities, Failure](InvalidConfiguration("external call effect is nil"))
	}
	var allowed ExternalCallCapability = ExternalCallsAllowed()
	host.ExternalCalls = allowed
	host.externalCall = effect
	return result.Ok[HostCapabilities, Failure](host)
}

// assayxport:unit gotp.vm.receive-timeout
func HostWithTimedMessaging(effects TimedMessagingEffects) result.Result[HostCapabilities, Failure] {
	match HostWithMessaging(effects.Messaging) {
	case result.Err(failure):
		return result.Err[HostCapabilities, Failure](failure)
	case result.Ok(host):
		if effects.Timer.Wait == nil || effects.Timer.Cancel == nil || effects.Timer.Finish == nil {
			return result.Err[HostCapabilities, Failure](InvalidConfiguration("timer effects must be complete"))
		}
		var timerAllowed TimerCapability = TimerAllowed()
		host.Timer = timerAllowed
		host.timerWait = effects.Timer.Wait
		host.timerCancel = effects.Timer.Cancel
		host.timerFinish = effects.Timer.Finish
		return result.Ok[HostCapabilities, Failure](host)
	}
}

func validateReceiveEffects(effects ReceiveEffects) result.Result[bool, Failure] {
	if effects.Peek == nil || effects.Advance == nil || effects.Remove == nil {
		return result.Err[bool, Failure](InvalidConfiguration("receive effects must be complete"))
	}
	return result.Ok[bool, Failure](true)
}

package erts

import (
	"math/big"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/distribution"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type DistributionQueueMutation enum {
	DistributionOutputQueued()
	DistributionOutputUnchanged()
}

// assayxport:unit gotp.erts.distribution-outbound
func QueueRemoteUnlink(
	queue *distribution.OutboundQueue,
	unlink kernel.RemoteUnlink,
) result.Result[DistributionQueueMutation, distribution.Failure] {
	if queue == nil {
		return result.Err[DistributionQueueMutation, distribution.Failure](distribution.InvalidControl("outbound queue is nil"))
	}
	identifier := term.MustBigInteger(new(big.Int).SetUint64(unlink.ID))
	match distribution.NewControl(
		distribution.UnlinkIDCode(),
		identifier, term.PIDValue(unlink.Local), term.PIDValue(unlink.Remote),
	) {
	case result.Err(failure): return result.Err[DistributionQueueMutation, distribution.Failure](failure)
	case result.Ok(control):
		match queue.Enqueue(
			distribution.OrdinaryOutput(), unlink.Remote, control, option.None[term.Term],
		) {
		case result.Err(failure): return result.Err[DistributionQueueMutation, distribution.Failure](failure)
		case result.Ok(_): return result.Ok[DistributionQueueMutation, distribution.Failure](DistributionOutputQueued())
		}
	}
}

func QueueDistributionReply(
	queue *distribution.OutboundQueue,
	outcome DistributionDispatch,
) result.Result[DistributionQueueMutation, distribution.Failure] {
	if queue == nil {
		return result.Err[DistributionQueueMutation, distribution.Failure](distribution.InvalidControl("outbound queue is nil"))
	}
	match outcome {
	case DistributionUnlinkAcknowledgement(identifier, from, to):
		match distribution.NewControl(
			distribution.UnlinkIDAckCode(), identifier, term.PIDValue(from), term.PIDValue(to),
		) {
		case result.Err(failure): return result.Err[DistributionQueueMutation, distribution.Failure](failure)
		case result.Ok(control):
			match queue.Enqueue(
				distribution.RequiredReplyOutput(), to, control, option.None[term.Term],
			) {
			case result.Err(failure): return result.Err[DistributionQueueMutation, distribution.Failure](failure)
			case result.Ok(_): return result.Ok[DistributionQueueMutation, distribution.Failure](DistributionOutputQueued())
			}
		}
	case _:
		return result.Ok[DistributionQueueMutation, distribution.Failure](DistributionOutputUnchanged())
	}
}

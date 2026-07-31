package mnesia

import (
	"fmt"
	"os"

	"goforge.dev/goplus/std/fsatomic"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/etf"
)

type PersistenceFailure enum {
	InvalidPersistencePath()
	PersistenceSnapshotFailure(Cause SnapshotFailure)
	PersistenceReadFailure(Path string, Cause error)
	PersistenceWriteFailure(Path string, Cause error)
}

func (failure PersistenceFailure) Error() string {
	match failure {
	case InvalidPersistencePath:
		return "gotp/mnesia: persistence path is empty"
	case PersistenceSnapshotFailure(cause):
		return cause.Error()
	case PersistenceReadFailure(path, cause):
		return fmt.Sprintf("gotp/mnesia: read snapshot %q: %v", path, cause)
	case PersistenceWriteFailure(path, cause):
		return fmt.Sprintf("gotp/mnesia: write snapshot %q: %v", path, cause)
	}
}

// assayxport:unit gotp.otp.mnesia-persistence
func SaveFile(
	database *Database,
	codec etf.CanonicalCodec,
	path string,
	permission os.FileMode,
) result.Result[Mutation, PersistenceFailure] {
	if path == "" {
		return result.Err[Mutation, PersistenceFailure](InvalidPersistencePath())
	}
	if permission == 0 {
		permission = 0o600
	}
	var payload []byte
	match Snapshot(database, codec) {
	case result.Err(failure):
		return result.Err[Mutation, PersistenceFailure](PersistenceSnapshotFailure(failure))
	case result.Ok(encoded):
		payload = encoded
	}
	match result.Of(true, fsatomic.WriteFile(path, payload, permission)) {
	case result.Err(cause):
		return result.Err[Mutation, PersistenceFailure](PersistenceWriteFailure(path, cause))
	case result.Ok(_):
		return result.Ok[Mutation, PersistenceFailure](Changed())
	}
}

func LoadFile(
	database *Database,
	codec etf.CanonicalCodec,
	path string,
) result.Result[Mutation, PersistenceFailure] {
	if path == "" {
		return result.Err[Mutation, PersistenceFailure](InvalidPersistencePath())
	}
	payload, readFailure := os.ReadFile(path)
	match result.Of(payload, readFailure) {
	case result.Err(cause):
		return result.Err[Mutation, PersistenceFailure](PersistenceReadFailure(path, cause))
	case result.Ok(encoded):
		match Restore(database, codec, encoded) {
		case result.Err(failure):
			return result.Err[Mutation, PersistenceFailure](PersistenceSnapshotFailure(failure))
		case result.Ok(mutation):
			return result.Ok[Mutation, PersistenceFailure](mutation)
		}
	}
}

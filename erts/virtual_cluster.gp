package erts

import (
	"sort"

	"goforge.dev/goplus/std/option"
	"goforge.dev/goplus/std/result"
	"goforge.dev/gotp/kernel"
	"goforge.dev/gotp/term"
)

type VirtualNode struct {
	Name string
	ID uint32
	Runtime *kernel.Kernel
}

type VirtualCluster struct {
	byName map[string]VirtualNode
	byID map[uint32]VirtualNode
	disconnected map[virtualRoute]bool
}

type virtualRoute struct { from uint32; to uint32 }

type VirtualClusterReport struct { Rounds int; Reductions int; RoutedSignals int }

type VirtualClusterFailure enum {
	InvalidVirtualNode(Detail string)
	DuplicateVirtualNode(Name string)
}

func (failure VirtualClusterFailure) Error() string {
	match failure {
	case InvalidVirtualNode(detail): return "gotp/erts: invalid virtual node: " + detail
	case DuplicateVirtualNode(name): return "gotp/erts: duplicate virtual node: " + name
	}
}

// assayxport:unit gotp.erts.virtual-cluster
func NewVirtualCluster() *VirtualCluster {
	return &VirtualCluster{byName: map[string]VirtualNode{}, byID: map[uint32]VirtualNode{}, disconnected: map[virtualRoute]bool{}}
}

func (cluster *VirtualCluster) AddNode(name string, id uint32, creation uint32) result.Result[VirtualNode, VirtualClusterFailure] {
	if cluster == nil || name == "" || id == 0 { return result.Err[VirtualNode, VirtualClusterFailure](InvalidVirtualNode("cluster, name, and id are required")) }
	if _, present := cluster.byName[name]; present { return result.Err[VirtualNode, VirtualClusterFailure](DuplicateVirtualNode(name)) }
	if _, present := cluster.byID[id]; present { return result.Err[VirtualNode, VirtualClusterFailure](InvalidVirtualNode("node id is already present")) }
	runtime := kernel.New(kernel.KernelConfig{Node: id, Creation: creation, NodeName: name, Remote: cluster})
	node := VirtualNode{Name: name, ID: id, Runtime: runtime}
	cluster.byName[name] = node; cluster.byID[id] = node
	return result.Ok[VirtualNode, VirtualClusterFailure](node)
}

func (cluster *VirtualCluster) Disconnect(left uint32, right uint32) {
	cluster.disconnected[virtualRoute{from: left, to: right}] = true
	cluster.disconnected[virtualRoute{from: right, to: left}] = true
}

func (cluster *VirtualCluster) Connect(left uint32, right uint32) {
	delete(cluster.disconnected, virtualRoute{from: left, to: right})
	delete(cluster.disconnected, virtualRoute{from: right, to: left})
}

func (cluster *VirtualCluster) NodeName(node uint32) option.Option[string] {
	value, present := cluster.byID[node]; if !present { return option.None[string]() }; return option.Some(value.Name)
}

func (cluster *VirtualCluster) ConnectedNodes(node uint32) []string {
	names := []string{}
	for id, candidate := range cluster.byID { if id != node && cluster.connected(node, id) { names = append(names, candidate.Name) } }
	sort.Strings(names); return names
}

func (cluster *VirtualCluster) SendPID(from term.PID, to term.PID, message term.Term) kernel.Delivery {
	target, present := cluster.byID[to.Node]; if !present || !cluster.connected(from.Node, to.Node) { return kernel.NoProcess() }
	return target.Runtime.Send(from, to, message)
}

func (cluster *VirtualCluster) SendName(from term.PID, node string, name string, message term.Term) kernel.Delivery {
	target, present := cluster.byName[node]; if !present || !cluster.connected(from.Node, target.ID) { return kernel.NoProcess() }
	return target.Runtime.SendRegistered(from, name, message)
}

func (cluster *VirtualCluster) SendAlias(from term.PID, reference term.Reference, message term.Term) kernel.Delivery {
	target, present := cluster.byID[reference.Node]; if !present || !cluster.connected(from.Node, reference.Node) { return kernel.NoProcess() }
	return target.Runtime.SendAlias(from, reference, message)
}

func (cluster *VirtualCluster) MonitorName(watcher term.PID, node string, name string, reference term.Reference) bool {
	target, present := cluster.byName[node]; if !present || !cluster.connected(watcher.Node, target.ID) { return false }
	match target.Runtime.MonitorRemoteName(watcher, name, reference) { case result.Err(_): return false; case result.Ok(_): return true }
}

func (cluster *VirtualCluster) DemonitorName(watcher term.PID, node string, name string, reference term.Reference) {
	target, present := cluster.byName[node]; if !present { return }
	target.Runtime.DemonitorRemoteName(watcher, name, reference)
}

func (cluster *VirtualCluster) Run(maxRounds int, reductionsPerNode int) VirtualClusterReport {
	if maxRounds <= 0 { maxRounds = 1 }; if reductionsPerNode <= 0 { reductionsPerNode = 1_000_000 }
	report := VirtualClusterReport{}
	ids := make([]int, 0, len(cluster.byID)); for id := range cluster.byID { ids = append(ids, int(id)) }; sort.Ints(ids)
	for round := 0; round < maxRounds; round++ {
		active := false; report.Rounds++
		for _, rawID := range ids {
			node := cluster.byID[uint32(rawID)]
			run := node.Runtime.Run(reductionsPerNode); report.Reductions += run.Reductions; if run.Reductions > 0 || run.Runnable > 0 { active = true }
			for _, signal := range node.Runtime.DrainRemoteSignals() {
				active = true; report.RoutedSignals++
				match signal {
				case kernel.RemoteExitSignal(from, to, reason): if destination, present := cluster.byID[to.Node]; present && cluster.connected(from.Node, to.Node) { destination.Runtime.SendExit(from, to, reason) }
				case kernel.RemoteDownSignal(source, to, reference, reason): if destination, present := cluster.byID[to.Node]; present && cluster.connected(source.Node, to.Node) { destination.Runtime.DeliverRemoteDown(source, to, reference, term.PIDValue(source), reason) }
				case kernel.RemoteDownNamedSignal(source, to, reference, reason): if destination, present := cluster.byID[to.Node]; present && cluster.connected(uint32(rawID), to.Node) { destination.Runtime.DeliverRemoteDown(term.PID{Node: uint32(rawID), Creation: 1}, to, reference, term.Tuple(term.MustAtom(source), term.MustAtom(node.Name)), reason) }
				}
			}
		}
		if !active { break }
	}
	return report
}

func (cluster *VirtualCluster) connected(from uint32, to uint32) bool {
	if from == to { return true }
	_, left := cluster.byID[from]; _, right := cluster.byID[to]
	return left && right && !cluster.disconnected[virtualRoute{from: from, to: to}]
}

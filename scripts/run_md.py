#!/usr/bin/env python3
"""
OpenMM molecular dynamics validation.
Input: PDB file
Output: RMSD trajectory CSV, first/last frame PDB, JSON report.
"""

import argparse
import json
import os
import sys
import time
import numpy as np

import openmm as mm
import openmm.app as app
import openmm.unit as unit
from openmm.app import PDBFile, PDBFixer, Modeller, ForceField
from openmm.app import PME, HBonds, NoCutoff
from openmm import LangevinMiddleIntegrator, MonteCarloBarostat
from pdbfixer import PDBFixer
import mdtraj as md

DT = 0.002  # picoseconds (2 fs)
FRICTION = 1.0  # 1/ps
TEMPERATURE = 300 * unit.kelvin
PRESSURE = 1.0 * unit.bar
BAROSTAT_FREQ = 25  # steps


def parse_args():
    p = argparse.ArgumentParser(description="OpenMM MD validation")
    p.add_argument("--pdb", required=True, help="Input PDB file")
    p.add_argument("--out-dir", required=True, help="Output directory")
    p.add_argument("--ns", type=float, default=50.0, help="Production length in ns (default: 50)")
    p.add_argument("--save-trajectory", action="store_true", help="Save full DCD trajectory")
    return p.parse_args()


def fix_pdb(pdb_path):
    fixer = PDBFixer(filename=pdb_path)
    fixer.findMissingResidues()
    fixer.findNonstandardResidues()
    fixer.replaceNonstandardResidues()
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=7.4)
    return fixer


def build_system(fixer):
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    modeller = Modeller(fixer.topology, fixer.positions)
    padding = 1.0 * unit.nanometers
    modeller.addSolvent(forcefield, model="tip3p", padding=padding, ionicStrength=0.15 * unit.molar)
    system = forcefield.createSystem(
        modeller.topology,
        nonbondedMethod=PME,
        nonbondedCutoff=1.0 * unit.nanometers,
        constraints=HBonds,
    )
    system.addForce(MonteCarloBarostat(PRESSURE, TEMPERATURE, BAROSTAT_FREQ))
    return system, modeller


def minimize(simulation, tol=10.0 * unit.kilojoules_per_mole / unit.nanometer, max_steps=2000):
    simulation.minimizeEnergy(maxIterations=max_steps, tolerance=tol)


def equilibrate(simulation, steps, is_nvt=False, reporters=None):
    if is_nvt:
        for force in simulation.system.getForces():
            if isinstance(force, MonteCarloBarostat):
                force.setFrequency(0)
    simulation.step(steps)
    if is_nvt:
        for force in simulation.system.getForces():
            if isinstance(force, MonteCarloBarostat):
                force.setFrequency(BAROSTAT_FREQ)


def get_rmsd_from_topology(topology, ref_coords, positions):
    ref_traj = md.Trajectory(
        np.array(ref_coords.value_in_unit(unit.nanometers)).reshape(1, -1, 3),
        md.Topology(),
    )
    pos = np.array(positions.value_in_unit(unit.nanometers)).reshape(1, -1, 3)
    traj = md.Trajectory(pos, md.Topology())

    ca_indices = [a.index for a in topology.atoms() if a.name == "CA"]
    if not ca_indices:
        ref_traj = ref_traj.atom_slice(range(ref_traj.n_atoms))
        traj = traj.atom_slice(range(traj.n_atoms))
    else:
        ref_traj = ref_traj.atom_slice(ca_indices)
        traj = traj.atom_slice(ca_indices)

    return md.rmsd(traj, ref_traj)[0]


def run_production(simulation, total_steps, report_interval, rmsd_ref_coords, topology):
    rmsd_values = []
    times_ns = []
    integrator = simulation.context.getIntegrator()
    n_steps = 0
    while n_steps < total_steps:
        chunk = min(report_interval, total_steps - n_steps)
        simulation.step(chunk)
        n_steps += chunk
        state = simulation.context.getState(getPositions=True)
        time_ns = (state.getTime().value_in_unit(unit.picoseconds)) / 1000.0
        rmsd = get_rmsd_from_topology(topology, rmsd_ref_coords, state.getPositions())
        rmsd_values.append(rmsd)
        times_ns.append(time_ns)
    return times_ns, rmsd_values


def save_pdb(simulation, path):
    state = simulation.context.getState(getPositions=True)
    with open(path, "w") as f:
        PDBFile.writeFile(simulation.topology, state.getPositions(), f)


def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    print(f"[MD] Loading PDB: {args.pdb}")
    pdb_id = os.path.splitext(os.path.basename(args.pdb))[0]

    print("[MD] Fixing missing atoms/hydrogens (PDBFixer)...")
    fixer = fix_pdb(args.pdb)

    print("[MD] Building system (AMBER14, TIP3P, 1.0nm padding, 0.15M ions)...")
    system, modeller = build_system(fixer)

    integrator = LangevinMiddleIntegrator(TEMPERATURE, FRICTION / unit.picosecond, DT * unit.picoseconds)
    simulation = app.Simulation(modeller.topology, system, integrator)

    platform = mm.Platform.getPlatformByName("CUDA")
    props = {"Precision": "mixed"}
    simulation.context.setPlatform(platform)
    simulation.context.setProperties(props)
    print(f"[MD] Platform: {platform.getName()}")

    simulation.context.setPositions(modeller.positions)

    print("[MD] Energy minimization...")
    t0 = time.time()
    minimize(simulation)
    print(f"      done in {time.time() - t0:.1f}s")

    print("[MD] NVT equilibration (100ps)...")
    equilibrate(simulation, 50000, is_nvt=True)
    print("[MD] NPT equilibration (100ps)...")
    equilibrate(simulation, 50000, is_nvt=False)

    print("[MD] Saving reference frame...")
    ref_state = simulation.context.getState(getPositions=True)
    ref_pdb = os.path.join(args.out_dir, f"{pdb_id}_ref.pdb")
    with open(ref_pdb, "w") as f:
        PDBFile.writeFile(modeller.topology, ref_state.getPositions(), f)

    total_ps = args.ns * 1000.0
    total_steps = int(total_ps / DT)
    report_interval = max(1000, total_steps // 500)

    print(f"[MD] Production: {args.ns}ns ({total_steps:,} steps, 2fs timestep)...")
    t0 = time.time()

    n_atoms = modeller.topology.getNumAtoms()
    rmsd_ref = np.array(ref_state.getPositions().value_in_unit(unit.nanometers))

    times_ns, rmsd_values = run_production(
        simulation, total_steps, report_interval, rmsd_ref, modeller.topology
    )
    elapsed = time.time() - t0
    ns_per_day = (args.ns / elapsed) * 86400
    print(f"      done in {elapsed:.1f}s ({ns_per_day:.0f} ns/day)")

    print("[MD] Saving outputs...")
    last_pdb = os.path.join(args.out_dir, f"{pdb_id}_last.pdb")
    save_pdb(simulation, last_pdb)
    ref_pdb_out = os.path.join(args.out_dir, f"{pdb_id}_ref.pdb")
    save_pdb(simulation, ref_pdb_out)

    csv_path = os.path.join(args.out_dir, "rmsd.csv")
    with open(csv_path, "w") as f:
        f.write("time_ns,rmsd_nm\n")
        for t, r in zip(times_ns, rmsd_values):
            f.write(f"{t:.4f},{r:.4f}\n")

    final_rmsd = rmsd_values[-1] if rmsd_values else 0.0
    mean_rmsd = np.mean(rmsd_values[-200:]) if len(rmsd_values) >= 200 else np.mean(rmsd_values)
    rmsd_std = np.std(rmsd_values[-200:]) if len(rmsd_values) >= 200 else np.std(rmsd_values)

    print(f"      Final RMSD : {final_rmsd:.3f} nm")
    print(f"      Mean RMSD  : {mean_rmsd:.3f} nm")
    print(f"      Std RMSD   : {rmsd_std:.3f} nm")

    stability = "stable"
    if final_rmsd > 0.5 or np.std(rmsd_values) > 0.3:
        stability = "unstable"
    elif final_rmsd > 0.35:
        stability = "marginal"

    report = {
        "input_pdb": os.path.abspath(args.pdb),
        "n_atoms": n_atoms,
        "simulation_ns": args.ns,
        "platform": platform.getName(),
        "wall_time_s": round(elapsed, 1),
        "ns_per_day": round(ns_per_day, 1),
        "rmsd_final_nm": round(final_rmsd, 4),
        "rmsd_mean_last200_nm": round(mean_rmsd, 4),
        "rmsd_std_last200_nm": round(rmsd_std, 4),
        "stability": stability,
    }

    report_path = os.path.join(args.out_dir, "report.json")
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)

    print(f"      Stability  : {stability}")
    print(f"[MD] All outputs saved to {args.out_dir}")
    print(json.dumps(report))


if __name__ == "__main__":
    main()

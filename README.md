# JetClass-II dataset generation

This repository contains the event-generation and Delphes-production scripts used for the [JetClass-II dataset](https://huggingface.co/datasets/jet-universe/jetclass2).

## Repository layout

```text
.
├── run.sh                  # End-to-end MadGraph/Pythia/Delphes production
├── gen_configs/            # Process-specific generation configurations
├── delphes_cards/          # Delphes detector cards
└── delphes_analyzers/      # ROOT macro to convert Delphes ROOT files to ntuples
```

## Software needed on lxplus alma9

The current scripts expect:

- `MadGraph5_aMC@NLO` with `pythia8`, `hepmc`, and `lhapdf6` installed inside `HEPTools`
- `LHAPDF6` PDF data available to MadGraph/Pythia
- `Delphes`
- `ROOT` for the ntuple-making step

The examples below use EL9-compatible software on lxplus.

### 1. Load a ROOT/compiler environment

```bash
source /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-el9-gcc13-opt/setup.sh
```

### 2. Install MadGraph + internal Pythia8/HepMC/LHAPDF

```bash
cd /path/where/you/want/the/tools
wget https://launchpad.net/mg5amcnlo/2.0/2.9.x/+download/MG5_aMC_v2.9.18.tar.gz
tar -xzf MG5_aMC_v2.9.18.tar.gz
cd MG5_aMC_v2_9_18

cat > install_mg5.dat <<'MG5'
install pythia8
install hepmc
install lhapdf6
install model 2HDM
exit
MG5

./bin/mg5_aMC install_mg5.dat
```

Notes:

- The existing JetClass-II resonance configs use the `2HDM` model.
- The provided `pp -> ZZ` prototype added in this repository uses the Standard Model (`import model sm`) and does not need any extra UFO model.
- If you prefer a site-wide LHAPDF installation, point `LHAPDFCONFIG` and `LHAPDF_DATA_PATH` in `run.sh` to that installation instead of the internal MG5 copy.

### 3. Install Delphes

```bash
cd /path/where/you/want/the/tools
wget http://cp3.irmp.ucl.ac.be/downloads/Delphes-3.5.0.tar.gz
tar -xzf Delphes-3.5.0.tar.gz
cd Delphes-3.5.0
make -j"$(nproc)"
ln -sf /eos/cms/store/group/upgrade/delphes/PhaseII/MinBias_100k.pileup MinBias_100k.pileup
```

The production script expects `MinBias_100k.pileup` to be available directly under `${DELPHES_PATH}`.

## Configure `run.sh`

Edit the paths near the top of `/home/runner/work/jetclass2_generation/jetclass2_generation/run.sh`:

```bash
MG5_PATH=/absolute/path/to/MG5_aMC_v2_9_18
DELPHES_PATH=/absolute/path/to/Delphes-3.5.0
OUTPUT_PATH=/absolute/path/to/output_dir
LHAPDFCONFIG=/absolute/path/to/lhapdf-config
LHAPDF_DATA_PATH=/absolute/path/to/share/LHAPDF
PYTHIA8DATA=/absolute/path/to/MG5_aMC_v2_9_18/HEPTools/pythia8/share/Pythia8/xmldoc
```

Optional override:

```bash
export DELPHES_CARD_PATH=/absolute/path/to/custom_delphes_card.tcl
```

If `DELPHES_CARD_PATH` is not set, the script uses `delphes_cards/delphes_card_CMS_JetClassII_onlyFatJet.tcl`.

## Run MadGraph + Pythia + Delphes

From anywhere on the machine:

```bash
/home/runner/work/jetclass2_generation/jetclass2_generation/run.sh [process_name] [num_tot_events] [num_events_per_gen_step] [job_num]
```

Examples:

```bash
/home/runner/work/jetclass2_generation/jetclass2_generation/run.sh jetclass2/train_higgs2p 100 50 0
/home/runner/work/jetclass2_generation/jetclass2_generation/run.sh jetclass2/train_zz 100 50 0
```

Important runtime notes:

- `num_tot_events` must be divisible by `num_events_per_gen_step`.
- Output ROOT files are written to `${OUTPUT_PATH}/[process_name]/events_delphes_[job_num].root`.
- The current Higgs-like configs sample one random line from `mg5_params.dat` for each generation batch.
- `run.sh` creates a temporary work directory under `${OUTPUT_PATH}` and removes it after a successful job.

### Included process configurations

| Process | Command example | Notes |
| --- | --- | --- |
| `jetclass2/train_higgs2p` | `./run.sh jetclass2/train_higgs2p 100000 100 [job_num]` | Neutral resonance pair prototype |
| `jetclass2/train_higgspm2p` | `./run.sh jetclass2/train_higgspm2p 100000 100 [job_num]` | Charged resonance pair prototype |
| `jetclass2/train_higgs4p` | `./run.sh jetclass2/train_higgs4p 100000 100 [job_num]` | 4-parton resonance prototype |
| `jetclass2/train_qcd` | `./run.sh jetclass2/train_qcd 100000 100 [job_num]` | Pythia8-only QCD production |
| `jetclass2/train_zz` | `./run.sh jetclass2/train_zz 100000 100 [job_num]` | New Standard Model `pp -> ZZ` prototype at 13 TeV |

## How process configs are structured

A MadGraph+Pythia config directory may contain:

```text
mg5_step1.dat         # MadGraph process definition
mg5_step2_templ.dat   # MadGraph launch commands, with $NEVENT/$SEED placeholders
mg5_params.dat        # Optional parameter scan file; one line is sampled per batch
py8.dat               # Pythia8 card used by MG5aMC_PY8_interface
```

The default wrapper is `/home/runner/work/jetclass2_generation/jetclass2_generation/gen_configs/run_gen_default.sh`.

## New `pp -> ZZ` prototype

The prototype configuration is located in:

```text
/home/runner/work/jetclass2_generation/jetclass2_generation/gen_configs/jetclass2/train_zz
```

It uses:

- `import model sm`
- `generate p p > z z`
- `set ebeam1 6500` and `set ebeam2 6500` for 13 TeV proton-proton collisions
- default Pythia8 Standard Model `Z` decays

This makes it a simple starting point for LHC diboson studies on top of the existing JetClass-II workflow.

## Produce ntuples from Delphes output

The Delphes analyzer lives in `/home/runner/work/jetclass2_generation/jetclass2_generation/delphes_analyzers`.

```bash
cd /home/runner/work/jetclass2_generation/jetclass2_generation/delphes_analyzers
source /cvmfs/sft.cern.ch/lcg/views/LCG_104/x86_64-el9-gcc13-opt/setup.sh
export ROOT_INCLUDE_PATH=$ROOT_INCLUDE_PATH:/cvmfs/sft.cern.ch/lcg/releases/delphes/3.5.1pre09-9fe9c/x86_64-el9-gcc13-opt/include

root -b -q 'makeNtuples.C++("events_delphes_higgs2p_example.root", "out.root", "JetPUPPIAK8", "GenJetAK8", true)'
```

Macro signature:

```cpp
void makeNtuples(TString inputFile,
                 TString outputFile,
                 TString jetBranch = "JetPUPPIAK8",
                 TString genjetBranch = "GenJetAK8",
                 bool assignQCDLabel = false,
                 bool debug = false)
```

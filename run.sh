#!/bin/bash -x

usage() {
    cat <<'USAGE'
Usage: ./run.sh [process_name] [num_tot_events] [num_events_per_gen_step] [job_num]

Example:
  ./run.sh jetclass2/train_higgs2p 100 50 0

Optional environment override:
  DELPHES_CARD_PATH=/absolute/path/to/card.tcl ./run.sh ...
USAGE
}

if [ $# -ne 4 ]; then
    usage >&2
    exit 1
fi

PROC=$1
NEVENT=$2
NEVENT_GEN=$3
JOBNUM=$4
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)

if ! [[ "$NEVENT" =~ ^[0-9]+$ && "$NEVENT_GEN" =~ ^[0-9]+$ && "$JOBNUM" =~ ^[0-9]+$ ]]; then
    echo "NEVENT, NEVENT_GEN, and JOBNUM must be non-negative integers." >&2
    exit 1
fi

if [ "$NEVENT" -eq 0 ] || [ "$NEVENT_GEN" -eq 0 ]; then
    echo "NEVENT and NEVENT_GEN must be larger than zero." >&2
    exit 1
fi

if [ $((NEVENT % NEVENT_GEN)) -ne 0 ]; then
    echo "NEVENT must be divisible by NEVENT_GEN so that all requested events are produced." >&2
    exit 1
fi

# Setup environment

# ============ basic configuration ============
MG5_PATH=/PATH/TO/MG5_aMC_v3_5_13
DELPHES_PATH=/PATH/TO/Delphes-3.5.0
OUTPUT_PATH=/PATH/TO/OUTPUT_DIR

## some env variables are required by the softwares
LHAPDFCONFIG=/PATH/TO/lhapdf-config
LHAPDF_DATA_PATH=/PATH/TO/share/LHAPDF
PYTHIA8DATA=/PATH/TO/MG5_aMC_v3_5_13/HEPTools/pythia8/share/Pythia8/xmldoc

## fixed configuration
GENCFG_PATH="$SCRIPT_DIR/gen_configs"
DEFAULT_DELPHES_CARD_PATH="$SCRIPT_DIR/delphes_cards/delphes_card_CMS_JetClassII_onlyFatJet.tcl"
DELPHES_CARD_PATH=${DELPHES_CARD_PATH:-$DEFAULT_DELPHES_CARD_PATH}
# =============================================

for required_var in MG5_PATH DELPHES_PATH OUTPUT_PATH LHAPDFCONFIG LHAPDF_DATA_PATH PYTHIA8DATA; do
    value=${!required_var}
    if [[ "$value" == /PATH/TO/* ]]; then
        echo "Please configure $required_var in $SCRIPT_DIR/run.sh before running." >&2
        exit 1
    fi
done

if [ ! -d "$GENCFG_PATH/$PROC" ]; then
    echo "Generation config not found: $GENCFG_PATH/$PROC" >&2
    exit 1
fi

if [ ! -x "$MG5_PATH/bin/mg5_aMC" ]; then
    echo "MadGraph executable not found: $MG5_PATH/bin/mg5_aMC" >&2
    exit 1
fi

if [ ! -x "$DELPHES_PATH/DelphesHepMC2" ]; then
    echo "Delphes executable not found: $DELPHES_PATH/DelphesHepMC2" >&2
    exit 1
fi

if [ ! -f "$DELPHES_CARD_PATH" ]; then
    echo "Delphes card not found: $DELPHES_CARD_PATH" >&2
    exit 1
fi

if [ ! -f "$DELPHES_PATH/MinBias_100k.pileup" ]; then
    echo "Pileup file not found: $DELPHES_PATH/MinBias_100k.pileup" >&2
    exit 1
fi

mkdir -p "$OUTPUT_PATH"
OUTPUT_PATH=$(realpath "$OUTPUT_PATH")

# Create workdir
RANDSTR=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10; echo)
WORKDIR="$OUTPUT_PATH/workdir_$(date +%y%m%d-%H%M%S)_${RANDSTR}_$(echo "$PROC" | sed 's/\//_/g')_$JOBNUM"
mkdir -p "$WORKDIR"

cd "$WORKDIR"

generate_delphes(){
    # all GEN production logic inside the gen_configs folder
    # generate GEN events
    rm -f events.hepmc
    MG5_PATH="$MG5_PATH" ./run_gen.sh "$NEVENT_GEN"

    # run delphes
    ln -s "$DELPHES_PATH/MinBias_100k.pileup" .
    rm -f events_delphes.root
    "$DELPHES_PATH/DelphesHepMC2" "$DELPHES_CARD_PATH" events_delphes.root events.hepmc
    return $?
}

# generate delphes, in a batch of NEVENT_GEN
nbatch=$((NEVENT / NEVENT_GEN))

for ((i=0; i<nbatch; i++)); do

    echo "Batch: $i"

    # copy genpack if not exist
    cd "$WORKDIR"
    if [ ! -d "proc_base" ]; then
        mkdir proc_base
        cp -r "$GENCFG_PATH/$PROC"/* proc_base/
        # if genpack does not have a run_gen.sh, use the default
        if [ ! -f "proc_base/run_gen.sh" ]; then
            cp "$GENCFG_PATH/run_gen_default.sh" proc_base/run_gen.sh
        fi
    fi
    cd "$WORKDIR/proc_base"

    generate_delphes

    # if return code is 0
    if [ $? -eq 0 ]; then
        # successful
        mv events_delphes.root "$WORKDIR/events_delphes_$i.root"
    fi
    cd "$WORKDIR"

    # intermediate file merging for every 100 batches
    if [ $(((i+1) % 100)) -eq 0 ]; then
        hadd -f "$WORKDIR/merged_events_delphes_$i.root" "$WORKDIR"/events_delphes_*.root
        if [ $? -eq 0 ]; then
            rm -f "$WORKDIR"/events_delphes_*.root
        fi
    fi

done

# combine all root
if [ "$nbatch" -eq 1 ]; then
    mv "$WORKDIR/events_delphes_0.root" events_delphes.root
else
    hadd -f events_delphes.root "$WORKDIR"/*.root
fi
mkdir -p "$OUTPUT_PATH/$PROC"

# transfer the file
mv -f events_delphes.root "$OUTPUT_PATH/$PROC/events_delphes_$JOBNUM.root"

# remove workspace
rm -rf "$WORKDIR"

echo -e "\033[1mJob done. Generated $NEVENT events for $PROC.\033[0m"
echo -e "\033[1mDelphes file path: $OUTPUT_PATH/$PROC/events_delphes_$JOBNUM.root\033[0m"

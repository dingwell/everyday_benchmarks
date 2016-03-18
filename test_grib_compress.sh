#!/bin/bash
# This script will test several compression tools on grib files
# It will output processing times and compression ratios
set -e

FILES=$@

total_size_kB(){
  # Takes a list of files as argument
  du -B kB -c $@|tail -n1|sed 's/kB.*//'

  # WARNING: it takes time before the new size shows up
  # don't use this function on newly created or modified files!
}

get_suffix(){
  # Returns the default suffix for a given compression tool
  # Takes one argument (the compression tool)
  CMD="$1"
  if ! command -v $CMD >/dev/null 2>&1; then
    echo "Command: '$CMD' not found, aborting"
    exit 1
  fi

  # Create an empty file:
  TMPFILE=${0##*/}-${PID}.tmp
  touch $TMPFILE
  $CMD $TMPFILE
  NEWFILE=$(ls $TMPFILE.*)
  SUFFIX=$(echo "$NEWFILE"|sed 's/'"$TMPFILE"'\.//')
  echo $SUFFIX
  rm $NEWFILE
}


get_compr_ratio_gz(){
  # Takes a list of gzip-compressed files as argument:
  gzip -l $@ |tail -n1|egrep -o '[0-9]+.[0-9]%'
}

get_compr_ratio_bz2(){
  # Takes a list of bzip2-compressed files as argument
  local COMPR_SIZE=$(cat $@|wc -c)  # Size in bytes
  local ORIG_SIZE=$(bzcat $@|wc -c)
  local RATIO=$(echo "scale=1;100-100*$COMPR_SIZE/$ORIG_SIZE"|bc)
  echo "$RATIO%"
}

get_compr_ratio_xz(){
  # Takes a list of xz-compressed files as argument
  local COMPR_SIZE=$(cat $@|wc -c)  # Size in bytes
  local ORIG_SIZE=$(xzcat $@|wc -c)
  local RATIO=$(echo "scale=1;100-100*$COMPR_SIZE/$ORIG_SIZE"|bc)
  echo "$RATIO%"
}


test_compression(){
  # Takes compression tool as argument
  # $1    - compression command
  # $2    - decompression command
  # Needs the following variables:
  # FILES         - list of files to compress
  # KB_BEFORE     - decompressed size (no suffix)
  CMD="$1"
  UNCMD="$2"

  #get_suffix $CMD
  SUFFIX=$(get_suffix "$CMD")  # Get compression suffix
  
  # Ensure that no already compressed files exist:
  if ls *.$SUFFIX &> /dev/null; then
    echo "Found some .$SUFFIX files in working directory!"
    echo "Please remove before running test!"
    exit 1
  fi

  # Begin compression test:
  echo "Testing '$CMD' (decomp.: $UNCMD; suffix: '.$SUFFIX')"
  T0=$SECONDS
  $CMD $FILES
  T1=$SECONDS

  DT=$(( T1-T0 ))
  echo "Compression time = ${DT}s"
  
  COMP_RATIO=$(get_compr_ratio_$SUFFIX *.$SUFFIX)
  echo "Compression ratio = $COMP_RATIO"

  # Begin decompression test:
  T0=$SECONDS
  $UNCMD *.$SUFFIX
  T1=$SECONDS
  DT=$(( T1-T0 ))
  echo "Decompression time = ${DT}s"
}


KB_BEFORE=$(total_size_kB $FILES)  # With unit

echo "Total uncompressed size = $KB_BEFORE kB"

# Test compression:
test_compression gzip gunzip
test_compression bzip2 bunzip2
test_compression xz unxz
# TODO: format output as a table e.g.:
# CMD           |  gzip |  lzo  | bzip2 |   xz  |
# ----------------------------------------------+
# LEV1: RATIO   | XX.X% | XX.X% | XX.X% | XX.X% |
# LEV1: TIME [s]| XXX s | XXX s | XXX s | XXX s |
# ----------------------------------------------+
# LEV2: RATIO   |
# LEV2: TIME [s]|
# LEV3: RATIO   |
# LEV3: TIME [s]|
# LEV4: RATIO   |
# LEV4: TIME [s]|
# LEV5: RATIO   |
# LEV5: TIME [s]|
# LEV6: RATIO   |
# LEV6: TIME [s]|
# LEV7: RATIO   |
# LEV7: TIME [s]|
# LEV8: RATIO   |
# LEV8: TIME [s]|
# LEV9: RATIO   |
# LEV9: TIME [s]|

#!/bin/bash

#  
#  Copyright 2016 Adam Dingwell <adam@YOGHURT>
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are
#  met:
#  
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following disclaimer
#    in the documentation and/or other materials provided with the
#    distribution.
#  * Neither the name of the  nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#  
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#  

# This script will test several compression tools on grib files
# It will output processing times and compression ratios
set -e

FILES=$@

# Settings:
# (TODO: allow setting this from the CLI)
DO_GZIP=true
DO_BZIP=true
DO_XZ=true
DO_LZOP=true

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
  gzip -l $@ |tail -n1|egrep -o '[0-9]+.[0-9]%' \
    |sed 's/%/\\%/'
}

get_compr_ratio_lzo(){
  # Takes a list of .lz files as argument
  TMP=$(lzop -l $@ |tail -n1|egrep -o '[0-9]+.[0-9]%')
  TMP=$(echo $TMP|sed 's/%//')  # Remove '%'
  local RATIO=$(echo "scale=1; 100-$TMP"|bc)
  echo "$RATIO"'\%'
}

get_compr_ratio_bz2(){
  # Takes a list of bzip2-compressed files as argument
  local COMPR_SIZE=$(cat $@|wc -c)  # Size in bytes
  local ORIG_SIZE=$(bzip2 -dc $@|wc -c)
  local RATIO=$(echo "scale=1;100-100*$COMPR_SIZE/$ORIG_SIZE"|bc)
  echo "$RATIO"'\%'
}

get_compr_ratio_xz(){
  # Takes a list of xz-compressed files as argument
  local COMPR_SIZE=$(cat $@|wc -c)  # Size in bytes
  local ORIG_SIZE=$(xz -dc $@|wc -c)
  local RATIO=$(echo "scale=1;100-100*$COMPR_SIZE/$ORIG_SIZE"|bc)
  echo "$RATIO"'\%'
}

test_compression(){
  # Takes compression tool as argument
  # $1    - compression command
  # $2    - compression level (1-9)
  # Needs the following variables: The pipe and plus characters can be used to visually separate columns although this is not needed. Multiple separator lines after another are treated as one separator line.
  # FILES         - list of files to compress

  local CMD="$1"
  local LVL="$2"

  #get_suffix for $CMD
  SUFFIX=$(get_suffix "$CMD")  # Get compression suffix

  # Ensure that no already compressed files exist:
  if ls *.$SUFFIX &> /dev/null; then
    echo "Found some .$SUFFIX files in working directory!" 1>&2
    echo "Please remove before running test!" 1>&2
    exit 1
  fi
  
  # Begin compression test:
  T0=$SECONDS
  if [[ $CMD == "lzop" ]]; then 
    $CMD -U -$LVL $FILES  # Run command (U=delete original files)
  else  # Most tools will remove the uncompressed files by default
    $CMD -$LVL $FILES # Run compress command 
  fi
  T1=$SECONDS
  DT_COM=$(( T1-T0 ))
  #echo "Compression time = ${DT}s"
  
  COMP_RATIO=$(get_compr_ratio_$SUFFIX *.$SUFFIX)
  #echo "Compression ratio = $COMP_RATIO"

  # Begin decompression test:
  T0=$SECONDS
  if [[ $CMD == "lzop" ]]; then
    $CMD -d -U *.$SUFFIX  # Run command (U=delete original files)
  else  # Most tools will remove the uncompressed files by default
    $CMD -d *.$SUFFIX  # Run decompress command
  fi
  T1=$SECONDS
  DT_DEC=$(( T1-T0 ))
  #echo "Decompression time = ${DT}s"
  echo "$COMP_RATIO ${DT_COM}s ${DT_DEC}s"
}

print_header(){
  local HEADER='        & CMD        '
  if $DO_GZIP; then
    HEADER="$HEADER"'& gzip '
  fi
  if $DO_LZOP; then
    HEADER="$HEADER"'& lzop '
  fi
  if $DO_BZIP; then
    HEADER="$HEADER"'& bzip2 '
  fi
  if $DO_XZ; then
    HEADER="$HEADER"'& xz '
  fi
  local NWORDS=$(echo $HEADER|wc -w)
  local NCOLS=$(echo "$NWORDS/2-1"|bc)
  echo '\hline'
  echo '\begin{tabular}{ll*{'"$NCOLS"'}{c}}'
  echo '\hline'
}

print_footer(){
  echo '\end{tabular}'
}

KB_BEFORE=$(total_size_kB $FILES)  # With unit

echo "Total uncompressed size = $KB_BEFORE kB"
echo "'RATIO' below is the amount of space _saved_"

print_header
# Perform tests:
for lvl in $(seq 9); do
  RATIOS=""
  C_TIMES=""
  U_TIMES=""
  if $DO_GZIP; then
    A="$(test_compression gzip $lvl)"
    RATIOS="$RATIOS & $(echo $A|awk '{print $1}')"
    C_TIMES="$C_TIMES & $(echo $A|awk '{print $2}')"
    U_TIMES="$U_TIMES & $(echo $A|awk '{print $3}')"
  fi
  if $DO_LZOP; then
    A="$(test_compression lzop $lvl)"
    RATIOS="$RATIOS & $(echo $A|awk '{print $1}')"
    C_TIMES="$C_TIMES & $(echo $A|awk '{print $2}')"
    U_TIMES="$U_TIMES & $(echo $A|awk '{print $3}')"
  fi
  if $DO_BZIP; then
    A="$(test_compression bzip2 $lvl)"
    RATIOS="$RATIOS & $(echo $A|awk '{print $1}')"
    C_TIMES="$C_TIMES & $(echo $A|awk '{print $2}')"
    U_TIMES="$U_TIMES & $(echo $A|awk '{print $3}')"
  fi
  if $DO_XZ; then
    A="$(test_compression xz $lvl)"
    RATIOS="$RATIOS & $(echo $A|awk '{print $1}')"
    C_TIMES="$C_TIMES & $(echo $A|awk '{print $2}')"
    U_TIMES="$U_TIMES & $(echo $A|awk '{print $3}')"
  fi
  RATIOS="$RATIOS"'\\'
  C_TIMES="$C_TIMES"'\\'
  U_TIMES="$U_TIMES"'\\'
  echo "        & RATIO      $RATIOS"
  echo "LEV$lvl    & COMP. TIME $C_TIMES"
  echo "        & DEC.  TIME $U_TIMES"
  echo '\hline'
done
print_footer

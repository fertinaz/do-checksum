#!/bin/bash
set -e

# Define numerical values
((MAXSIZE=(2**63)-1));
((KB=1024**1));
((MB=1024**2));
((GB=1024**3));

SOURCE=<sourcedir>
TARGET=<targetdir>

get_file_hash() {
    $HASHFUNC "$1"
}

get_file_size() {
    stat -c %s "$1" 
}

set_hash_func() {
    HASHFUNC=`which "$1"`
}

# TODO: Check if bc exists
print_human_readable_bytes() {
    nhumanbytes=0
    if [[ $1 -lt $KB ]] ; then echo "Total clean-up space is $1 bytes." ; fi
    if [[ $1 -ge $KB && $1 -lt $MB ]] ; then nhumanbytes=$(echo "scale=2 ; $1/$KB" | bc) ; echo "Total clean-up space is $nhumanbytes kilobytes." ; fi
    if [[ $1 -ge $MB && $1 -lt $GB ]] ; then nhumanbytes=$(echo "scale=2 ; $1/$MB" | bc) ; echo "Total clean-up space is $nhumanbytes megabytes." ; fi
    if [[ $1 -ge $GB ]] ; then nhumanbytes=$(echo "scale=2 ; $1/$GB" | bc) ; echo "Total clean-up space is $nhumanbytes gigabytes." ; fi
}

remove_file() {
    rm -f "$1"
}

# Set default file extensiom
EXT="pdf"

# Set default hash method
hashfunc="md5sum"

# Disable dry-run by default
dryrun="0"

# Print stats flag and file counters
isprint="0"
nsourcefiles=0
ntargetfiles=0
nfoundfiles=0
ndeletedfiles=0

# Total number of bytes cleaned-up
ndeletedbytes=0
targetfilesize=0

# Flags for quiet and verbose modes
isquiet="0"
isverbose="0"

# Parse input arguments
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
  -h | --help )
    echo "do-checksum reads each file in a source directory and deletes the identical ones in the target directory."
    echo
    echo "Usage: ./do-checksum [OPTIONS]"
    echo
    echo "Options are:"
    echo "    -d | --dry-run                Run this tool without deleting files."
    echo "    -e | --extension              Specify the file extension to search. The default is pdf."
    echo "    -h | --help                   Print this message."
    echo "    -p | --print-statistics       Print statistical information before exiting."
    echo "    -q | --quiet                  Run in quiet mode."
    echo "    -s | --sha512sum              Use sha512sum for hashing. Otherwise default method is md5sum."
    echo "    -v | --verbose                Verbose mode.  Causes do-checksum to print debugging messages about its progress."
    echo "    -V | --version                Show version."
    exit 1
    ;;
  -V | --version )
    echo "version: 0.1.1"
    exit 1
    ;;
  -v | --verbose )
    isverbose="1"
    ;;
  -s | --sha512sum )
    hashfunc="sha512sum" # Use md5sum if not set
    ;;
  -q | --quiet )
    isquiet="1"
    ;;
  -p | --print-statistics )
    isprint="1"
    ;;
  -e | --extension )
    shift ; EXT="$1"
    ;;
  -d | --dry-run )
    dryrun="1"
    ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

# Check if source & target dirs do exist
if [[ ! -e $SOURCE ]] ; then echo "Source directory $SOURCE does not exist. Exiting..." ; exit 1 ; fi
if [[ ! -e $TARGET ]] ; then echo "Target directory $TARGET does not exist. Exiting..." ; exit 1 ; fi

# Quit if quiet and verbose modes are both enabled
if [[ $isquiet == "1" && $isverbose == "1" ]] ; then 
    echo "Please do not enable quiet and verbose modes at the same time. Exiting..."
    exit 1
fi

# Check number of files before running checksums
while IFS= read -r -d '' sourcefile; 
do
    nsourcefiles=$((nsourcefiles + 1))
done < <(find $SOURCE -type f -iname "*.${EXT}" -print0)

while IFS= read -r -d '' targetfile; 
do
    ntargetfiles=$((ntargetfiles + 1))
done < <(find $TARGET -type f -iname "*.${EXT}" -print0)
    
echo "There are $nsourcefiles $EXT files in $SOURCE"
echo "There are $ntargetfiles $EXT files in $TARGET"
echo

# Exit if no files are found
if [[ $nsourcefiles -eq 0 ]] ; then echo "No files found in the source directory.  Exiting..." ; exit 1 ; fi
if [[ $ntargetfiles -eq 0 ]] ; then echo "No files found in the target directory.  Exiting..." ; exit 1 ; fi

set_hash_func "$hashfunc"

echo "Starting reading checksums using ${HASHFUNC}..."
if [[ $dryrun == "1" ]] ; then
    echo "Running in dry-run mode..."
fi
sleep 3

nsourcefiles=0
while IFS= read -r -d '' sourcefile; 
do
    sourcehash=$(get_file_hash "$sourcefile" | awk '{print $1}')
    nsourcefiles=$((nsourcefiles + 1))

    # Print each source file only in verbose mode
    if [[ $isquiet == "0" && $isverbose == "1" ]] ; then
        echo "+ File index $nsourcefiles. File name: $sourcefile has hash $sourcehash"
    fi

    while IFS= read -r -d '' targetfile; 
    do
        targethash=$(get_file_hash "$targetfile" | awk '{print $1}')
        if [[ $sourcehash == $targethash && $sourcefile != $targetfile ]] ; then
            
            # Print source file in the non-verbose mode
            if [[ $isquiet == "0" && $isverbose == "0" ]] ; then
                echo "+ File index $nsourcefiles. File name: $sourcefile has hash $sourcehash"
            fi
            
            nfoundfiles=$((nfoundfiles + 1))
            targetfilesize=$(get_file_size "$targetfile")

            # Print this information regardless of verbosity
            if [[ $isquiet == "0" ]] ; then
                echo "  - Found file: $targetfile with hash $targethash" 
            fi

            # Delete only if not in dry-run mode
            if [[ $dryrun == "0" ]] ; then
                remove_file "$targetfile"
                if [[ $? -eq 0 ]] ; then
                    # Print this information regardless of verbosity
                    if [[ $isquiet == "0" ]] ; then
                        echo "  - File deleted successfully."
                    fi
                else
                    echo "An error occurred. Exiting..."
                    exit 1
                fi
                if [[ $isprint == 1 ]] ; then
                    ndeletedfiles=$((ndeletedfiles + 1))
                    # if (MAXSIZE - ndeletedbytes) < targetfilesize -> stop counting bytes
                    ndeletedbytes=$((ndeletedbytes + $targetfilesize))
                fi
                if [[ $isquiet == "0" && $isverbose == "0" ]] ; then
                    echo
                fi
            fi
        fi      
    done < <(find $TARGET -type f -iname "*.${EXT}" -print0)
    if [[ $isquiet == "0" && $isverbose == "1" ]] ; then
        echo
    fi
done < <(find $SOURCE -type f -iname "*.${EXT}" -print0)

# Print statistical information
if [[ $isprint == 1 ]] ; then
    if [[ $nfoundfiles -eq 0 ]] ; then
        echo "No files are found."
    else
        echo "$nfoundfiles files are found."
    fi
    if [[ $ndeletedfiles -eq 0 ]] ; then
        echo "No files are deleted."
    else
        echo "$ndeletedfiles files are deleted."
        print_human_readable_bytes $ndeletedbytes
    fi
fi


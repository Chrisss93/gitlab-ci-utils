#!/bin/sh

case $1 in
    "load")
        [ -d "$3" ] && mkdir -p $(dirname $2) && mv $3 $2 && echo "loaded compiled artifacts to $2 from $3"
        exit 0
    ;;
    "save")
    ;;
    *) echo "First argument must be either 'load' or 'save'." && exit 1
    ;;
esac

shift 1


if [ "$#" -lt 4 ]
then echo "No crates to save" && exit 0
fi

from=$1
to=$2
flag=$3
shift 3

transitive=$(cargo tree -e $flag $(echo "$@" | xargs -d ' ' -I {} echo -p {}) | grep -o '─ .* v' | awk '{print $2}')
full=$(echo $transitive $@ | tr ' ' '\n' | sed 's/@.*//' | sort -ru)

rm -rf $to
mkdir -p $to/deps $to/.fingerprint $to/build

for crate in $full; do
    dep=$(echo "$crate" | sed 's/-/_/g')
    mv $from/deps/$dep-* $from/deps/lib$dep-* $to/deps
    mv $from/.fingerprint/$crate-* $to/.fingerprint
    if ls $from/build/$crate-* 1> /dev/null 2>&1; then
        mv -f $from/build/$crate-* $to/build
    fi
done

echo "saved the following crates' compiled artifacts to $to: $full"

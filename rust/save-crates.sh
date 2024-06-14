#!/bin/sh

which jq rustc cargo || (echo "jq, rustc and cargo must first be installed" && exit 2)

while getopts ":t:j:p:h" opt; do
    case $opt in
        t)
            build_target="$OPTARG"
            ;;
        j)
            json_diagnostic="$OPTARG"
            [ -f "$json_diagnostic" ] || (
                echo "option -j=$OPTARG must refer to a json-render-diagnostics file" && exit 2
            )
            ;;
        p)
            profile="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 2
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            exit 2
            ;;
        h)
            echo "\
            Usage:
                save-crates.sh -t [target-triple] -j [json-render-diagnostics-file] -p [profile] [to] [crates]...

            Description:
                For a rust project that directly or transitively depends on [crates], this script will cache those
                [crates]'s compiled artifacts (and the compiled artifacts of their dependencies) to the destination:
                [to]. This performs best using the -j option which should be a json file (specifically the stdout of
                running basic cargo commands like:
                \`cargo check/build/test --message-format=json-render-diagnostics\`
                ).
                
                Without the -j option, the script will make a best-attempt at caching compiled artifacts, however it
                may end up caching more than necessary since, without [json-render-diagnostics-file], the
                compiled artifacts' filenames are not fully specified and must be assumed.  Without the -j option,
                the -p option for identifying the cargo profile (i.e. debug/release, etc.) is mandatory.

                If the compiled artifacts have been generated using a \`cargo [command] --target=t\`, this script
                should be invoked with the -t option using the same value (or else set the CARGO_BUILD_TARGET
                environment variable).  This will save the compiled artifacts to the appropiate locations
                in order to support cross-compilation to different target-triples than the host.
            "
            exit 0
            ;;
    esac
done
shift $((OPTIND - 1))

if [ -n "$profile" ] && [ -n "$json_diagnostic" ]; then echo "Ignoring option -p=$profile since option -j is set"
elif [ -z "$profile" ] && [ -z "$json_diagnostic" ]; then echo "One of -p and -j options must be set" && exit 2
fi

case "$#" in
    0)
        echo "Must supply positional arguments for the destination directory and one or more crates" && exit 2
        ;;
    1)
        echo "No crates to save." && exit 0
        ;;
esac

set -e
to=$1
shift 1

[ -d "$to" ] || mkdir "$to"
build_target=${build_target:-$CARGO_BUILD_TARGET}

cargo metadata --format-version 1 --locked \
  --filter-platform ${build_target:-$(rustc -vV | awk '/^host: .*/ {print $2}')} > metadata.json

target_dir=$(jq -r '.target_directory' metadata.json)

if [ -f "$json_diagnostic" ]; then
    deps=$(
        jq -c --arg crates "$*" -f /dev/stdin metadata.json << 'EOF'
        def get_deps($id; $nodes): [$id] + ($nodes[] | select(.id == $id) | .dependencies | map(get_deps(.; $nodes)));

        .resolve.nodes as $nodes |
        .packages | map(select(.name as $nm | any($crates | split(" ")[]; . == $nm)) | .id as $id |
            $nodes | .[] | select(.id == $id) | [$id] + .dependencies | map(get_deps(.; $nodes))
        ) |
        flatten | unique | sort
EOF
    )
    ver=$(cargo --version | awk '/^cargo .+ \(.+\)$/ { print $2 }')
    jq -r -s --arg v "$ver" --argjson deps "$deps" -f /dev/stdin "$json_diagnostic" > result.txt << 'EOF'

($v | split(".") | map(tonumber)) as $version |
(if $version[0] == 1 and $version[1] >= 77 then ".+#(?<x>.+)@.+" else "(?<x>.+) .+ \\(.+\\)" end) as $pattern |
map(select(.package_id as $id | any($deps[]; . == $id)) |
    (.package_id | sub($pattern; "\(.x)")) as $crate_proper |
    [.filenames[]?, .out_dir?] | map(select(. != null) | 
        if contains("/build/") then [ sub("(?<prefix>/.+)/build/(?<artifact>.+?)/.+";
            "\(.prefix)/build/\(.artifact)",
            "\(.prefix)/.fingerprint/\(.artifact)"
        )]
        elif contains("/deps/") then [ sub("(?<prefix>/.+)/deps/lib(?<crate>.+)\\-(?<hash>.+)\\.(?<ext>.+)";
            "\(.prefix)/deps/lib\(.crate)-\(.hash).\(.ext)",
            "\(.prefix)/deps/\(.crate)-\(.hash).d",
            "\(.prefix)/.fingerprint/\($crate_proper)-\(.hash)"
        )]
        else []
        end
    )
) | flatten | unique | .[]
EOF

    while IFS= read -r f; do
        artifact=${f#$target_dir/}
        dest=$to/$(dirname $artifact)
        mkdir -p $dest
        cp -rp $f $dest
    done < result.txt

    rm result.txt metadata.json
    printf "Saved the following crates' artifacts to $to:\n$(echo $deps | jq))\n"
    du -hd 2 $to
    exit 0
fi

jq -r --arg crates "$*" -f /dev/stdin metadata.json > result.json << 'EOF'
def is_proc(pkg): any(pkg.targets[]?.kind[]; . == "proc-macro");

def is_build(pkg): any(pkg.targets[]?.kind[]; . == "custom-build");

def get_crate($id; $proc; $build; $all_nodes; $all_packages):
    ($all_nodes[] | select(.id == $id)) as $node |
    ($all_packages[] | select(.id == $id)) as $pkg |

    [{"crate": $pkg.name, "proc": (is_proc($pkg) or $proc), "build": is_build($pkg)}] + (
        $node.dependencies | map(get_crate(.; is_proc($pkg) or $proc; is_build($pkg); $all_nodes; $all_packages))
    );

.packages as $pkgs |
.resolve.nodes as $nodes |
.packages | map(    
  select(.name as $nm | any($crates | split(" ")[]; . == $nm)) as $pkg |
  $nodes | .[] | select(.id == $pkg.id) |
  [{"crate": $pkg.name, "proc": is_proc($pkg), "build": is_build($pkg)}] + (
    .dependencies | map(get_crate(.; is_proc($pkg); is_build($pkg); $nodes; $pkgs))
  )
) |
flatten | unique | sort
EOF

mkdir -p $to/$profile/deps $to/$profile/.fingerprint $to/$profile/build

if [ -z "$build_target" ]; then
    jq -r 'map(.crate | gsub("\\-"; "_") as $c | "-name \"\($c)-*\" -o -name \"lib\($c)-*\"") | 
        join(" -o ")' result.json |
    xargs find "$target_dir/$profile/deps" | 
    xargs -I {} cp -rp {} "$to/$profile/deps"

    jq -r 'map("-name \(.crate)-*") | join(" -o ")' result.json | 
    xargs find "$target_dir/$profile/.fingerprint" |
    xargs -I {} cp -rp {} "$to/$profile/.fingerprint"

    jq -r 'map(select(.build) | "-name \(.crate)-*") | join(" -o ")' result.json | 
    xargs find "$target_dir/$profile/build" |
    xargs -I {} cp -rp {} "$to/$profile/build"
else
    jq -r 'map(select(.proc) | .crate | gsub("\\-"; "_") as $c | "-name \"\($c)-*\" -o -name \"lib\($c)-*\"") | 
        join(" -o ")' result.json |
    xargs find "$target_dir/$profile/deps" | 
    xargs -I {} cp -rp {} "$to/$profile/deps"

    jq -r 'map(select(.proc or .build) | "-name \(.crate)-*") | join(" -o ")' result.json |
    xargs find "$target_dir/$profile/.fingerprint" |
    xargs -I {} cp -rp {} "$to/$profile/.fingerprint"

    jq -r 'map(select(.build) | "-name \(.crate)-*") | join(" -o ")' result.json | 
    xargs find "$target_dir/$profile/build" |
    xargs -I {} cp -rp {} "$to/$profile/build"


    cross_dir=$build_target/$profile
    mkdir -p $to/$cross_dir/deps $to/$cross_dir/.fingerprint $to/$cross_dir/build

    jq -r 'map(select(.proc | not) | .crate | gsub("\\-"; "_") as $c | "-name \"\($c)-*\" -o -name \"lib\($c)-*\"") | 
        join(" -o ")' result.json |
    xargs find "$target_dir/$cross_dir/deps" | 
    xargs -I {} cp -rp {} "$to/$cross_dir/deps"

    jq -r 'map(select(.proc | not) | "-name \(.crate)-*") | join(" -o ")' result.json | 
    xargs find "$target_dir/$cross_dir/.fingerprint" |
    xargs -I {} cp -rp {} "$to/$cross_dir/.fingerprint"

    jq -r 'map(select(.build) | "-name \(.crate)-*") | join(" -o ")' result.json | 
    xargs find "$target_dir/$cross_dir/build" |
    xargs -I {} cp -rp {} "$to/$cross_dir/build"
fi

rm result.json metadata.json
printf "Saved the following crates' artifacts to $to:\n$(jq -r '.[].crate' result.json)\n"
du -hd 2 $to

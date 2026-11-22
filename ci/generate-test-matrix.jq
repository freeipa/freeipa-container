
def xcontains($element):
	. as $input |
	$element | to_entries | map($input[.key] == .value) | all
;

def unseen:
	[ (.singles | length), (.pairs | length) ]
;

def multiply:
	reduce .[] as $i (1; . * $i)
;

.["build-dist"] as $dist
| (.push.exclude // []) as $nopush
| [(.["fresh-dist"] // []) | .[] | select([ xcontains($nopush[]) ] | any | not)] as $fresh
| if $ARGS.named["job"] == "push-data"
then
	[ [ $fresh[].os ] | unique[] | . as $os
		| { "os": $os, "arch": [ $dist | map(select(.os == $os)) | .[] | [ . ] | select(all(contains($nopush[]) | not)) | .[].arch ] } ]
elif $ARGS.named["job"] == "push"
then
	[ $fresh[].os ] | unique
else
.[$ARGS.named.job]
| if . == null then error("Unknown job") end
| ($ARGS.named.count // .count | tonumber) as $count
| (.exclude // []) as $exclude
| .["upgrade-to-from"] as $upgrades
| ( $ARGS.named.seed // 42 | tonumber ) as $seed
| [ limit($count + 1; $seed % 2147483646 + 1 | recurse(. * 48271 % 2147483647)) ][1:] as $random

| del(.count, .exclude, .["upgrade-to-from"])
| . as $def

| [
	[ $dist | map(select($upgrades == null or $upgrades[.os])) | map({ dist: . }) ]
		+ [ keys_unsorted[] as $k | [ { $k: .[$k] | keys_unsorted[] } ] ]
	| combinations
	| add
	| { os: .dist.os, arch: .dist.arch } + .
	| if $upgrades then .["data-from"] = $upgrades[.os][] end
]
| map(select([$exclude[] as $e | xcontains($e)] | any | not))

| [ .[]
	| .dist as $d
	| ( [ to_entries[] | [.] | from_entries ] ) as $singles
	| ( [ to_entries[] | $def[ .key ][ .value ] // 1 ] | multiply ) as $multiply
	| if ( $fresh | any(xcontains($d)) ) then .["fresh-image"] = true end
	| if ( [ $nopush[] as $np | $d | xcontains($np) ] | any ) then .nopush = true end
	| {
		r: .,
		m: $multiply,
		singles: ( if ( $fresh | length ) > 0 and ( .["fresh-image"] | not ) then [] else $singles end ),
		pairs: [ $singles | range(0; length) as $i | range($i + 1; length) as $j | [.[$i], .[$j]] ],
		pairs_m: ( if .["fresh-image"] then 2 else 1 end )
	}
]

| if $count > length then debug("There are only \(length) input records, not \($count)") end
| reduce range([ $count, length ] | min) as $n (.;
	( .[$n:] | map(unseen) | max ) as $max
	| [ range($n; length) as $i | .[$i] as $r | select(($r | unseen | [.[0], .[1] * $r.pairs_m ]) >= $max) | range($r.m) | $i ] as $list

	| $list[ $random[$n] % ($list | length) ] as $selected_index
	| .[$selected_index] as $selected
	| .[$selected_index] = .[$n]
	| .[$n] = $selected
	| del(.[$n].r.dist)

	| reduce range($n + 1; length) as $i (.;
		.[$i].singles -= $selected.singles
		| .[$i].pairs -= $selected.pairs
	)
)
| .[:$count]
| map(.r)
| sort_by(.[])

end
